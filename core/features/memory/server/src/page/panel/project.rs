//! A project's screens beyond `/api/v1` (plan 40 B), read as upstream's
//! project page (ai-memory-web's routes/project.rs) and agent page
//! (routes/agents.rs) read them, as root (every owner's sessions). Under
//! `extra/workspaces/{workspace}/projects/{project}/`:
//!
//! - `summary` → `{"tokens":{"input_tokens","output_tokens",…}|null,
//!   "agents":[{"agent","sessions","mixed_capture_sessions"}],
//!   "mailbox":{"total","messages":[{"subject","nature","sender","snippet",
//!   "body","created_at"}]},"page_agents":{path: agent}}`: the overview tab's
//!   token total (`total_session_usage`), its per-agent badges
//!   (`session_counts_by_agent`), its mailbox card (the 5 newest waiting,
//!   `list_inbox_with_senders`, and `pending_message_count`), and the agent
//!   badge of each page in the knowledge tab (`latest_page_agent_kinds`).
//! - `sessions?state=open&sort=events&limit&offset` → `{"sessions":[…]}`:
//!   the sessions tab (`sessions_for_scope_view`, 20 by default as upstream
//!   shows, at most 100), each session as `/api/v1` gives it plus
//!   `display_name`.
//! - `agents` → `{"agents":[card]}`: the agents tab (`agent_usage`).
//! - `agents/{agent}?offset` → `{"agent":card,"sessions":[…],"more"}`: the
//!   agent page (`agent_sessions`, 50 a page).
//!
//! A card: `{"agent","sessions","open","measured_sessions","coverage","calls",
//! "input","output","cache_read","cache_write"}`, `coverage` the percent of
//! sessions that report usage, as upstream's `agent_card` computes it.

use std::collections::HashMap;
use std::sync::Arc;

use ai_memory_core::AgentKind;
use ai_memory_store::{AgentUsage, SessionSummary};
use axum::Json;
use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use serde_json::{Value, json};

use super::super::{Params, error};
use super::{OWNER, PanelCtx, bad, internal, number, scope};

const MAILBOX_LIMIT: usize = 5;
const SNIPPET_CHARS: usize = 160;
const SESSIONS_SHOWN: usize = 20;
const SESSIONS_MAX: usize = 100;
const AGENT_PAGE: usize = 50;

/// Upstream's mailbox snippet: whitespace folded, 160 characters and "…".
fn snippet(body: &str) -> String {
    let mut flat = body.split_whitespace().flat_map(|word| std::iter::once(' ').chain(word.chars())).skip(1);
    let cut: String = flat.by_ref().take(SNIPPET_CHARS).collect();
    if flat.next().is_some() { format!("{cut}…") } else { cut }
}

/// A session as `/api/v1/.../sessions` gives it, with the name upstream's
/// session rows show (left out of its JSON by `serde(skip)`).
pub(crate) fn session(s: SessionSummary) -> Value {
    let name = s.display_name.clone();
    let mut value = serde_json::to_value(&s).unwrap_or(Value::Null);
    if let Some(row) = value.as_object_mut() {
        row.insert("display_name".into(), json!(name));
    }
    value
}

fn card(row: &AgentUsage) -> Value {
    json!({
        "agent": row.agent,
        "sessions": row.sessions,
        "open": row.open,
        "measured_sessions": row.measured_sessions,
        "coverage": row.measured_sessions.saturating_mul(100).checked_div(row.sessions).unwrap_or(0),
        "calls": row.calls,
        "input": row.input,
        "output": row.output,
        "cache_read": row.cache_read,
        "cache_write": row.cache_write,
    })
}

pub(crate) async fn summary(State(ctx): State<Arc<PanelCtx>>, Path((workspace, project)): Path<(String, String)>) -> Response {
    let s = match scope(&ctx, &workspace, &project).await {
        Ok(s) => s,
        Err(r) => return r,
    };
    let reader = &ctx.page.reader;
    let read = tokio::try_join!(
        reader.total_session_usage(s.workspace_id, s.project_id, OWNER),
        reader.session_counts_by_agent(s.workspace_id, s.project_id, OWNER, None),
        reader.list_inbox_with_senders(s.workspace_id, s.project_id, None, MAILBOX_LIMIT),
        reader.pending_message_count(s.workspace_id, s.project_id),
        reader.latest_page_agent_kinds(&workspace, &project),
    );
    let (tokens, by_agent, entries, waiting, page_agents) = match read {
        Ok(read) => read,
        Err(e) => return internal(e),
    };
    let total = waiting.max(entries.len() as u64);
    let messages: Vec<Value> = entries
        .into_iter()
        .map(|e| {
            json!({
                "subject": e.message.subject.filter(|s| !s.trim().is_empty()),
                "nature": e.message.nature.as_str(),
                "sender": e.sender.map(|(w, p)| format!("{w}/{p}")),
                "snippet": snippet(&e.message.body),
                "body": e.message.body,
                "created_at": e.message.created_at.to_string(),
            })
        })
        .collect();
    let page_agents: HashMap<String, &'static str> = page_agents.into_iter().map(|(p, a)| (p, a.as_str())).collect();
    Json(json!({
        "tokens": tokens,
        "agents": by_agent,
        "mailbox": {"total": total, "messages": messages},
        "page_agents": page_agents,
    }))
    .into_response()
}

pub(crate) async fn sessions(
    State(ctx): State<Arc<PanelCtx>>,
    Path((workspace, project)): Path<(String, String)>,
    axum::extract::Query(q): Params,
) -> Response {
    let open_only = match q.get("state").map(String::as_str) {
        None | Some("" | "all") => false,
        Some("open") => true,
        _ => return bad("state must be all or open"),
    };
    let sort_events = match q.get("sort").map(String::as_str) {
        None | Some("" | "recent") => false,
        Some("events") => true,
        _ => return bad("sort must be recent or events"),
    };
    let (limit, offset) = match (number(&q, "limit"), number(&q, "offset")) {
        (Ok(l), Ok(o)) => (l.unwrap_or(SESSIONS_SHOWN).clamp(1, SESSIONS_MAX), o.unwrap_or(0)),
        (Err(r), _) | (_, Err(r)) => return r,
    };
    let s = match scope(&ctx, &workspace, &project).await {
        Ok(s) => s,
        Err(r) => return r,
    };
    match ctx.page.reader.sessions_for_scope_view(s.workspace_id, s.project_id, OWNER, open_only, sort_events, limit, offset).await {
        Ok(rows) => Json(json!({"sessions": rows.into_iter().map(session).collect::<Vec<_>>()})).into_response(),
        Err(e) => internal(e),
    }
}

pub(crate) async fn agents(State(ctx): State<Arc<PanelCtx>>, Path((workspace, project)): Path<(String, String)>) -> Response {
    let s = match scope(&ctx, &workspace, &project).await {
        Ok(s) => s,
        Err(r) => return r,
    };
    match ctx.page.reader.agent_usage(s.workspace_id, s.project_id, OWNER).await {
        Ok(rows) => Json(json!({"agents": rows.iter().map(card).collect::<Vec<_>>()})).into_response(),
        Err(e) => internal(e),
    }
}

pub(crate) async fn agent(
    State(ctx): State<Arc<PanelCtx>>,
    Path((workspace, project, raw)): Path<(String, String, String)>,
    axum::extract::Query(q): Params,
) -> Response {
    // Upstream answers 404 to a name that is not a wire name exactly.
    let kind = AgentKind::from_wire(&raw);
    if kind.as_str() != raw {
        return error(StatusCode::NOT_FOUND, "no such agent");
    }
    let offset = match number(&q, "offset") {
        Ok(o) => o.unwrap_or(0),
        Err(r) => return r,
    };
    let s = match scope(&ctx, &workspace, &project).await {
        Ok(s) => s,
        Err(r) => return r,
    };
    let reader = &ctx.page.reader;
    let rows = match reader.agent_usage(s.workspace_id, s.project_id, OWNER).await {
        Ok(rows) => rows,
        Err(e) => return internal(e),
    };
    let Some(row) = rows.iter().find(|r| r.agent == raw) else {
        return error(StatusCode::NOT_FOUND, "no sessions of this agent in the project");
    };
    let mut sessions = match reader.agent_sessions(s.workspace_id, s.project_id, kind, OWNER, offset).await {
        Ok(rows) => rows,
        Err(e) => return internal(e),
    };
    let more = sessions.len() > AGENT_PAGE;
    sessions.truncate(AGENT_PAGE);
    Json(json!({"agent": card(row), "sessions": sessions.into_iter().map(session).collect::<Vec<_>>(), "more": more}))
        .into_response()
}
