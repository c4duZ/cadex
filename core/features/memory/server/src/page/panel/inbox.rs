//! `GET extra/inbox?workspace&project&box=inbox|outbox&state&offset` (plan
//! 40 B): the reading side of upstream's inbox page (ai-memory-web's
//! routes/inbox.rs `handler`), with its rules: no project named picks the
//! first one with mail waiting, else the first project; the inbox shows the
//! waiting messages unless `state` says otherwise (`state=` blank is every
//! state); 50 a page, newest first, `more` when there is another page.
//! Sending and editing stay out: the panel only reads.
//!
//! → `{"workspace","project","box","state","pending_total","pending_projects",
//! "scopes":[{"workspace","project","pending"}],"editing_count",
//! "recipients":[{"workspace","project","agent"}],"more",
//! "messages":[{"id","subject","body","from","to","from_agent","to_agent",
//! "state","nature","created_at","claimed_at"}]}`. `from` and `to` are
//! "workspace / project", as upstream prints them; `subject` is null when
//! the message has none.

use std::collections::HashMap;
use std::sync::Arc;

use ai_memory_core::{MessageBox, MessageState, ProjectId};
use ai_memory_store::{ProjectAccess, lookup_project_id_guarded};
use axum::Json;
use axum::extract::State;
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use serde_json::{Value, json};

use super::super::{Params, error};
use super::{PanelCtx, bad, internal, number, scope};

const PAGE: usize = 50;
/// Held-for-edit messages upstream counts for its banner.
const EDITING_LIMIT: usize = 100;

/// The mailbox side and the state filter, as upstream reads the query.
fn filters(q: &HashMap<String, String>) -> Result<(MessageBox, Option<MessageState>), Response> {
    let mailbox = match q.get("box").map(String::as_str) {
        None | Some("inbox") => MessageBox::Inbox,
        Some("outbox") => MessageBox::Outbox,
        _ => return Err(bad("box must be inbox or outbox")),
    };
    let state = match q.get("state").map(String::as_str) {
        None if mailbox == MessageBox::Inbox => Some(MessageState::Pending),
        None | Some("") => None,
        Some(raw) => Some(raw.parse::<MessageState>().map_err(|_| bad("unknown message state"))?),
    };
    Ok((mailbox, state))
}

pub(crate) async fn handle(State(ctx): State<Arc<PanelCtx>>, axum::extract::Query(q): Params) -> Response {
    let reader = &ctx.page.reader;
    let (projects, counts, directory) =
        match tokio::try_join!(reader.list_projects_with_stats(None), reader.pending_inbox_counts(None), reader.registered_agents(None)) {
            Ok(read) => read,
            Err(e) => return internal(e),
        };
    let pending: HashMap<(String, String), u64> =
        counts.into_iter().map(|c| ((c.workspace_name, c.project_name), c.pending)).collect();
    let (workspace, project, default_id) = match (q.get("workspace"), q.get("project")) {
        (Some(w), Some(p)) => (w.clone(), p.clone(), None),
        (None, None) => projects
            .iter()
            .find(|p| pending.contains_key(&(p.workspace_name.clone(), p.project_name.clone())))
            .or_else(|| projects.first())
            .map(|p| (p.workspace_name.clone(), p.project_name.clone(), p.project_id.parse::<ProjectId>().ok()))
            .unwrap_or_default(),
        _ => return error(StatusCode::BAD_REQUEST, "Select both workspace and project."),
    };
    let (mailbox, state) = match filters(&q) {
        Ok(f) => f,
        Err(r) => return r,
    };
    let offset = match number(&q, "offset") {
        Ok(n) => n.unwrap_or(0),
        Err(r) => return r,
    };
    let resolved = match default_id {
        _ if workspace.is_empty() && project.is_empty() => Ok(None),
        Some(id) => lookup_project_id_guarded(reader, &workspace, id, None, ProjectAccess::Read)
            .await
            .map_err(|e| error(StatusCode::NOT_FOUND, &e.to_string()))
            .map(Some),
        None => scope(&ctx, &workspace, &project).await.map(Some),
    };
    let scope = match resolved {
        Ok(s) => s,
        Err(r) => return r,
    };
    let (mut messages, editing) = match scope {
        Some(s) => {
            let page = reader.message_history_filtered(s.workspace_id, s.project_id, mailbox, state, PAGE + 1, offset);
            let held = reader.message_history_filtered(
                s.workspace_id, s.project_id, MessageBox::Inbox, Some(MessageState::Editing), EDITING_LIMIT, 0,
            );
            match tokio::try_join!(page, held) {
                Ok((m, h)) => (m, if mailbox == MessageBox::Inbox { h.len() } else { 0 }),
                Err(e) => return internal(e),
            }
        }
        None => (Vec::new(), 0),
    };
    let more = messages.len() > PAGE;
    messages.truncate(PAGE);
    let names: HashMap<(String, String), String> = projects
        .iter()
        .map(|p| ((p.workspace_id.clone(), p.project_id.clone()), format!("{} / {}", p.workspace_name, p.project_name)))
        .collect();
    let name = |ws: String, proj: String| names.get(&(ws, proj)).cloned();
    let rows: Vec<Value> = messages
        .into_iter()
        .map(|m| {
            json!({
                "id": m.id.to_string(),
                "subject": m.subject.filter(|s| !s.is_empty()),
                "body": m.body,
                "from": name(m.origin.from_workspace_id.to_string(), m.origin.from_project_id.to_string()),
                "to": name(m.to_workspace_id.to_string(), m.to_project_id.to_string()),
                "from_agent": m.origin.from_agent.as_str(),
                "to_agent": m.to_agent.map(|a| a.as_str()),
                "state": m.state.as_str(),
                "nature": m.nature.as_str(),
                "created_at": m.created_at.to_string(),
                "claimed_at": m.claimed_at.map(|t| t.to_string()),
            })
        })
        .collect();
    // Totals over the project list, as upstream sums its scope options.
    let waiting: Vec<u64> =
        projects.iter().map(|p| pending.get(&(p.workspace_name.clone(), p.project_name.clone())).copied().unwrap_or(0)).collect();
    let scopes: Vec<Value> = projects
        .iter()
        .zip(&waiting)
        .map(|(p, n)| json!({"workspace": p.workspace_name, "project": p.project_name, "pending": n}))
        .collect();
    let recipients: Vec<Value> =
        directory.into_iter().map(|r| json!({"workspace": r.workspace, "project": r.project, "agent": r.agent.as_str()})).collect();
    Json(json!({
        "workspace": workspace,
        "project": project,
        "box": if mailbox == MessageBox::Inbox { "inbox" } else { "outbox" },
        "state": state.map(|s| s.as_str()),
        "pending_total": waiting.iter().fold(0_u64, |n, c| n.saturating_add(*c)),
        "pending_projects": waiting.iter().filter(|n| **n > 0).count(),
        "scopes": scopes,
        "editing_count": editing,
        "recipients": recipients,
        "more": more,
        "messages": rows,
    }))
    .into_response()
}
