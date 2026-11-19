//! `/cadex/memory/panel/api/v1/...`: upstream's read-only JSON API, the
//! routes the native screens use, answered by Cadex (plan 40 B, 2026-11-19).
//!
//! Upstream's own `api_router` (ai-memory-web) also embeds its guides and
//! changelog for its `/docs` routes, about 3.7 MB of the release binary that
//! no flag drops; with the translations its health checks pull in, the
//! crate cost 4.3 MB (measured 2026-11-19). The owner chose to leave it out:
//! the native Documentação screen links to upstream's guides on GitHub. So
//! these handlers repeat upstream's (crates/ai-memory-web/src/routes/api.rs
//! at 411d90d): the same paths, query names, defaults and limits, the same
//! store and wiki reads and the same JSON, which tests/panel_api.rs holds
//! equal to upstream's real `api_router` over the same folder. The request
//! is the owner's: upstream's root with no `AuthorizedViewer` (no viewer
//! filter) and the anonymous actor (its `owner_filter_for(None)`).
//!
//! Left out from upstream's API: `/docs*`, `POST /search`, `recent`'s
//! `updated_since`/`cursor` paging, the page's ETag and `Cache-Control`
//! (a socket client keeps no cache). Search, unlike upstream's API here,
//! gets the engine's model, as `memory_query` does (search.rs).
//!
//! Files: pages.rs (workspaces, projects, pages, a page, recent, the two
//! graphs), overview.rs (workspace and project overview, briefing,
//! handoffs), sessions.rs (sessions, observations), history.rs with diff.rs
//! (upstream's private diff, copied), search.rs.

mod diff;
mod history;
mod overview;
mod pages;
mod search;
mod sessions;

use std::sync::Arc;

use ai_memory_core::{ActorContext, OwnerFilter, ProjectId, WorkspaceId};
use ai_memory_store::{ProjectAccess, ScopeResolutionError, lookup_existing_scope_guarded};
use axum::Router;
use axum::http::StatusCode;
use axum::response::Response;
use axum::routing::get;

use super::PanelCtx;
use crate::page::error;

pub(crate) fn router(ctx: Arc<PanelCtx>) -> Router {
    let p = "/workspaces/{workspace}/projects/{project}";
    Router::new()
        .route("/workspaces", get(pages::workspaces))
        .route("/projects", get(pages::projects))
        .route("/graph", get(pages::graph))
        .route("/search", get(search::handle))
        .route("/workspaces/{workspace}/overview", get(overview::workspace))
        .route(&format!("{p}/pages"), get(pages::pages))
        .route(&format!("{p}/pages/{{*path}}"), get(pages::page))
        .route(&format!("{p}/history/{{*path}}"), get(history::handle))
        .route(&format!("{p}/recent"), get(pages::recent))
        .route(&format!("{p}/briefing"), get(overview::briefing))
        .route(&format!("{p}/overview"), get(overview::project))
        .route(&format!("{p}/handoffs"), get(overview::handoffs))
        .route(&format!("{p}/sessions"), get(sessions::list))
        .route(&format!("{p}/sessions/{{session_id}}/observations"), get(sessions::observations))
        .route(&format!("{p}/graph"), get(pages::project_graph))
        .with_state(ctx)
}

/// Upstream's `owner_filter_for` with no actor on the request: the owner's
/// own rows and the shared ones.
pub(super) fn actor_filter() -> OwnerFilter {
    OwnerFilter::for_actor_context(&ActorContext::anonymous())
}

/// Upstream's 500: the error is logged, the body says nothing more.
pub(super) fn internal(e: impl std::fmt::Display) -> Response {
    tracing::error!(error = %e, "panel API internal error");
    error(StatusCode::INTERNAL_SERVER_ERROR, "internal server error")
}

pub(super) fn not_found(message: &str) -> Response {
    error(StatusCode::NOT_FOUND, message)
}

pub(super) fn bad_request(message: &str) -> Response {
    error(StatusCode::BAD_REQUEST, message)
}

/// Upstream's `scope_error_response`.
pub(super) fn scope_error(err: ScopeResolutionError) -> Response {
    if err.is_bad_request() {
        bad_request(&err.to_string())
    } else if err.is_forbidden() {
        error(StatusCode::FORBIDDEN, &err.to_string())
    } else if err.is_not_found() {
        not_found(&err.to_string())
    } else {
        internal(err)
    }
}

/// Upstream's `lookup_project`: an existing project, never created.
pub(super) async fn lookup(ctx: &PanelCtx, workspace: &str, project: &str) -> Result<(WorkspaceId, ProjectId), Response> {
    lookup_existing_scope_guarded(&ctx.page.reader, workspace, project, None, ProjectAccess::Read)
        .await
        .map(ai_memory_store::ResolvedScope::as_tuple)
        .map_err(|err| match err {
            ScopeResolutionError::ProjectNotFoundInWorkspace { project, .. } => {
                not_found(&format!("project '{project}' not found"))
            }
            other => scope_error(other),
        })
}

/// Upstream's `trimmed_opt`.
pub(super) fn trimmed(value: Option<&str>) -> Option<&str> {
    value.map(str::trim).filter(|s| !s.is_empty())
}

/// Upstream's default `limit` for briefing, overview, recent and search.
pub(super) fn default_limit() -> usize {
    10
}
