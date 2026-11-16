//! `GET /cadex/memory/overview?cwd=<dir>[&workspace=]`: the Memory page's
//! header for a folder (plan 22 phase H, 2026-11-16; the spec's "o estado do
//! processo e do modelo de vetores; o histórico importado"):
//!
//! `{"running":true,"workspace":W,"project":P,"wiki_dir":<abs>|null,
//! "model":"off"|"absent"|"downloading"|"ready"|"loaded","pages":N,
//! "sessions":N,"imported":{"state":"none"|"started"|"done","sessions":N,
//! "accounts":[{"dir":<account folder>,"sessions":N}]}}`
//!
//! `workspace` and `project` are null for a folder outside any project. The
//! counts are upstream's own project list (`list_projects_with_stats`, the
//! web UI's projects page): unexpired latest pages, recorded sessions. Only
//! reads; `cadex memory-agent overview` never starts the engine for it.

use std::sync::Arc;
use std::sync::atomic::Ordering;

use axum::Json;
use axum::extract::State;
use axum::response::{IntoResponse, Response};
use serde_json::{Value, json};

use super::{Ctx, Params, Project, cwd_of, ids_of, scope_of};
use crate::import_state::{Backfill, BackfillMarker};

/// The vector model's state, as the page names it.
fn model_state(ctx: &Ctx) -> &'static str {
    let Some(events) = &ctx.model else { return "off" };
    if events.loaded.load(Ordering::SeqCst) {
        "loaded"
    } else if events.fetching.load(Ordering::SeqCst) {
        "downloading"
    } else if ai_memory_llm::model_present(&ctx.data_dir.join("models")) {
        "ready"
    } else {
        "absent"
    }
}

/// The project's pages and sessions, from upstream's project list.
async fn counts(ctx: &Ctx, project: &Project) -> (u64, u64) {
    let Ok(rows) = ctx.reader.list_projects_with_stats_for_workspace(project.workspace.clone(), None).await else {
        return (0, 0);
    };
    let row = rows.into_iter().find(|r| r.project_name == project.project);
    row.map_or((0, 0), |r| (r.page_count, r.session_count))
}

/// The history import: its marker (import_state.rs) and the sessions each
/// account gave it, by the folder the import sent its events to.
fn imported(ctx: &Ctx, project: &Project, root: Option<&str>) -> Value {
    let state = match project.ids.map(|(ws, proj)| BackfillMarker::new(&ctx.data_dir, &ws, &proj).read()) {
        Some(Backfill::Done) => "done",
        Some(Backfill::Started) => "started",
        Some(Backfill::Never) | None => "none",
    };
    let by_account = root.map(|r| crate::import_state::imported(&ctx.data_dir, &project.workspace, r)).unwrap_or_default();
    let total: u64 = by_account.values().sum();
    let accounts: Vec<Value> = by_account.into_iter().map(|(dir, n)| json!({"dir": dir, "sessions": n})).collect();
    json!({"state": state, "sessions": total, "accounts": accounts})
}

/// The folder the import sent the project's events to: the project's
/// recorded repository path, else the folder's main repository root.
async fn import_root(ctx: &Ctx, project: &Project, cwd: &str) -> Option<String> {
    if let Some((ws, proj)) = project.ids
        && let Ok(Some(row)) = ctx.reader.scope_row_by_ids(ws, proj).await
        && let Some(path) = row.repo_path
    {
        return Some(path);
    }
    crate::projects_file::root_of(cwd).await.map(|r| r.to_string_lossy().into_owned())
}

pub(crate) async fn handle(State(ctx): State<Arc<Ctx>>, axum::extract::Query(q): Params) -> Response {
    let cwd = match cwd_of(&q) {
        Ok(cwd) => cwd,
        Err(response) => return response,
    };
    let model = model_state(&ctx);
    let workspace = q.get("workspace").map(String::as_str).filter(|w| !w.is_empty());
    let Some((ws_name, project_name)) = scope_of(&cwd, workspace).await else {
        return Json(json!({
            "running": true, "workspace": null, "project": null, "wiki_dir": null, "model": model,
            "pages": 0, "sessions": 0, "imported": {"state": "none", "sessions": 0, "accounts": []},
        }))
        .into_response();
    };
    let ids = ids_of(&ctx.reader, &ws_name, &project_name).await;
    let project = Project { workspace: ws_name, project: project_name, ids };
    let (pages, sessions) = counts(&ctx, &project).await;
    let root = import_root(&ctx, &project, &cwd).await;
    let repo_root = crate::projects_file::root_of(&cwd).await;
    crate::projects_file::record_project(&ctx, &project, repo_root.as_deref());
    let wiki_dir = project.ids.map(|(ws, proj)| ctx.wiki.project_root(ws, proj).to_string_lossy().into_owned());
    Json(json!({
        "running": true,
        "workspace": project.workspace,
        "project": project.project,
        "wiki_dir": wiki_dir,
        "model": model,
        "pages": pages,
        "sessions": sessions,
        "imported": imported(&ctx, &project, root.as_deref()),
    }))
    .into_response()
}
