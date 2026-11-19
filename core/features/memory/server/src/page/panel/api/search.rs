//! `GET .../api/v1/search?q=&limit=&workspace=&project=&scope=w/p,...`, as
//! upstream's `/api/v1/search` (ai-memory-web's routes/api.rs at 411d90d:
//! `search_handler`, `search_with_request`, `scoped_search_mode`,
//! `enrich_hits`; the query reading, `SearchQuery::from_raw`,
//! `decode_query_component` and `parse_scope_param`, **copied**). With no
//! project it is FTS over every project, as `memory_query(global=true)`;
//! with one (or `scope`s) it is the hybrid ranker `memory_query` runs, the
//! steps of upstream's recall.rs `search_scopes` with the engine's own model
//! (loaded on demand, text only until it is there) and no reranker, as the
//! engine's `memory_query` has none. Upstream's `api_router`, built without
//! a model, skips the vector stream; with `--no-embeddings` the two agree
//! (tests/panel_api.rs).

use std::sync::Arc;

use ai_memory_core::{ProjectId, WorkspaceId};
use ai_memory_store::{HybridSearch, PageFilter, PageHit, ScopeName, VectorQuery, resolve_many_existing_scopes_guarded};
use axum::Json;
use axum::extract::{RawQuery, State};
use axum::response::{IntoResponse, Response};
use serde::Serialize;

use super::{actor_filter, bad_request, default_limit, internal, lookup, scope_error, trimmed};
use crate::page::panel::PanelCtx;

const MAX_SEARCH_SCOPES: usize = 25;

#[derive(Serialize)]
struct ApiSearchHit {
    workspace: String,
    project: String,
    path: String,
    title: String,
    kind: String,
    snippet: String,
    rank: f64,
}

/// The request, as upstream's `SearchQuery` reads it.
struct SearchQuery {
    q: String,
    workspace: Option<String>,
    project: Option<String>,
    scopes: Vec<(String, String)>,
    limit: usize,
}

fn hex_value(byte: u8) -> Option<u8> {
    match byte {
        b'0'..=b'9' => Some(byte - b'0'),
        b'a'..=b'f' => Some(byte - b'a' + 10),
        b'A'..=b'F' => Some(byte - b'A' + 10),
        _ => None,
    }
}

fn decode(raw: &str) -> Result<String, Response> {
    let invalid = || bad_request("invalid percent-encoding in query");
    let (raw, mut bytes, mut i) = (raw.as_bytes(), Vec::with_capacity(raw.len()), 0);
    while i < raw.len() {
        match raw[i] {
            b'+' => bytes.push(b' '),
            b'%' => {
                if i + 2 >= raw.len() {
                    return Err(invalid());
                }
                let hi = hex_value(raw[i + 1]).ok_or_else(invalid)?;
                let lo = hex_value(raw[i + 2]).ok_or_else(invalid)?;
                bytes.push((hi << 4) | lo);
                i += 2;
            }
            byte => bytes.push(byte),
        }
        i += 1;
    }
    String::from_utf8(bytes).map_err(|_| bad_request("query must be valid UTF-8"))
}

fn parse_scope(raw: &str) -> Result<(String, String), Response> {
    let refuse = || bad_request("scope must use the workspace/project format");
    let (workspace, project) = raw.split_once('/').ok_or_else(refuse)?;
    let (workspace, project) = (workspace.trim(), project.trim());
    if workspace.is_empty() || project.is_empty() || project.contains('/') {
        return Err(refuse());
    }
    Ok((workspace.to_owned(), project.to_owned()))
}

fn read_query(raw: Option<&str>) -> Result<SearchQuery, Response> {
    let mut query = SearchQuery { q: String::new(), workspace: None, project: None, scopes: Vec::new(), limit: default_limit() };
    let mut scope_params = Vec::new();
    for pair in raw.unwrap_or_default().split('&').filter(|p| !p.is_empty()) {
        let (key, value) = pair.split_once('=').unwrap_or((pair, ""));
        let (key, value) = (decode(key)?, decode(value)?);
        match key.as_str() {
            "limit" => query.limit = value.parse().map_err(|_| bad_request("limit must be an integer"))?,
            "project" => query.project = Some(value),
            "q" | "query" => query.q = value,
            "scope" => scope_params.push(value),
            "workspace" => query.workspace = Some(value),
            _ => {}
        }
    }
    for raw in scope_params.iter().flat_map(|s| s.split(',')).map(str::trim).filter(|s| !s.is_empty()) {
        query.scopes.push(parse_scope(raw)?);
    }
    Ok(query)
}

/// The scopes searched: `None` is every project (FTS).
async fn scopes_of(ctx: &PanelCtx, q: &SearchQuery) -> Result<Option<Vec<(WorkspaceId, ProjectId)>>, Response> {
    if !q.scopes.is_empty() {
        if trimmed(q.workspace.as_deref()).is_some() || trimmed(q.project.as_deref()).is_some() {
            return Err(bad_request("scopes cannot be combined with workspace/project"));
        }
        if q.scopes.len() > MAX_SEARCH_SCOPES {
            return Err(bad_request(&format!("at most {MAX_SEARCH_SCOPES} scopes are allowed")));
        }
        let names: Vec<_> = q.scopes.iter().map(|(w, p)| ScopeName::new(w, p)).collect();
        let resolved = resolve_many_existing_scopes_guarded(&ctx.page.reader, &names, MAX_SEARCH_SCOPES, None, ai_memory_store::ProjectAccess::Read)
            .await
            .map_err(scope_error)?;
        return Ok(Some(resolved.into_iter().map(|s| (s.workspace_id, s.project_id)).collect()));
    }
    match (trimmed(q.workspace.as_deref()), trimmed(q.project.as_deref())) {
        (Some(workspace), Some(project)) => Ok(Some(vec![lookup(ctx, workspace, project).await?])),
        (None, None) => Ok(None),
        _ => Err(bad_request("workspace and project must be provided together")),
    }
}

/// `memory_query`'s ranking of `term` over `scopes`: the model's query
/// vector when there is one, latest unexpired pages only.
async fn hybrid(ctx: &PanelCtx, scopes: &[(WorkspaceId, ProjectId)], term: &str, limit: usize) -> ai_memory_store::StoreResult<Vec<PageHit>> {
    let vector = match &ctx.sources.model {
        Some(model) => ai_memory_llm::embed_search_query(model.as_ref(), term).await,
        None => None,
    };
    let owner = actor_filter();
    let search = HybridSearch {
        query: term,
        vector: vector.as_ref().map(|v| VectorQuery { vector: &v.vector, provider: &v.provider, model: &v.model, dim: v.dim }),
        limit,
        expiry_cutoff_us: None,
        include_superseded: false,
        explain: false,
        owner: &owner,
        filter: PageFilter::default(),
    };
    let (hits, _) = ctx.page.reader.hybrid_search_scopes(scopes, search).await?;
    Ok(hits.into_iter().take(limit).map(|(hit, _)| hit).collect())
}

pub(super) async fn handle(State(ctx): State<Arc<PanelCtx>>, RawQuery(raw): RawQuery) -> Response {
    let q = match read_query(raw.as_deref()) {
        Ok(q) => q,
        Err(r) => return r,
    };
    let term = q.q.trim().to_owned();
    if term.is_empty() {
        return Json(Vec::<ApiSearchHit>::new()).into_response();
    }
    let limit = q.limit.clamp(1, 100);
    let hits = match scopes_of(&ctx, &q).await {
        Ok(None) => ctx.page.reader.search_pages(term, limit, None).await,
        Ok(Some(scopes)) => hybrid(&ctx, &scopes, &term, limit).await,
        Err(r) => return r,
    };
    let hits = match hits {
        Ok(hits) => hits,
        Err(e) => return internal(e),
    };
    // Upstream's `enrich_hits`: each hit's names and kind from its page.
    let mut out = Vec::with_capacity(hits.len());
    for hit in hits {
        match ctx.page.reader.page_meta_by_id(hit.id).await {
            Ok(Some(meta)) => out.push(ApiSearchHit {
                workspace: meta.workspace_name,
                project: meta.project_name,
                path: meta.path,
                title: hit.title,
                kind: meta.kind,
                snippet: ai_memory_store::highlighted_snippet_html(&hit.snippet),
                rank: hit.rank,
            }),
            Ok(None) => {}
            Err(e) => return internal(e),
        }
    }
    Json(out).into_response()
}
