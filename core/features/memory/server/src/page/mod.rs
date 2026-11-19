//! The engine side of Cadex's Memory page (plan 22 phase H, 2026-11-16),
//! behind the session token like every route (auth.rs). The app reaches
//! these routes only through `cadex memory-agent` (agent_client.zig), which
//! prints what they answer.
//!
//! - `GET /cadex/memory/overview?cwd&workspace`: the folder's project, its
//!   wiki folder, the model, the counts and the imported history
//!   (overview.rs).
//! - `GET /cadex/memory/briefing?cwd&workspace`: what the next SessionStart
//!   in that folder would receive, without claiming the handoff and without
//!   a live session's recovery snapshot (briefing.rs).
//! - `POST /cadex/memory/write-page?cwd&workspace&path` (Markdown body),
//!   `POST /cadex/memory/delete-page?cwd&workspace&path` (pages.rs) and
//!   `POST /cadex/memory/reindex?cwd&workspace` (reindex.rs).
//! - `GET /cadex/memory/proposals?cwd&workspace`,
//!   `POST /cadex/memory/approve?id`, `POST /cadex/memory/reject?id`
//!   (proposals.rs).
//!
//! Every route that names a project also refreshes `<data-dir>/projects.json`
//! (crate::projects_file), the list the page shows while the engine is down.

// The helpers' error is the response the handler sends as is; boxing it
// would only move the size around (clippy's result_large_err).
#![allow(clippy::result_large_err)]

mod briefing;
mod handoff_text;
mod overview;
mod pages;
mod proposals;
mod reindex;

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::{Arc, OnceLock};

use ai_memory_core::{ProjectId, WorkspaceId};
use ai_memory_store::{ReaderPool, WriterHandle};
use ai_memory_wiki::Wiki;
use axum::Json;
use axum::Router;
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use axum::routing::{get, post};
use serde_json::json;

use crate::restart::ModelEvents;
use crate::sessions::Sessions;

/// What the page's routes read and write.
pub(crate) struct Ctx {
    pub(crate) reader: ReaderPool,
    pub(crate) writer: WriterHandle,
    pub(crate) wiki: Wiki,
    pub(crate) data_dir: PathBuf,
    /// `None` with `--no-embeddings`.
    pub(crate) model: Option<Arc<ModelEvents>>,
    /// The live sessions: the briefing's preview leaves their recovery
    /// snapshot out (briefing.rs, plan 35 H).
    pub(crate) sessions: Arc<Sessions>,
    /// The inner router (the marker's query pairs, the MCP tools), set once
    /// it is built: these routes are part of it, so it cannot be passed in.
    inner: OnceLock<Router>,
}

impl Ctx {
    pub(crate) fn new(
        stores: (ReaderPool, WriterHandle, Wiki),
        data_dir: PathBuf,
        model: Option<Arc<ModelEvents>>,
        sessions: Arc<Sessions>,
    ) -> Self {
        let (reader, writer, wiki) = stores;
        Self { reader, writer, wiki, data_dir, model, sessions, inner: OnceLock::new() }
    }

    pub(crate) fn set_inner(&self, router: Router) {
        let _ = self.inner.set(router);
    }

    fn inner(&self) -> Result<Router, Response> {
        self.inner.get().cloned().ok_or_else(|| error(StatusCode::SERVICE_UNAVAILABLE, "the engine is starting"))
    }
}

pub(crate) fn router(ctx: Arc<Ctx>) -> Router {
    Router::new()
        .route("/cadex/memory/overview", get(overview::handle))
        .route("/cadex/memory/briefing", get(briefing::handle))
        .route("/cadex/memory/write-page", post(pages::write))
        .route("/cadex/memory/delete-page", post(pages::delete))
        .route("/cadex/memory/reindex", post(reindex::handle))
        .route("/cadex/memory/proposals", get(proposals::list))
        .route("/cadex/memory/approve", post(proposals::approve))
        .route("/cadex/memory/reject", post(proposals::reject))
        .with_state(ctx)
}

pub(crate) type Params = axum::extract::Query<HashMap<String, String>>;

/// The error body `cadex memory-agent` prints: `{"error": text}`.
pub(crate) fn error(status: StatusCode, text: &str) -> Response {
    (status, Json(json!({"error": text}))).into_response()
}

/// A folder's project: its names as the hooks name it, and its store ids
/// once the store has it.
pub(crate) struct Project {
    pub(crate) workspace: String,
    pub(crate) project: String,
    pub(crate) ids: Option<(WorkspaceId, ProjectId)>,
}

impl Project {
    /// The MCP tools' explicit scope.
    pub(crate) fn tool_args(&self) -> serde_json::Value {
        json!({"workspace": self.workspace, "project": self.project})
    }
}

/// The `cwd` of a request, required.
pub(crate) fn cwd_of(q: &HashMap<String, String>) -> Result<String, Response> {
    q.get("cwd").filter(|c| !c.is_empty()).cloned().ok_or_else(|| error(StatusCode::BAD_REQUEST, "cwd is required"))
}

/// The project of a folder, `None` outside a repository without a marker
/// naming one (`mcp_scope::scope_of`, the hooks' rule).
pub(crate) async fn scope_of(cwd: &str, workspace: Option<&str>) -> Option<(String, String)> {
    let (cwd, workspace) = (cwd.to_owned(), workspace.map(str::to_owned));
    tokio::task::spawn_blocking(move || crate::mcp_scope::scope_of(&cwd, workspace.as_deref())).await.ok().flatten()
}

/// The store ids of a project, without creating it.
pub(crate) async fn ids_of(reader: &ReaderPool, workspace: &str, project: &str) -> Option<(WorkspaceId, ProjectId)> {
    let ws = reader.find_workspace(workspace.to_owned()).await.ok().flatten()?;
    let proj = reader.find_project(ws, project.to_owned()).await.ok().flatten()?;
    Some((ws, proj))
}

/// The request's project; 404 when the folder names none.
pub(crate) async fn project_of(ctx: &Ctx, q: &HashMap<String, String>) -> Result<Project, Response> {
    let cwd = cwd_of(q)?;
    let workspace = q.get("workspace").map(String::as_str).filter(|w| !w.is_empty());
    let Some((workspace, project)) = scope_of(&cwd, workspace).await else {
        return Err(error(StatusCode::NOT_FOUND, "the folder is not in a project"));
    };
    let ids = ids_of(&ctx.reader, &workspace, &project).await;
    Ok(Project { workspace, project, ids })
}
