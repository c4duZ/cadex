//! `GET extra/search?q=&scope=w/p|workspace=&project=&kind=&tier=&limit=&explain=1`
//! (plan 40 E): what upstream's search screen shows (ai-memory-web's
//! routes/search.rs at 411d90d, `handler`), as JSON. `/api/v1/search` has
//! neither the kind and tier filters, nor the recall trace, nor the recent
//! pages listed with no term; this route repeats the screen's steps:
//!
//! - a project (`scope`, or `workspace` + `project`): the hybrid ranker of
//!   `memory_query` (upstream's recall.rs `search_scopes`) with the engine's
//!   model, as api/search.rs, asking one hit more than shown to tell a cut
//!   list; with no term, the project's ten newest pages;
//! - every project: FTS (`search_pages_with_meta`), the time of that one
//!   stream as the trace; with no term, the ten newest pages of all.
//!
//! Answer: `{query, workspace, project, kind, tier, explain, filtered,
//! unknown_kind, truncated, max_results, hits:[{workspace, project, path,
//! title, snippet, trace}], kinds, tiers, scopes:[{workspace, projects}],
//! streams_active, embedder, reranker, timings:[{stream, ms}]}`; `snippet` is
//! upstream's HTML (`<mark>` around the match, the rest escaped), `trace`
//! only with `explain` in a project (search_trace.rs). The engine has no
//! reranker (`memory_query` here has none), so `reranker` is "none".

use std::collections::{BTreeMap, HashMap};
use std::sync::Arc;
use std::time::Instant;

use ai_memory_core::{ProjectId, Tier, WorkspaceId};
use ai_memory_store::{HybridSearch, PAGE_KINDS, PageFilter, StreamTimings, VectorQuery, highlighted_snippet_html};
use axum::Json;
use axum::extract::{Query, State};
use axum::response::{IntoResponse, Response};
use serde::Serialize;
use serde_json::json;

use super::search_trace::{HitTrace, hit_trace, timing_rows};
use super::{PanelCtx, bad, internal, number, scope};

/// Upstream's limits: 50 hits across projects, 20 in one, at most 100.
const GLOBAL_DEFAULT_LIMIT: usize = 50;
const SCOPED_DEFAULT_LIMIT: usize = 20;
const MAX_LIMIT: usize = 100;
const RECENT_LIMIT: usize = 10;

#[derive(Serialize)]
struct Hit {
    workspace: String,
    project: String,
    path: String,
    title: String,
    snippet: String,
    trace: Option<HitTrace>,
}

/// What the screen ran: the hits, whether cut, the limit, the trace's streams and times.
#[derive(Default)]
struct Ran {
    hits: Vec<Hit>,
    truncated: bool,
    limit: usize,
    streams: Vec<&'static str>,
    timings: Option<StreamTimings>,
}

fn non_empty(q: &HashMap<String, String>, key: &str) -> Option<String> {
    q.get(key).map(|v| v.trim()).filter(|v| !v.is_empty()).map(str::to_owned)
}

/// The project named by `scope` (wins) or `workspace` + `project`, as upstream reads them.
fn named_scope(q: &HashMap<String, String>) -> Result<Option<(String, String)>, Response> {
    if let Some(value) = non_empty(q, "scope") {
        return match value.split_once('/') {
            Some((w, p)) if !w.is_empty() && !p.is_empty() => Ok(Some((w.to_owned(), p.to_owned()))),
            _ => Err(bad("scope must be workspace/project")),
        };
    }
    match (non_empty(q, "workspace"), non_empty(q, "project")) {
        (Some(w), Some(p)) => Ok(Some((w, p))),
        (None, None) => Ok(None),
        _ => Err(bad("workspace and project must be provided together")),
    }
}

pub(crate) async fn handle(State(ctx): State<Arc<PanelCtx>>, Query(q): Query<HashMap<String, String>>) -> Response {
    let query = q.get("q").map(|v| v.trim().to_owned()).unwrap_or_default();
    let explain = q.get("explain").is_some_and(|v| matches!(v.as_str(), "1" | "true" | "on" | "yes"));
    let named = match named_scope(&q) {
        Ok(named) => named,
        Err(r) => return r,
    };
    let kind = non_empty(&q, "kind");
    let tier = match non_empty(&q, "tier") {
        Some(v) => match Tier::ALL.iter().find(|t| t.as_str().eq_ignore_ascii_case(&v)) {
            Some(t) => Some(t.as_str()),
            None => return bad("tier must be working, episodic, semantic or procedural"),
        },
        None => None,
    };
    let limit = match number(&q, "limit") {
        Ok(limit) => limit,
        Err(r) => return r,
    };
    let filter = PageFilter { kind: kind.as_deref(), tier, ..PageFilter::default() };
    let (mut workspace, mut project) = (String::new(), String::new());
    let ran = match named {
        Some((w, p)) => {
            let resolved = match scope(&ctx, &w, &p).await {
                Ok(resolved) => resolved,
                Err(r) => return r,
            };
            // Page links use the stored name (upstream's `project_name_by_id` step).
            project = match ctx.page.reader.project_name_by_id(resolved.workspace_id, resolved.project_id).await {
                Ok(Some(name)) => name,
                Ok(None) => return bad("project not found"),
                Err(e) => return internal(e),
            };
            workspace = w;
            let ids = (resolved.workspace_id, resolved.project_id);
            in_project(&ctx, ids, (&workspace, &project), &query, limit, explain, filter).await
        }
        None => everywhere(&ctx, &query, limit, explain, filter).await,
    };
    let ran = match ran {
        Ok(ran) => ran,
        Err(e) => return internal(e),
    };
    let scopes = match scope_groups(&ctx).await {
        Ok(groups) => groups,
        Err(e) => return internal(e),
    };
    let unknown_kind = kind.as_deref().filter(|k| !PAGE_KINDS.iter().any(|known| known.eq_ignore_ascii_case(k))).unwrap_or_default();
    let mut kinds: Vec<&str> = PAGE_KINDS.to_vec();
    if !unknown_kind.is_empty() {
        kinds.push(unknown_kind);
    }
    let embedder = ctx.sources.model.as_ref().map_or_else(|| "none".to_owned(), |e| format!("{} / {} (dim {})", e.provider(), e.model(), e.dim()));
    Json(json!({
        "query": query, "workspace": workspace, "project": project,
        "kind": kind.clone().unwrap_or_default(), "tier": tier.unwrap_or_default(), "explain": explain,
        "filtered": kind.is_some() || tier.is_some(), "unknown_kind": unknown_kind,
        "truncated": ran.truncated, "max_results": ran.limit, "hits": ran.hits,
        "kinds": kinds, "tiers": Tier::ALL.map(|t| t.as_str()), "scopes": scopes,
        "streams_active": ran.streams.join(", "), "embedder": embedder, "reranker": "none",
        "timings": ran.timings.as_ref().map(timing_rows).unwrap_or_default(),
    }))
    .into_response()
}

async fn in_project(
    ctx: &PanelCtx,
    ids: (WorkspaceId, ProjectId),
    names: (&str, &str),
    query: &str,
    limit: Option<usize>,
    explain: bool,
    filter: PageFilter<'_>,
) -> ai_memory_store::StoreResult<Ran> {
    let hit = |path: String, title: String, snippet: &str, trace| Hit {
        workspace: names.0.to_owned(),
        project: names.1.to_owned(),
        path,
        title,
        snippet: highlighted_snippet_html(snippet),
        trace,
    };
    let reader = &ctx.page.reader;
    if query.is_empty() {
        let recent = reader.recent_pages_for_project(ids.0, ids.1, RECENT_LIMIT).await?;
        let hits = recent.into_iter().map(|h| hit(h.path.as_str().to_owned(), h.title, &h.snippet, None)).collect();
        return Ok(Ran { hits, ..Ran::default() });
    }
    let limit = limit.unwrap_or(SCOPED_DEFAULT_LIMIT).clamp(1, MAX_LIMIT);
    let vector = match &ctx.sources.model {
        Some(model) => ai_memory_llm::embed_search_query(model.as_ref(), query).await,
        None => None,
    };
    let owner = super::api::actor_filter();
    let search = HybridSearch {
        query,
        vector: vector.as_ref().map(|v| VectorQuery { vector: &v.vector, provider: &v.provider, model: &v.model, dim: v.dim }),
        limit: limit + 1,
        expiry_cutoff_us: None,
        include_superseded: false,
        explain,
        owner: &owner,
        filter,
    };
    let (found, timings) = reader.hybrid_search_scopes(&[ids], search).await?;
    let truncated = found.len() > limit;
    let hits = found
        .into_iter()
        .take(limit)
        .enumerate()
        .map(|(n, (h, details))| {
            let trace = details.filter(|_| explain).map(|d| hit_trace(n + 1, h.rank, &d));
            hit(h.path.as_str().to_owned(), h.title, &h.snippet, trace)
        })
        .collect();
    Ok(Ran { hits, truncated, limit, streams: reader.active_streams(vector.is_some()), timings })
}

async fn everywhere(ctx: &PanelCtx, query: &str, limit: Option<usize>, explain: bool, filter: PageFilter<'_>) -> ai_memory_store::StoreResult<Ran> {
    let reader = &ctx.page.reader;
    let hit = |h: ai_memory_store::PageHitWithMeta| Hit {
        path: h.path.as_str().to_owned(),
        workspace: h.workspace_name,
        project: h.project_name,
        title: h.title,
        snippet: highlighted_snippet_html(&h.snippet),
        trace: None,
    };
    if query.is_empty() {
        let recent = reader.recent_pages_global(RECENT_LIMIT, None).await?;
        return Ok(Ran { hits: recent.into_iter().map(hit).collect(), ..Ran::default() });
    }
    let limit = limit.unwrap_or(GLOBAL_DEFAULT_LIMIT).clamp(1, MAX_LIMIT);
    let started = explain.then(Instant::now);
    let raw = reader.search_pages_with_meta(query.to_owned(), limit + 1, None, None, filter).await?;
    let timings = started.map(|s| StreamTimings { fts_ms: Some(s.elapsed().as_secs_f64() * 1000.0), ..StreamTimings::default() });
    let truncated = raw.len() > limit;
    let streams = if explain { vec!["fts"] } else { Vec::new() };
    Ok(Ran { hits: raw.into_iter().take(limit).map(hit).collect(), truncated, limit, streams, timings })
}

/// The scope selector's options: projects by workspace, both by name (upstream's `scope_groups`).
async fn scope_groups(ctx: &PanelCtx) -> ai_memory_store::StoreResult<Vec<serde_json::Value>> {
    let mut by_workspace: BTreeMap<String, Vec<String>> = BTreeMap::new();
    for s in ctx.page.reader.list_projects_with_stats(None).await? {
        by_workspace.entry(s.workspace_name).or_default().push(s.project_name);
    }
    Ok(by_workspace
        .into_iter()
        .map(|(workspace, mut projects)| {
            projects.sort();
            json!({"workspace": workspace, "projects": projects})
        })
        .collect())
}
