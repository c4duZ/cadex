//! The memory agent's routes and its event middleware (plan 22 phase G,
//! 2026-11-16). Behind the session token like every route (auth.rs); the
//! app reaches them through `cadex memory-agent` (agent_client.zig).
//!
//! - `GET /cadex/agent/status`: on or off, paused, the day's spend and
//!   budget, the queue, the last 20 ledger lines, the proposals waiting for
//!   the owner, the Claude Code version.
//! - `POST /cadex/agent/pause?on=1|0`: in memory only; a new engine starts
//!   unpaused (memory.pause-agent pauses the running one).
//! - `POST /cadex/agent/run-dream?cwd=<dir>[&workspace=]`: queue a dream of
//!   the folder's project (needs the agent on).
//! - `POST /cadex/agent/bootstrap?cwd=<dir>[&workspace=][&dry_run=1]`: the
//!   estimate, or queue the run (even with the agent off: the owner clicked).
//!
//! The middleware turns a live SessionEnd and a PostCompact on `/hook` into
//! jobs, only with the agent on. The imported sessions' ends go to
//! `/hook/batch` and are not events, as for maintenance.

use std::collections::HashMap;
use std::sync::Arc;
use std::time::Instant;

use axum::Json;
use axum::extract::{Query, Request, State};
use axum::http::StatusCode;
use axum::middleware::Next;
use axum::response::{IntoResponse, Response};
use axum::routing::{get, post};
use serde_json::json;

use super::queue::{Job, Kind, Scope};
use super::{Agent, bootstrap, config, ledger, scope_for};

type Params = Query<HashMap<String, String>>;

pub(crate) fn router(agent: Arc<Agent>) -> axum::Router {
    axum::Router::new()
        .route("/cadex/agent/status", get(status))
        .route("/cadex/agent/pause", post(pause))
        .route("/cadex/agent/run-dream", post(run_dream))
        .route("/cadex/agent/bootstrap", post(run_bootstrap))
        .with_state(agent)
}

fn error(status: StatusCode, text: &str) -> Response {
    (status, Json(json!({"error": text}))).into_response()
}

async fn status(State(agent): State<Arc<Agent>>) -> Response {
    let ctx = &agent.ctx;
    let cfg = config::read(&ctx.data_dir);
    let pending: u64 = match ctx.reader.list_pending_auto_improve_scopes().await {
        Ok(scopes) => scopes.iter().map(|s| s.pending).sum(),
        Err(_) => 0,
    };
    Json(json!({
        "enabled": cfg.enabled,
        "paused": agent.queue.paused(),
        "spent_today_usd": ledger::spent_today(&ctx.data_dir),
        "daily_budget_usd": cfg.daily_budget_usd,
        "queue": agent.queue.rows(),
        "recent": ledger::recent(&ctx.data_dir, 20),
        "proposals_pending": pending,
        "claude_version": ctx.any_version(),
    }))
    .into_response()
}

async fn pause(State(agent): State<Arc<Agent>>, Query(q): Params) -> Response {
    let on = match q.get("on").map(String::as_str) {
        Some("1" | "true") => true,
        Some("0" | "false") => false,
        _ => return error(StatusCode::BAD_REQUEST, "on=1 or on=0"),
    };
    agent.queue.set_paused(on);
    Json(json!({"paused": on})).into_response()
}

/// The project of the request's `cwd`.
async fn scope_of_query(q: &HashMap<String, String>) -> Result<Scope, Response> {
    let Some(cwd) = q.get("cwd").cloned() else { return Err(error(StatusCode::BAD_REQUEST, "cwd is required")) };
    let workspace = q.get("workspace").cloned();
    let found = tokio::task::spawn_blocking(move || scope_for(&cwd, workspace.as_deref())).await.ok().flatten();
    found.ok_or_else(|| error(StatusCode::NOT_FOUND, "the folder is not in a project"))
}

fn queued(agent: &Agent, kind: Kind, scope: Scope) -> Response {
    let job = Job { kind, scope, session: None, manual: true, not_before: Instant::now() };
    let fresh = agent.queue.push(&agent.ctx, job);
    (StatusCode::ACCEPTED, Json(json!({"queued": true, "already_queued": !fresh}))).into_response()
}

async fn run_dream(State(agent): State<Arc<Agent>>, Query(q): Params) -> Response {
    if !config::read(&agent.ctx.data_dir).enabled {
        return error(StatusCode::CONFLICT, "the memory agent is off");
    }
    match scope_of_query(&q).await {
        Ok(scope) => queued(&agent, Kind::Dream, scope),
        Err(response) => response,
    }
}

async fn run_bootstrap(State(agent): State<Arc<Agent>>, Query(q): Params) -> Response {
    let scope = match scope_of_query(&q).await {
        Ok(scope) => scope,
        Err(response) => return response,
    };
    if !matches!(q.get("dry_run").map(String::as_str), Some("1" | "true")) {
        return queued(&agent, Kind::Bootstrap, scope);
    }
    match bootstrap::estimate(&agent.ctx, &scope).await {
        Ok(estimate) => Json(estimate).into_response(),
        Err(text) => error(StatusCode::CONFLICT, &text),
    }
}

/// The job a `/hook` event sets off, if any.
fn event_kind(req: &Request) -> Option<(Kind, HashMap<String, String>)> {
    if req.uri().path() != "/hook" {
        return None;
    }
    let Query(q) = Query::<HashMap<String, String>>::try_from_uri(req.uri()).ok()?;
    let kind = match q.get("event").map(String::as_str)? {
        "session-end" | "session_end" | "SessionEnd" | "sessionEnd" => Kind::SessionEnd,
        "post-compaction" | "post_compaction" | "PostCompaction" | "PostCompact" => Kind::Compact,
        _ => return None,
    };
    Some((kind, q))
}

/// Middleware on the inner router: a live SessionEnd or PostCompact the
/// router took becomes a job, when the agent is on.
pub(crate) async fn watch(State(agent): State<Arc<Agent>>, req: Request, next: Next) -> Response {
    let event = event_kind(&req);
    let response = next.run(req).await;
    if let Some((kind, q)) = event
        && response.status().is_success()
    {
        tokio::spawn(enqueue(agent, kind, q));
    }
    response
}

async fn enqueue(agent: Arc<Agent>, kind: Kind, q: HashMap<String, String>) {
    let ctx = &agent.ctx;
    if !config::read(&ctx.data_dir).enabled {
        return;
    }
    let (Some(cwd), Some(session)) = (q.get("cwd").cloned(), q.get("session_id").cloned()) else { return };
    let workspace = q.get("workspace").cloned();
    let Some(scope) = tokio::task::spawn_blocking(move || scope_for(&cwd, workspace.as_deref())).await.ok().flatten() else {
        tracing::debug!("memory agent: the session's folder is not in a project");
        return;
    };
    let job = Job { kind, scope, session: Some(session), manual: false, not_before: Instant::now() + ctx.delay };
    agent.queue.push(ctx, job);
}
