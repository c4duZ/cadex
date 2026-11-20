//! The two root-only queues of upstream's panel (plan 40 B), read as its web
//! handlers read them.
//!
//! - `GET extra/workstreams?page=N` (ai-memory-web's routes/workstreams.rs):
//!   `operational_workstreams`, 100 a page, ordered by the store (attention
//!   first, then recent activity) →
//!   `{"page","has_next","workstreams":[{"id","name","workspace","project",
//!   "status","latest_run_id","latest_agent","event_count","linked_harnesses",
//!   "last_active_at","latest_started_at","latest_ended_at"}]}`.
//! - `GET extra/review?project=<ws>/<proj>&sort=project|confidence-asc|
//!   confidence-desc|staged-desc` (routes/pending.rs): every project's
//!   pending auto-improve proposals, up to 500, sorted as upstream sorts →
//!   `{"total","project_count","truncated","sort","scopes":[{"workspace",
//!   "project","pending"}],"proposals":[…]}`, each proposal the Memory page's
//!   row (../proposals.rs) plus `workspace`, `project`, `operation`,
//!   `confidence`, `is_rule`, `rewrites_existing` and `edit_mode`.
//! - `POST extra/review/approve` and `extra/review/reject`, `{"id"[,"reason"]}`
//!   (plan 40 G): the Memory page's own decisions (../proposals.rs, upstream's
//!   pending-writes path), so the panel writes through the same code.

use std::sync::Arc;

use ai_memory_store::{AutoImproveProposalOperation, OperationalWorkstreamSummary, PendingAutoImproveReview};
use axum::Json;
use axum::extract::State;
use axum::response::{IntoResponse, Response};
use serde_json::{Value, json};

use super::super::Params;
use super::{PanelCtx, internal, micros, number};

const WORKSTREAM_PAGE: usize = 100;
const MAX_PAGE: usize = 10_000;
const REVIEW_LIMIT: usize = 500;
const SORTS: [&str; 4] = ["project", "confidence-asc", "confidence-desc", "staged-desc"];

fn workstream(s: OperationalWorkstreamSummary) -> Value {
    json!({
        "id": s.workstream_id.to_string(),
        "name": s.name,
        "workspace": s.workspace_name,
        "project": s.project_name,
        "status": s.status.as_str(),
        "latest_run_id": s.latest_run_id.map(|id| id.to_string()),
        "latest_agent": s.latest_agent.map(|a| a.as_str()),
        "event_count": s.event_count,
        "linked_harnesses": s.linked_harnesses.iter().map(|a| a.as_str()).collect::<Vec<_>>(),
        "last_active_at": micros(s.last_active_at),
        "latest_started_at": s.latest_started_at.and_then(micros),
        "latest_ended_at": s.latest_ended_at.and_then(micros),
    })
}

pub(crate) async fn workstreams(State(ctx): State<Arc<PanelCtx>>, axum::extract::Query(q): Params) -> Response {
    let page = match number(&q, "page") {
        Ok(n) => n.unwrap_or(1).clamp(1, MAX_PAGE),
        Err(r) => return r,
    };
    let offset = (page - 1).saturating_mul(WORKSTREAM_PAGE);
    let mut rows = match ctx.page.reader.operational_workstreams(WORKSTREAM_PAGE + 1, offset).await {
        Ok(rows) => rows,
        Err(e) => return internal(e),
    };
    let has_next = rows.len() > WORKSTREAM_PAGE;
    rows.truncate(WORKSTREAM_PAGE);
    let rows: Vec<Value> = rows.into_iter().map(workstream).collect();
    Json(json!({"page": page, "has_next": has_next, "workstreams": rows})).into_response()
}

/// Upstream's `display_scope`: quoted when a name holds a slash.
fn scope_label(workspace: &str, project: &str) -> String {
    if workspace.contains('/') || project.contains('/') {
        format!("{workspace:?}/{project:?}")
    } else {
        format!("{workspace}/{project}")
    }
}

/// Upstream's `sort_reviews`, the same keys and tie-breaks.
fn sort(reviews: &mut [PendingAutoImproveReview], by: &str) {
    reviews.sort_by(|a, b| {
        let by_scope = || scope_label(&a.workspace_name, &a.project_name).cmp(&scope_label(&b.workspace_name, &b.project_name));
        let by_staged = a.summary.staged_at.cmp(&b.summary.staged_at);
        let by_confidence = a.summary.confidence.total_cmp(&b.summary.confidence);
        match by {
            "confidence-asc" => by_confidence.then_with(by_scope).then(by_staged),
            "confidence-desc" => by_confidence.reverse().then_with(by_scope).then(by_staged),
            "staged-desc" => by_staged.reverse().then_with(by_scope),
            _ => by_scope().then(by_staged),
        }
    });
}

fn proposal(review: PendingAutoImproveReview) -> Value {
    let (workspace, project) = (review.workspace_name.clone(), review.project_name.clone());
    let s = &review.summary;
    let extra = json!({
        "workspace": workspace,
        "project": project,
        "operation": s.operation.as_str(),
        "confidence": s.confidence,
        "is_rule": s.target_path.as_str().starts_with("_rules/"),
        "rewrites_existing": s.operation != AutoImproveProposalOperation::Create,
        "edit_mode": review.edit_mode,
    });
    let mut row = super::super::proposals::row(review);
    if let (Some(row), Value::Object(extra)) = (row.as_object_mut(), extra) {
        row.extend(extra);
    }
    row
}

pub(crate) async fn review(State(ctx): State<Arc<PanelCtx>>, axum::extract::Query(q): Params) -> Response {
    let reader = &ctx.page.reader;
    let scopes = match reader.list_pending_auto_improve_scopes().await {
        Ok(scopes) => scopes,
        Err(e) => return internal(e),
    };
    // Upstream's filter key: the two names, as the select's value.
    let filter = q.get("project").and_then(|key| {
        scopes.iter().find(|s| format!("{}/{}", s.workspace_name, s.project_name) == *key)
    });
    let by = q.get("sort").map(String::as_str).filter(|s| SORTS.contains(s)).unwrap_or("project");
    let mut reviews = match reader
        .list_pending_auto_improve_reviews(filter.map(|s| (s.workspace_id, s.project_id)), REVIEW_LIMIT + 1)
        .await
    {
        Ok(reviews) => reviews,
        Err(e) => return internal(e),
    };
    let truncated = reviews.len() > REVIEW_LIMIT;
    reviews.truncate(REVIEW_LIMIT);
    sort(&mut reviews, by);
    let total: u64 = scopes.iter().map(|s| s.pending).sum();
    let listed: Vec<Value> =
        scopes.iter().map(|s| json!({"workspace": s.workspace_name, "project": s.project_name, "pending": s.pending})).collect();
    Json(json!({
        "total": total,
        "project_count": scopes.len(),
        "truncated": truncated,
        "sort": by,
        "scopes": listed,
        "proposals": reviews.into_iter().map(proposal).collect::<Vec<_>>(),
    }))
    .into_response()
}

#[derive(serde::Deserialize)]
pub(crate) struct Decision {
    id: String,
    #[serde(default)]
    reason: Option<String>,
}

fn as_query(d: Decision) -> axum::extract::Query<std::collections::HashMap<String, String>> {
    let mut q = std::collections::HashMap::from([("id".to_owned(), d.id)]);
    if let Some(reason) = d.reason {
        q.insert("reason".to_owned(), reason);
    }
    axum::extract::Query(q)
}

pub(crate) async fn approve(State(ctx): State<Arc<PanelCtx>>, Json(d): Json<Decision>) -> Response {
    super::super::proposals::approve(State(ctx.page.clone()), as_query(d)).await
}

pub(crate) async fn reject(State(ctx): State<Arc<PanelCtx>>, Json(d): Json<Decision>) -> Response {
    super::super::proposals::reject(State(ctx.page.clone()), as_query(d)).await
}
