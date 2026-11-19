//! A workspace's and a project's overview, the briefing and the handoffs,
//! as upstream's `/api/v1` answers them (ai-memory-web's routes/api.rs at
//! 411d90d: `overview_handler`, `project_overview_handler`,
//! `briefing_handler`, `handoffs_handler`), the same reads and JSON. The
//! owner is root with no actor: upstream's `serves_handoff_body` serves the
//! handoff bodies, and `all_owners=true` is allowed.

use std::sync::Arc;

use ai_memory_core::{Handoff, HandoffState, OwnerFilter};
use ai_memory_store::{BriefingSnapshot, HealthPage};
use axum::Json;
use axum::extract::{Path, Query, State};
use axum::response::{IntoResponse, Response};
use serde::{Deserialize, Serialize};
use serde_json::json;

use super::{actor_filter, bad_request, default_limit, internal, lookup, not_found};
use crate::page::panel::PanelCtx;

#[derive(Serialize)]
struct ApiOverview {
    handoff: Option<ApiHandoff>,
    briefing: BriefingSnapshot,
    health: ApiHealth,
}

#[derive(Serialize)]
struct ApiHandoff {
    agent: String,
    at: String,
    project: String,
    summary: String,
    open_questions: Vec<String>,
    next_steps: Vec<String>,
}

#[derive(Serialize)]
struct ApiHealth {
    stale: u64,
    duplicates: u64,
    contradictions: u64,
    orphans: u64,
    audited_at: Option<String>,
    stale_pages: Vec<HealthPage>,
    duplicate_pages: Vec<HealthPage>,
    orphan_pages: Vec<HealthPage>,
}

#[derive(Deserialize)]
pub(super) struct LimitQuery {
    #[serde(default = "default_limit")]
    limit: usize,
}

#[derive(Deserialize)]
pub(super) struct HandoffListQuery {
    #[serde(default)]
    state: Option<String>,
    #[serde(default = "default_handoff_limit")]
    limit: usize,
    #[serde(default)]
    all_owners: bool,
}

const fn default_handoff_limit() -> usize {
    50
}

fn card(h: Handoff, project: String) -> ApiHandoff {
    ApiHandoff {
        agent: h.origin.from_agent.as_str().to_owned(),
        at: h.lifecycle.created_at.to_string(),
        project,
        summary: h.content.summary,
        open_questions: h.content.open_questions,
        next_steps: h.content.next_steps,
    }
}

fn health(counts: (u64, u64, u64), detail: ai_memory_store::HealthDetail) -> ApiHealth {
    let (stale, duplicates, orphans) = counts;
    ApiHealth {
        stale,
        duplicates,
        contradictions: 0,
        orphans,
        audited_at: None,
        stale_pages: detail.stale,
        duplicate_pages: detail.duplicates,
        orphan_pages: detail.orphans,
    }
}

pub(super) async fn workspace(State(ctx): State<Arc<PanelCtx>>, Path(workspace): Path<String>, Query(q): Query<LimitQuery>) -> Response {
    let reader = &ctx.page.reader;
    let ws = match reader.find_workspace(workspace.clone()).await {
        Ok(Some(ws)) => ws,
        Ok(None) => return not_found(&format!("workspace '{workspace}' not found")),
        Err(e) => return internal(e),
    };
    let limit = q.limit.clamp(1, 100);
    let handoff = match reader.latest_open_handoff_for_workspace(ws, actor_filter(), None).await {
        Ok(Some(h)) => match reader.project_name_by_id(ws, h.scope.project_id).await {
            Ok(name) => Some(card(h, name.unwrap_or_default())),
            Err(e) => return internal(e),
        },
        Ok(None) => None,
        Err(e) => return internal(e),
    };
    let read = tokio::try_join!(
        reader.briefing_for_workspace(ws, limit, actor_filter(), None),
        reader.memory_health_for_workspace(ws, None),
        reader.health_detail_for_workspace(ws, limit, None),
    );
    match read {
        Ok((briefing, counts, detail)) => Json(ApiOverview { handoff, briefing, health: health(counts, detail) }).into_response(),
        Err(e) => internal(e),
    }
}

pub(super) async fn project(
    State(ctx): State<Arc<PanelCtx>>,
    Path((workspace, project)): Path<(String, String)>,
    Query(q): Query<LimitQuery>,
) -> Response {
    let (ws, proj) = match lookup(&ctx, &workspace, &project).await {
        Ok(ids) => ids,
        Err(r) => return r,
    };
    let reader = &ctx.page.reader;
    let limit = q.limit.clamp(1, 100);
    let read = tokio::try_join!(
        reader.latest_open_handoff(ws, proj, None, actor_filter()),
        reader.briefing_for_project(ws, proj, limit, actor_filter(), false),
        reader.memory_health_for_project(ws, proj),
        reader.health_detail_for_project(ws, proj, limit),
    );
    match read {
        Ok((handoff, briefing, counts, detail)) => Json(ApiOverview {
            handoff: handoff.map(|h| card(h, project.clone())),
            briefing,
            health: health(counts, detail),
        })
        .into_response(),
        Err(e) => internal(e),
    }
}

pub(super) async fn briefing(
    State(ctx): State<Arc<PanelCtx>>,
    Path((workspace, project)): Path<(String, String)>,
    Query(q): Query<LimitQuery>,
) -> Response {
    let (ws, proj) = match lookup(&ctx, &workspace, &project).await {
        Ok(ids) => ids,
        Err(r) => return r,
    };
    match ctx.page.reader.briefing_for_project(ws, proj, q.limit.clamp(1, 100), actor_filter(), false).await {
        Ok(briefing) => Json(briefing).into_response(),
        Err(e) => internal(e),
    }
}

pub(super) async fn handoffs(
    State(ctx): State<Arc<PanelCtx>>,
    Path((workspace, project)): Path<(String, String)>,
    Query(q): Query<HandoffListQuery>,
) -> Response {
    let (ws, proj) = match lookup(&ctx, &workspace, &project).await {
        Ok(ids) => ids,
        Err(r) => return r,
    };
    let state = match q.state.as_deref().map(str::trim) {
        None | Some("") => None,
        Some(raw) => match raw.parse::<HandoffState>() {
            Ok(s) => Some(s),
            Err(_) => return bad_request(&format!("unknown handoff state: {raw}")),
        },
    };
    // Root may ask for every owner's; either way root reads the bodies.
    let owner = if q.all_owners { OwnerFilter::Any } else { actor_filter() };
    let rows = match ctx.page.reader.list_handoffs(ws, proj, state, owner, q.limit.clamp(1, 200)).await {
        Ok(rows) => rows,
        Err(e) => return internal(e),
    };
    // Upstream's `ApiHandoffEntry`, its fields in its order; `redacted` is
    // always false for root.
    let entries: Vec<serde_json::Value> = rows
        .into_iter()
        .map(|h| {
            let mut entry = serde_json::Map::new();
            entry.insert("id".into(), json!(h.scope.id.to_string()));
            entry.insert("agent".into(), json!(h.origin.from_agent.as_str()));
            entry.insert("at".into(), json!(h.lifecycle.created_at.to_string()));
            entry.insert("state".into(), json!(h.lifecycle.state.as_str()));
            entry.insert("summary".into(), json!(h.content.summary));
            entry.insert("open_questions".into(), json!(h.content.open_questions));
            entry.insert("next_steps".into(), json!(h.content.next_steps));
            entry.insert("redacted".into(), json!(false));
            entry.insert("files_touched".into(), json!(h.content.files_touched));
            let optional = [
                ("cwd", h.origin.cwd.map(|c| c.to_string())),
                ("owner", h.origin.owner_user),
                ("accepted_by", h.lifecycle.accepted_by_user),
                ("accepted_at", h.lifecycle.accepted_at.map(|t| t.to_string())),
            ];
            for (key, value) in optional {
                if let Some(value) = value {
                    entry.insert(key.into(), json!(value));
                }
            }
            serde_json::Value::Object(entry)
        })
        .collect();
    Json(json!({"handoffs": entries})).into_response()
}
