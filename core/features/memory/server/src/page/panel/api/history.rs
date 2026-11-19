//! A page's stored versions, newest first, and a unified diff between two of
//! them (by default the newest against the version it replaced), as
//! upstream's `/api/v1/.../history/{path}` answers (ai-memory-web's
//! routes/api.rs `history_handler` over routes/history.rs `load`, at
//! 411d90d): `?from=&to=` version ids, `limit` (50 by default, capped by the
//! store) and `offset`; the diff by diff.rs, the copy of upstream's.

use std::sync::Arc;

use ai_memory_core::{PageId, PagePath};
use ai_memory_store::{PageVersion, PageVersionBody};
use axum::Json;
use axum::extract::{Path, Query, State};
use axum::response::{IntoResponse, Response};
use serde::{Deserialize, Serialize};

use super::diff::{self, Diff, Hunk};
use super::{bad_request, internal, lookup, not_found};
use crate::page::panel::PanelCtx;

const DEFAULT_VERSION_LIMIT: usize = 50;

#[derive(Deserialize)]
pub(super) struct HistoryQuery {
    #[serde(default)]
    from: Option<String>,
    #[serde(default)]
    to: Option<String>,
    #[serde(default)]
    limit: Option<usize>,
    #[serde(default)]
    offset: usize,
}

#[derive(Serialize)]
struct ApiHistory {
    workspace: String,
    project: String,
    path: String,
    total: u64,
    offset: usize,
    limit: usize,
    versions: Vec<PageVersion>,
    diff: ApiHistoryDiff,
}

#[derive(Serialize)]
struct ApiHistoryDiff {
    from: Option<ApiHistorySide>,
    to: ApiHistorySide,
    status: &'static str,
    #[serde(skip_serializing_if = "Option::is_none")]
    reason: Option<&'static str>,
    truncated: bool,
    hunks: Vec<Hunk>,
}

#[derive(Serialize)]
struct ApiHistorySide {
    id: String,
    title: String,
    created_at: String,
}

fn side(body: &PageVersionBody) -> ApiHistorySide {
    ApiHistorySide { id: body.id.to_string(), title: body.title.clone(), created_at: body.created_at.clone() }
}

fn version_id(raw: Option<&str>, name: &str) -> Result<Option<PageId>, Response> {
    match raw.map(str::trim).filter(|s| !s.is_empty()) {
        None => Ok(None),
        Some(raw) => raw.parse::<PageId>().map(Some).map_err(|_| bad_request(&format!("invalid {name} version id"))),
    }
}

pub(super) async fn handle(
    State(ctx): State<Arc<PanelCtx>>,
    Path((workspace, project, raw_path)): Path<(String, String, String)>,
    Query(q): Query<HistoryQuery>,
) -> Response {
    // Upstream answers a missing project here as "project 'p' not found",
    // as `lookup` does.
    let (ws, proj) = match lookup(&ctx, &workspace, &project).await {
        Ok(ids) => ids,
        Err(r) => return r,
    };
    let path = match PagePath::new(&raw_path) {
        Ok(p) => p.as_str().to_owned(),
        Err(e) => return bad_request(&format!("invalid path: {e}")),
    };
    let (from_id, to_id) = match (version_id(q.from.as_deref(), "from"), version_id(q.to.as_deref(), "to")) {
        (Ok(f), Ok(t)) => (f, t),
        (Err(r), _) | (_, Err(r)) => return r,
    };
    let limit = q.limit.unwrap_or(DEFAULT_VERSION_LIMIT).clamp(1, ai_memory_store::PAGE_VERSIONS_MAX_LIMIT);
    let reader = &ctx.page.reader;
    let listing = match reader.page_versions(ws, proj, path.clone(), limit, q.offset).await {
        Ok(listing) => listing,
        Err(e) => return internal(e),
    };
    if listing.total == 0 {
        return not_found("page not found");
    }
    let body = |id: PageId| {
        let path = path.clone();
        async move {
            match reader.page_version_body(ws, proj, path, id).await {
                Ok(Some(body)) => Ok(body),
                Ok(None) => Err(None),
                Err(e) => Err(Some(internal(e))),
            }
        }
    };
    let missing = |e: Option<Response>| e.unwrap_or_else(|| not_found("version not found"));
    // Off the first page the newest version is not in the listing.
    let to_id = match to_id {
        Some(id) => id,
        None if q.offset == 0 => listing.versions[0].id,
        None => match reader.page_versions(ws, proj, path.clone(), 1, 0).await {
            Ok(newest) => match newest.versions.first() {
                Some(v) => v.id,
                None => return not_found("page not found"),
            },
            Err(e) => return internal(e),
        },
    };
    let to = match body(to_id).await {
        Ok(b) => b,
        Err(e) => return missing(e),
    };
    let from = match (from_id, to.supersedes) {
        (Some(id), _) => match body(id).await {
            Ok(b) => Some(b),
            Err(e) => return missing(e),
        },
        // A replaced version the store no longer has diffs against nothing.
        (None, Some(prev)) => match body(prev).await {
            Ok(b) => Some(b),
            Err(None) => None,
            Err(Some(r)) => return r,
        },
        (None, None) => None,
    };
    let (status, reason, truncated, hunks) = match diff::unified(from.as_ref().map_or("", |f| f.body.as_str()), &to.body) {
        Diff::Same => ("same", None, false, Vec::new()),
        Diff::TooLarge(why) => ("too_large", Some(why), false, Vec::new()),
        Diff::Changed { hunks, truncated } => ("changed", None, truncated, hunks),
    };
    Json(ApiHistory {
        workspace,
        project,
        path: raw_path,
        total: listing.total,
        offset: q.offset,
        limit,
        diff: ApiHistoryDiff { from: from.as_ref().map(side), to: side(&to), status, reason, truncated, hunks },
        versions: listing.versions,
    })
    .into_response()
}

