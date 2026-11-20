//! The inbox's writes (plan 40 F): a new message to an agent, and editing
//! one still queued. They mirror upstream's browser routes (ai-memory-web's
//! routes/inbox.rs `send`, `begin_edit`, `save_edit`, `release_edit`, at
//! 411d90d): the same checks, limits, refusal words and store calls. The
//! browser checks (the UI header, the origin, sign-in, the write
//! capability) stay out: the request comes over the owner's socket with the
//! session token, as root does upstream.
//!
//! - `POST extra/messages`, `{"from_workspace","from_project","to_workspace",
//!   "to_project","to_agent","subject","body"}` → 201
//!   `{"message_id","state":"pending"}`.
//! - `POST extra/messages/{id}/edit`, `{"workspace","project"}` (the mailbox
//!   it sits in) → `{"message_id","state","subject","body"}`: held, agents
//!   cannot collect it.
//! - `POST extra/messages/{id}/save`, plus `subject` and `body` → back in the
//!   queue with the new text; `…/release` → back unchanged. Both
//!   `{"message_id","state":"pending"}`.
//!
//! Sending never starts an agent: the message waits for its next inbox check.

use std::sync::Arc;

use ai_memory_core::{ActorContext, AgentKind, MessageId, MessageNature, NewAgentMessage, OwnerFilter, ProjectId, WorkspaceId};
use ai_memory_store::{ProjectAccess, lookup_existing_scope_guarded};
use axum::Json;
use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use serde::Deserialize;
use serde_json::json;

use super::super::error;
use super::{PanelCtx, internal, scope};

/// Upstream's limits, in characters.
const BODY_MAX: usize = 8_000;
const SUBJECT_MAX: usize = 200;
const TOO_LONG: &str = "Enter a message up to 8,000 characters and a subject up to 200 characters.";

#[derive(Deserialize)]
pub(crate) struct Compose {
    from_workspace: String,
    from_project: String,
    to_workspace: String,
    to_project: String,
    to_agent: String,
    #[serde(default)]
    subject: String,
    body: String,
}

#[derive(Deserialize)]
pub(crate) struct Edit {
    workspace: String,
    project: String,
    #[serde(default)]
    subject: Option<String>,
    #[serde(default)]
    body: Option<String>,
}

fn fits(subject: &str, body: &str) -> bool {
    !body.trim().is_empty() && body.chars().count() <= BODY_MAX && subject.chars().count() <= SUBJECT_MAX
}

pub(crate) async fn send(State(ctx): State<Arc<PanelCtx>>, Json(input): Json<Compose>) -> Response {
    let source = match scope(&ctx, &input.from_workspace, &input.from_project).await {
        Ok(s) => s,
        Err(r) => return r,
    };
    let target = match scope(&ctx, &input.to_workspace, &input.to_project).await {
        Ok(s) => s,
        Err(r) => return r,
    };
    let agent = AgentKind::from_wire(&input.to_agent);
    if agent.as_str() != input.to_agent {
        return error(StatusCode::BAD_REQUEST, "Select a registered agent.");
    }
    // Upstream's check: the agent has a session recorded in the recipient project.
    match ctx.page.reader.agent_usage(target.workspace_id, target.project_id, OwnerFilter::Any).await {
        Ok(rows) if rows.iter().any(|r| r.agent == input.to_agent) => {}
        Ok(_) => return error(StatusCode::BAD_REQUEST, "That agent has no registered session in the recipient project."),
        Err(e) => return internal(e),
    }
    if !fits(&input.subject, &input.body) {
        return error(StatusCode::BAD_REQUEST, TOO_LONG);
    }
    let message = NewAgentMessage {
        from_workspace_id: source.workspace_id,
        from_project_id: source.project_id,
        from_agent: AgentKind::Other,
        from_session_id: None,
        // owner_stamp(no identity, operators not distinguished): none, as upstream's single user.
        from_owner_user: None,
        to_workspace_id: target.workspace_id,
        to_project_id: target.project_id,
        to_agent: Some(agent),
        subject: Some(input.subject.trim().to_owned()),
        body: input.body.trim().to_owned(),
        nature: MessageNature::Unknown,
        evidence: None,
    };
    match ctx.page.wiki.send_agent_message(message, ActorContext::anonymous()).await {
        Ok(id) => (StatusCode::CREATED, Json(json!({"message_id": id.to_string(), "state": "pending"}))).into_response(),
        Err(ai_memory_wiki::WikiError::Store(ai_memory_store::StoreError::InvalidState(_))) => {
            error(StatusCode::CONFLICT, "This inbox is full. An agent must collect pending mail first.")
        }
        Err(e) => {
            tracing::warn!(error = %e, "panel message refused");
            error(StatusCode::FORBIDDEN, "The message could not be queued. Check project access and message admission policy.")
        }
    }
}

/// The message an edit targets, as upstream's `editable_message` finds it:
/// in the named mailbox, and sent from a project that exists.
async fn editable(ctx: &PanelCtx, raw_id: &str, input: &Edit) -> Result<(WorkspaceId, ProjectId, MessageId), Response> {
    let id = raw_id.parse::<MessageId>().map_err(|_| error(StatusCode::BAD_REQUEST, "That is not a message id."))?;
    let target = scope(ctx, &input.workspace, &input.project).await?;
    let reader = &ctx.page.reader;
    let message = reader
        .message_in_mailbox(target.workspace_id, target.project_id, id)
        .await
        .map_err(internal)?
        .ok_or_else(|| error(StatusCode::NOT_FOUND, "That message is not in this mailbox."))?;
    let projects = reader.list_projects_with_stats(None).await.map_err(internal)?;
    let origin = projects
        .into_iter()
        .find(|p| {
            p.workspace_id == message.origin.from_workspace_id.to_string() && p.project_id == message.origin.from_project_id.to_string()
        })
        .ok_or_else(|| error(StatusCode::FORBIDDEN, "You cannot edit mail sent from a project you cannot write to."))?;
    lookup_existing_scope_guarded(reader, &origin.workspace_name, &origin.project_name, None, ProjectAccess::Write)
        .await
        .map_err(|e| error(StatusCode::NOT_FOUND, &e.to_string()))?;
    Ok((target.workspace_id, target.project_id, id))
}

pub(crate) async fn begin_edit(State(ctx): State<Arc<PanelCtx>>, Path(raw_id): Path<String>, Json(input): Json<Edit>) -> Response {
    let (ws, proj, id) = match editable(&ctx, &raw_id, &input).await {
        Ok(t) => t,
        Err(r) => return r,
    };
    match ctx.page.wiki.begin_agent_message_edit(ws, proj, id).await {
        Ok(Some(m)) => Json(json!({
            "message_id": m.id.to_string(),
            "state": m.state.as_str(),
            "subject": m.subject.unwrap_or_default(),
            "body": m.body,
        }))
        .into_response(),
        Ok(None) => error(StatusCode::CONFLICT, "An agent already collected this message, or it is no longer queued."),
        Err(e) => internal(e),
    }
}

pub(crate) async fn save_edit(State(ctx): State<Arc<PanelCtx>>, Path(raw_id): Path<String>, Json(input): Json<Edit>) -> Response {
    let (ws, proj, id) = match editable(&ctx, &raw_id, &input).await {
        Ok(t) => t,
        Err(r) => return r,
    };
    let body = input.body.clone().unwrap_or_default();
    let subject = input.subject.clone().unwrap_or_default();
    if !fits(&subject, &body) {
        return error(StatusCode::BAD_REQUEST, TOO_LONG);
    }
    match ctx
        .page
        .wiki
        .save_agent_message_edit(ws, proj, id, Some(subject.trim().to_owned()), body.trim().to_owned(), ActorContext::anonymous())
        .await
    {
        Ok(true) => Json(json!({"message_id": id.to_string(), "state": "pending"})).into_response(),
        Ok(false) => error(StatusCode::CONFLICT, "This message is no longer being edited."),
        Err(e) => {
            tracing::warn!(error = %e, "panel message edit refused");
            error(StatusCode::FORBIDDEN, "The message could not be saved. Check project access and message admission policy.")
        }
    }
}

pub(crate) async fn release_edit(State(ctx): State<Arc<PanelCtx>>, Path(raw_id): Path<String>, Json(input): Json<Edit>) -> Response {
    let (ws, proj, id) = match editable(&ctx, &raw_id, &input).await {
        Ok(t) => t,
        Err(r) => return r,
    };
    match ctx.page.wiki.release_agent_message_edit(ws, proj, id).await {
        Ok(true) => Json(json!({"message_id": id.to_string(), "state": "pending"})).into_response(),
        Ok(false) => error(StatusCode::CONFLICT, "This message is no longer being edited."),
        Err(e) => internal(e),
    }
}
