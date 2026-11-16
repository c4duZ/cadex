//! The memory agent's auto-improve proposals waiting for the owner (plan 22
//! phase H, 2026-11-16; memory.requireApproval, agent/improve.rs stages them).
//!
//! - `GET /cadex/memory/proposals?cwd&workspace`: the project's pending ones,
//!   as upstream's web triage page reads them
//!   (`list_pending_auto_improve_reviews`, ai-memory-web's pending.rs):
//!   `{"proposals":[{"id","title","path","kind","summary","created_at","body"}]}`
//!   (`summary` is the reviewer's rationale; `body` the proposed page text).
//! - `POST /cadex/memory/approve?id=ID` and `/reject?id=ID`: upstream's own
//!   decision path, the one its `/admin/pending-writes/{id}/approve|reject`
//!   handlers take (ai-memory-mcp's admin.rs at fa0ec25; upstream has no MCP
//!   tool for it): `Wiki::approve_auto_improve_proposal` (admission, the
//!   page written as a new version, the proposal marked approved) and
//!   `reject_auto_improve_proposal`. An approval is then committed to the
//!   wiki's git, as every page write here is. → `{"ok":true}`

use std::str::FromStr;
use std::sync::Arc;

use ai_memory_core::{ActorContext, AutoImproveProposalId};
use ai_memory_store::{ApproveAutoImproveProposalResult, PendingAutoImproveReview, RejectAutoImproveProposal, StoreError};
use ai_memory_wiki::{AdmissionContext, AdmissionOp, WikiError};
use axum::Json;
use axum::extract::State;
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use serde_json::{Value, json};

use super::{Ctx, Params, error, project_of};

/// Most proposals one answer carries (each with its whole body); upstream's
/// triage page reads 500 across every project.
const LIST_LIMIT: usize = 200;
/// The whole pending queue, read to find one id's project.
const QUEUE_LIMIT: usize = 10_000;
const REJECT_REASON: &str = "rejected by the owner in Cadex's Memory page";

fn row(review: PendingAutoImproveReview) -> Value {
    let s = review.summary;
    let created = jiff::Timestamp::from_microsecond(s.staged_at).map(|t| t.to_string()).unwrap_or_default();
    json!({
        "id": s.id.to_string(),
        "title": s.title,
        "path": s.target_path.as_str(),
        "kind": s.kind,
        "summary": review.rationale,
        "created_at": created,
        "body": review.body_markdown,
    })
}

pub(crate) async fn list(State(ctx): State<Arc<Ctx>>, axum::extract::Query(q): Params) -> Response {
    let project = match project_of(&ctx, &q).await {
        Ok(project) => project,
        Err(response) => return response,
    };
    let Some(scope) = project.ids else { return Json(json!({"proposals": []})).into_response() };
    match ctx.reader.list_pending_auto_improve_reviews(Some(scope), LIST_LIMIT).await {
        Ok(reviews) => Json(json!({"proposals": reviews.into_iter().map(row).collect::<Vec<_>>()})).into_response(),
        Err(e) => error(StatusCode::INTERNAL_SERVER_ERROR, &e.to_string()),
    }
}

/// The pending proposal `id` names, with its scope.
async fn pending(ctx: &Ctx, q: &std::collections::HashMap<String, String>) -> Result<PendingAutoImproveReview, Response> {
    let raw = q.get("id").filter(|i| !i.is_empty()).ok_or_else(|| error(StatusCode::BAD_REQUEST, "id is required"))?;
    let id = AutoImproveProposalId::from_str(raw).map_err(|e| error(StatusCode::BAD_REQUEST, &format!("invalid proposal id: {e}")))?;
    let queue = ctx
        .reader
        .list_pending_auto_improve_reviews(None, QUEUE_LIMIT)
        .await
        .map_err(|e| error(StatusCode::INTERNAL_SERVER_ERROR, &e.to_string()))?;
    queue.into_iter().find(|r| r.summary.id == id).ok_or_else(|| error(StatusCode::NOT_FOUND, "no pending proposal with this id"))
}

pub(crate) async fn approve(State(ctx): State<Arc<Ctx>>, axum::extract::Query(q): Params) -> Response {
    let review = match pending(&ctx, &q).await {
        Ok(review) => review,
        Err(response) => return response,
    };
    let s = &review.summary;
    let admission = AdmissionContext { op: AdmissionOp::WritePage, ..AdmissionContext::default() };
    let applied =
        ctx.wiki.approve_auto_improve_proposal(s.workspace_id, s.project_id, s.id, ActorContext::anonymous(), None, Some(admission)).await;
    match applied {
        Ok(ApproveAutoImproveProposalResult::Approved { .. }) => {
            let wiki = ctx.wiki.clone();
            let message = format!("auto-improve approved: {}", s.target_path.as_str());
            if let Ok(Err(e)) = tokio::task::spawn_blocking(move || wiki.commit_all(&message)).await {
                tracing::warn!(error = %e, "approved proposal not committed");
            }
            Json(json!({"ok": true})).into_response()
        }
        Ok(ApproveAutoImproveProposalResult::Conflict) => {
            error(StatusCode::CONFLICT, "the page changed since the proposal was made")
        }
        Err(WikiError::Store(StoreError::InvalidState(msg))) => error(StatusCode::CONFLICT, &msg),
        Err(e) => error(StatusCode::INTERNAL_SERVER_ERROR, &e.to_string()),
    }
}

pub(crate) async fn reject(State(ctx): State<Arc<Ctx>>, axum::extract::Query(q): Params) -> Response {
    let review = match pending(&ctx, &q).await {
        Ok(review) => review,
        Err(response) => return response,
    };
    let s = &review.summary;
    let decision = RejectAutoImproveProposal {
        workspace_id: s.workspace_id,
        project_id: s.project_id,
        proposal_id: s.id,
        reason: REJECT_REASON.to_owned(),
        actor: ActorContext::anonymous(),
        author_id: None,
    };
    match ctx.writer.reject_auto_improve_proposal(decision).await {
        Ok(()) => Json(json!({"ok": true})).into_response(),
        Err(StoreError::InvalidState(msg)) => error(StatusCode::CONFLICT, &msg),
        Err(e) => error(StatusCode::INTERNAL_SERVER_ERROR, &e.to_string()),
    }
}
