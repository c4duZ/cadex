//! The overview's extras and the inbox counter (plan 40 B), what upstream's
//! `/web/` (routes/index.rs) and `/web/inbox/notifications`
//! (routes/notifications.rs) read beyond `/api/v1/projects`.
//!
//! - `GET extra/home` →
//!   `{"projects":[{"workspace","project","agents":[kind],"pending_inbox"}],
//!   "capture":{"accepted","dropped_by_policy","shed_saturated","shed_rate_limited"}}`:
//!   one row per project of `list_projects_with_stats`, in its order, with
//!   the registered agents (`registered_agents`, wire names in upstream's
//!   order) and the messages waiting (`pending_inbox_counts`, 0 when none);
//!   `capture` is upstream's "hook capture health" block, from this engine's
//!   own counters since it started (shown to root only, which the owner is).
//! - `GET extra/inbox/notifications` → upstream's JSON as is:
//!   `{"pending","project_count","projects":[{"workspace","project","pending"}]}`
//!   (the five busiest projects).

use std::collections::HashMap;
use std::sync::Arc;

use axum::Json;
use axum::extract::State;
use axum::response::{IntoResponse, Response};
use serde_json::{Value, json};

use super::{PanelCtx, internal};

/// Projects the notifications name, as upstream's handler takes.
const NOTIFIED_PROJECTS: usize = 5;

pub(crate) async fn home(State(ctx): State<Arc<PanelCtx>>) -> Response {
    let reader = &ctx.page.reader;
    let read = tokio::try_join!(
        reader.list_projects_with_stats(None),
        reader.pending_inbox_counts(None),
        reader.registered_agents(None),
    );
    let (summaries, counts, registered) = match read {
        Ok(read) => read,
        Err(e) => return internal(e),
    };
    let mut agents: HashMap<(String, String), Vec<&'static str>> = HashMap::new();
    for agent in registered {
        agents.entry((agent.workspace, agent.project)).or_default().push(agent.agent.as_str());
    }
    let pending: HashMap<(String, String), u64> =
        counts.into_iter().map(|c| ((c.workspace_name, c.project_name), c.pending)).collect();
    let projects: Vec<Value> = summaries
        .into_iter()
        .map(|s| {
            let key = (s.workspace_name, s.project_name);
            json!({
                "workspace": key.0,
                "project": key.1,
                "agents": agents.get(&key).cloned().unwrap_or_default(),
                "pending_inbox": pending.get(&key).copied().unwrap_or(0),
            })
        })
        .collect();
    let m = ctx.sources.ingest.snapshot();
    Json(json!({
        "projects": projects,
        "capture": {
            "accepted": m.accepted,
            "dropped_by_policy": m.dropped_by_policy,
            "shed_saturated": m.shed_saturated,
            "shed_rate_limited": m.shed_rate_limited,
        },
    }))
    .into_response()
}

pub(crate) async fn notifications(State(ctx): State<Arc<PanelCtx>>) -> Response {
    let mut counts = match ctx.page.reader.pending_inbox_counts(None).await {
        Ok(counts) => counts,
        Err(e) => return internal(e),
    };
    // Upstream's order: busiest first, then by name.
    counts.sort_by(|a, b| {
        b.pending
            .cmp(&a.pending)
            .then_with(|| a.workspace_name.cmp(&b.workspace_name))
            .then_with(|| a.project_name.cmp(&b.project_name))
    });
    let pending = counts.iter().fold(0_u64, |n, c| n.saturating_add(c.pending));
    let projects: Vec<Value> = counts
        .iter()
        .take(NOTIFIED_PROJECTS)
        .map(|c| json!({"workspace": c.workspace_name, "project": c.project_name, "pending": c.pending}))
        .collect();
    Json(json!({"pending": pending, "project_count": counts.len(), "projects": projects})).into_response()
}
