//! Workspaces, projects, a project's pages, one page, its recent pages and
//! the link graphs, as upstream's `/api/v1` answers them (ai-memory-web's
//! routes/api.rs at 411d90d: `workspaces_handler`, `projects_handler`,
//! `pages_handler`, `page_handler`, `recent_handler`, `graph_handler`,
//! `project_graph_handler`), the same store reads and JSON.

use std::sync::Arc;

use ai_memory_core::PagePath;
use ai_memory_store::{PageAuthor, RelatedPage};
use axum::Json;
use axum::extract::{Path, Query, State};
use axum::response::{IntoResponse, Response};
use serde::{Deserialize, Serialize};
use serde_json::json;

use super::{bad_request, default_limit, internal, lookup, not_found, trimmed};
use crate::page::panel::PanelCtx;

/// Upstream's `ApiPage`, field for field and in its order.
#[derive(Serialize)]
struct ApiPage {
    id: String,
    workspace: String,
    project: String,
    path: String,
    title: String,
    kind: String,
    tier: String,
    pinned: bool,
    created_at: String,
    updated_at: String,
    supersedes: Option<String>,
    frontmatter: serde_json::Value,
    body_markdown: String,
    links: Vec<RelatedPage>,
    backlinks: Vec<RelatedPage>,
    #[serde(skip_serializing_if = "Option::is_none")]
    author: Option<PageAuthor>,
}

#[derive(Deserialize)]
pub(super) struct ProjectListQuery {
    #[serde(default)]
    workspace: Option<String>,
}

#[derive(Deserialize)]
pub(super) struct GraphQuery {
    #[serde(default)]
    workspace: Option<String>,
    #[serde(default)]
    project: Option<String>,
}

#[derive(Deserialize)]
pub(super) struct RecentQuery {
    #[serde(default = "default_limit")]
    limit: usize,
    updated_since: Option<String>,
    cursor: Option<String>,
}

pub(super) async fn workspaces(State(ctx): State<Arc<PanelCtx>>) -> Response {
    match ctx.page.reader.list_workspaces_with_stats(None).await {
        Ok(rows) => Json(rows).into_response(),
        Err(e) => internal(e),
    }
}

pub(super) async fn projects(State(ctx): State<Arc<PanelCtx>>, Query(q): Query<ProjectListQuery>) -> Response {
    let reader = &ctx.page.reader;
    let rows = match trimmed(q.workspace.as_deref()) {
        Some(workspace) => reader.list_projects_with_stats_for_workspace(workspace.to_owned(), None).await,
        None => reader.list_projects_with_stats(None).await,
    };
    match rows {
        Ok(rows) => Json(rows).into_response(),
        Err(e) => internal(e),
    }
}

pub(super) async fn pages(State(ctx): State<Arc<PanelCtx>>, Path((workspace, project)): Path<(String, String)>) -> Response {
    if let Err(r) = lookup(&ctx, &workspace, &project).await {
        return r;
    }
    match ctx.page.reader.list_unexpired_pages(&workspace, &project).await {
        Ok(rows) => Json(rows).into_response(),
        Err(e) => internal(e),
    }
}

pub(super) async fn page(
    State(ctx): State<Arc<PanelCtx>>,
    Path((workspace, project, path)): Path<(String, String, String)>,
) -> Response {
    // Upstream's `authorize_read` with no viewer reads nothing first; the
    // meta read below answers for a missing project or page.
    let reader = &ctx.page.reader;
    let meta = match reader.page_meta(&workspace, &project, &path).await {
        Ok(Some(meta)) => meta,
        Ok(None) => return not_found("page not found"),
        Err(e) => return internal(e),
    };
    let page_path = match PagePath::new(&path) {
        Ok(p) => p,
        Err(e) => return bad_request(&format!("invalid path: {e}")),
    };
    let Ok(markdown) = ctx.page.wiki.read_page(meta.workspace_id, meta.project_id, &page_path) else {
        return not_found("page file not found");
    };
    let links = match reader.page_links(meta.workspace_id, meta.project_id, meta.path.clone(), None).await {
        Ok(links) => links,
        Err(e) => return internal(e),
    };
    Json(ApiPage {
        id: meta.id.to_string(),
        workspace: meta.workspace_name,
        project: meta.project_name,
        path: meta.path,
        title: meta.title,
        kind: meta.kind,
        tier: meta.tier,
        pinned: meta.pinned,
        created_at: meta.created_at,
        updated_at: meta.updated_at,
        supersedes: meta.supersedes,
        frontmatter: markdown.frontmatter,
        body_markdown: markdown.body,
        links: links.links,
        backlinks: links.backlinks,
        author: meta.author,
    })
    .into_response()
}

/// The newest pages. Upstream's incremental form (`updated_since`,
/// `cursor`) is for sync clients; the screens never page this way.
pub(super) async fn recent(
    State(ctx): State<Arc<PanelCtx>>,
    Path((workspace, project)): Path<(String, String)>,
    Query(q): Query<RecentQuery>,
) -> Response {
    let (ws, proj) = match lookup(&ctx, &workspace, &project).await {
        Ok(ids) => ids,
        Err(r) => return r,
    };
    if q.updated_since.is_some() || q.cursor.is_some() {
        return bad_request("updated_since and cursor are not served here");
    }
    let limit = q.limit.clamp(1, 100);
    match ctx.page.reader.recent_unexpired_page_summaries(ws, proj, &workspace, &project, limit).await {
        Ok(rows) => Json(rows).into_response(),
        Err(e) => internal(e),
    }
}

pub(super) async fn graph(State(ctx): State<Arc<PanelCtx>>, Query(q): Query<GraphQuery>) -> Response {
    let scope = match (trimmed(q.workspace.as_deref()), trimmed(q.project.as_deref())) {
        (None, None) => None,
        (Some(workspace), Some(project)) => match lookup(&ctx, workspace, project).await {
            Ok(ids) => Some(ids),
            Err(r) => return r,
        },
        _ => return bad_request("workspace and project must be provided together"),
    };
    match ctx.page.reader.cross_project_edges(scope, None).await {
        Ok(edges) => Json(json!({"edges": edges})).into_response(),
        Err(e) => internal(e),
    }
}

pub(super) async fn project_graph(State(ctx): State<Arc<PanelCtx>>, Path((workspace, project)): Path<(String, String)>) -> Response {
    let (ws, proj) = match lookup(&ctx, &workspace, &project).await {
        Ok(ids) => ids,
        Err(r) => return r,
    };
    match ctx.page.reader.project_link_graph(ws, proj).await {
        Ok(graph) => Json(json!({
            "workspace": workspace,
            "project": project,
            "truncated": graph.truncated,
            "nodes": graph.nodes,
            "edges": graph.edges,
        }))
        .into_response(),
        Err(e) => internal(e),
    }
}
