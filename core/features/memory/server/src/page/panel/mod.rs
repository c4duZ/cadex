//! The native Memory panel's data (plan 40 B, 2026-11-19), under
//! `/cadex/memory/panel`, behind the session token like every route
//! (auth.rs); the app reaches it through `cadex memory-agent panel --path P`
//! (agent_client.zig); its writes, `cadex memory-agent panel-post --path P`
//! with the JSON on stdin. Everything here only reads but the inbox's
//! messages (messages.rs, plan 40 F: send, and edit one still queued).
//!
//! - `/cadex/memory/panel/api/v1/...`: upstream's read-only JSON API
//!   (workspaces, projects, overview, pages, history, recent, briefing,
//!   handoffs, sessions, observations, search, graph), answered by Cadex
//!   with upstream's paths and JSON (api/; why not upstream's own router
//!   there), the request seen as the local owner: root, as upstream's
//!   single-user server treats its operator. No docs routes: the native
//!   Documentação screen links to upstream's guides on GitHub.
//! - `/cadex/memory/panel/extra/...`: what upstream shows only in its HTML
//!   (docs/research/memory-panel-screens.md, the final table), built from the
//!   same store reads its web handlers call, so the numbers match its pages:
//!   home.rs (overview extras and the inbox counter), inbox.rs with
//!   messages.rs, queues.rs
//!   (workstreams and the review list; approve and reject stay in
//!   ../proposals.rs), health.rs with health_checks.rs, project.rs (a project's summary, sessions
//!   and agents), tokens.rs (token usage of a project or a session),
//!   session.rs (retrievals and a page's evidence), search.rs with
//!   search_trace.rs (the search screen: filters, the recall trace, the
//!   recent pages with no term; plan 40 E).
//!
//! Ours sit under `extra/` rather than among upstream's paths so an upstream
//! update that adds a route can never collide with one of ours.

mod api;
mod health;
mod health_checks;
mod home;
mod inbox;
mod messages;
mod project;
mod queues;
mod search;
mod search_trace;
mod session;
mod tokens;

use std::path::PathBuf;
use std::sync::Arc;

use ai_memory_core::{IngestMetrics, OwnerFilter};
use ai_memory_llm::Embedder;
use ai_memory_store::{ProjectAccess, ResolvedScope, lookup_existing_scope_guarded};
use axum::Router;
use axum::http::StatusCode;
use axum::response::Response;
use axum::routing::{get, post};

use super::{Ctx, error};

pub(crate) const PREFIX: &str = "/cadex/memory/panel";

/// What the extra routes read besides the store: the process side of
/// upstream's `HealthSources` (health.rs).
pub(crate) struct Sources {
    /// The hook router's counters (engine.rs).
    pub(crate) ingest: Arc<IngestMetrics>,
    /// The queue `cadex memory-hook` leaves when the engine is down.
    pub(crate) spool_dir: PathBuf,
    /// The engine's embedder (the lazy model), for search and the health
    /// screen; `None` with `--no-embeddings`.
    pub(crate) model: Option<Arc<dyn Embedder>>,
}

impl Sources {
    /// The embedder's provider, stored-vector identity and dimension, read
    /// without loading the model.
    pub(crate) fn identity(&self) -> Option<(String, String, u32)> {
        self.model.as_ref().map(|e| (e.provider().to_owned(), e.model_identity(), e.dim()))
    }
}

pub(crate) struct PanelCtx {
    pub(crate) page: Arc<Ctx>,
    pub(crate) sources: Sources,
}

/// Root sees every owner's sessions and token usage, as upstream's
/// `session_owner_filter_for` gives root (#1867 upstream).
pub(crate) const OWNER: OwnerFilter = OwnerFilter::Any;

pub(crate) fn router(page: Arc<Ctx>, sources: Sources) -> Router {
    let ctx = Arc::new(PanelCtx { page, sources });
    let p = "/workspaces/{workspace}/projects/{project}";
    let extra = Router::new()
        .route("/home", get(home::home))
        .route("/inbox/notifications", get(home::notifications))
        .route("/inbox", get(inbox::handle))
        .route("/messages", post(messages::send))
        .route("/messages/{id}/edit", post(messages::begin_edit))
        .route("/messages/{id}/save", post(messages::save_edit))
        .route("/messages/{id}/release", post(messages::release_edit))
        .route("/workstreams", get(queues::workstreams))
        .route("/review", get(queues::review))
        .route("/health", get(health::handle))
        .route("/search", get(search::handle))
        .route(&format!("{p}/summary"), get(project::summary))
        .route(&format!("{p}/sessions"), get(project::sessions))
        .route(&format!("{p}/agents"), get(project::agents))
        .route(&format!("{p}/agents/{{agent}}"), get(project::agent))
        .route(&format!("{p}/tokens"), get(tokens::project))
        .route(&format!("{p}/sessions/{{session_id}}/tokens"), get(tokens::session))
        .route(&format!("{p}/sessions/{{session_id}}/retrievals"), get(session::retrievals))
        .route(&format!("{p}/evidence/{{*path}}"), get(session::evidence))
        .with_state(ctx.clone());
    Router::new().nest(&format!("{PREFIX}/api/v1"), api::router(ctx)).nest(&format!("{PREFIX}/extra"), extra)
}

/// A project named in the path, as upstream's `resolve_read_scope` finds it
/// (no viewer: the owner reads everything); 404 when the store has none.
pub(crate) async fn scope(ctx: &PanelCtx, workspace: &str, project: &str) -> Result<ResolvedScope, Response> {
    lookup_existing_scope_guarded(&ctx.page.reader, workspace, project, None, ProjectAccess::Read)
        .await
        .map_err(|e| error(StatusCode::NOT_FOUND, &e.to_string()))
}

/// A store failure, as the error body the page's routes answer.
pub(crate) fn internal(e: impl std::fmt::Display) -> Response {
    error(StatusCode::INTERNAL_SERVER_ERROR, &e.to_string())
}

/// A query value that does not parse.
pub(crate) fn bad(what: &str) -> Response {
    error(StatusCode::BAD_REQUEST, what)
}

/// A store time in microseconds as RFC 3339, the way upstream's pages print it.
pub(crate) fn micros(us: i64) -> Option<String> {
    jiff::Timestamp::from_microsecond(us).ok().map(|t| t.to_string())
}

/// A whole-number query value (`offset`, `page`, `limit`); blank is absent,
/// as upstream's `blank_as_none` reads it.
pub(crate) fn number(q: &std::collections::HashMap<String, String>, key: &str) -> Result<Option<usize>, Response> {
    match q.get(key).map(|v| v.trim()) {
        None | Some("") => Ok(None),
        Some(raw) => raw.parse().map(Some).map_err(|_| bad(&format!("{key} must be a whole number"))),
    }
}
