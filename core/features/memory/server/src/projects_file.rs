//! `<data-dir>/projects.json`: the projects the engine has resolved, so the
//! Memory page can show the wiki tree while the engine is down (plan 22
//! phase H, 2026-11-16; the spec's "ligada, sem sessão de agente: a página
//! lê a wiki"):
//!
//! `{"projects":[{"workspace":W,"project":P,"root":"<repo root>"|null,
//! "wiki_dir":"<absolute folder of the project's pages>"}]}`
//!
//! Refreshed when a project is resolved: a live SessionStart and its
//! `/handoff` (the middleware below), and the page's routes (page/). Written
//! by rename, mode 0600 (the names of the owner's repositories).

use std::collections::HashMap;
use std::io::Write;
use std::os::unix::fs::OpenOptionsExt;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use axum::extract::{Query, Request, State};
use axum::middleware::Next;
use axum::response::Response;
use serde::{Deserialize, Serialize};

use crate::page::{Ctx, Project, ids_of, scope_of};

const FILE: &str = "projects.json";
/// How long a SessionStart's project may take to show up in the store: the
/// hook route answers 202 and stores the event in a task of its own.
const ROW_WAIT: Duration = Duration::from_secs(5);

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub(crate) struct Entry {
    pub(crate) workspace: String,
    pub(crate) project: String,
    pub(crate) root: Option<String>,
    pub(crate) wiki_dir: String,
}

#[derive(Default, Serialize, Deserialize)]
struct File {
    projects: Vec<Entry>,
}

/// One writer at a time in this process (the engine is the only one).
static LOCK: Mutex<()> = Mutex::new(());

/// Put `entry` in the file, replacing the same project's; a known root is
/// kept when the new entry has none.
pub(crate) fn upsert(data_dir: &Path, mut entry: Entry) -> std::io::Result<()> {
    let _guard = LOCK.lock().unwrap_or_else(|e| e.into_inner());
    let path = data_dir.join(FILE);
    let mut file: File = std::fs::read(&path).ok().and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default();
    let same = |e: &Entry| e.workspace == entry.workspace && e.project == entry.project;
    if let Some(old) = file.projects.iter().find(|e| same(e)) {
        if entry.root.is_none() {
            entry.root = old.root.clone();
        }
        if old == &entry {
            return Ok(());
        }
    }
    file.projects.retain(|e| !same(e));
    file.projects.push(entry);
    file.projects.sort_by(|a, b| (&a.workspace, &a.project).cmp(&(&b.workspace, &b.project)));
    let tmp = path.with_extension("json.tmp");
    let mut out = std::fs::OpenOptions::new().write(true).create(true).truncate(true).mode(0o600).open(&tmp)?;
    out.write_all(&serde_json::to_vec_pretty(&file)?)?;
    out.sync_all()?;
    std::fs::rename(&tmp, &path)
}

/// The main repository root of a folder, when it is in one.
pub(crate) async fn root_of(cwd: &str) -> Option<PathBuf> {
    let cwd = PathBuf::from(cwd);
    tokio::task::spawn_blocking(move || crate::project_paths::main_repo_root(&cwd)).await.ok().flatten()
}

/// Record a project whose store ids are known.
pub(crate) fn record_project(ctx: &Ctx, project: &Project, root: Option<&Path>) {
    let Some((ws, proj)) = project.ids else { return };
    let entry = Entry {
        workspace: project.workspace.clone(),
        project: project.project.clone(),
        root: root.map(|r| r.to_string_lossy().into_owned()),
        wiki_dir: ctx.wiki.project_root(ws, proj).to_string_lossy().into_owned(),
    };
    if let Err(error) = upsert(&ctx.data_dir, entry) {
        tracing::warn!(%error, "projects.json not written");
    }
}

/// Resolve a folder's project and record it, waiting a little for a project
/// the store is still creating. Whether it was recorded.
pub(crate) async fn record_folder(ctx: &Ctx, cwd: &str, workspace: Option<&str>, wait: Duration) -> bool {
    let Some((ws_name, project)) = scope_of(cwd, workspace).await else { return false };
    let deadline = tokio::time::Instant::now() + wait;
    let ids = loop {
        if let Some(ids) = ids_of(&ctx.reader, &ws_name, &project).await {
            break ids;
        }
        if tokio::time::Instant::now() >= deadline {
            return false;
        }
        tokio::time::sleep(Duration::from_millis(200)).await;
    };
    let root = root_of(cwd).await;
    record_project(ctx, &Project { workspace: ws_name, project, ids: Some(ids) }, root.as_deref());
    true
}

fn is_start(q: &HashMap<String, String>) -> bool {
    matches!(q.get("event").map(String::as_str), Some("session-start" | "session_start" | "SessionStart" | "sessionStart"))
}

/// The folder and workspace of a request that resolves a session's project:
/// a live SessionStart on `/hook`, or the `/handoff` that follows it (not
/// the inbox poll, which resolves nothing new).
fn resolving(req: &Request) -> Option<(String, Option<String>)> {
    let path = req.uri().path();
    if path != "/hook" && path != "/handoff" {
        return None;
    }
    let Query(q) = Query::<HashMap<String, String>>::try_from_uri(req.uri()).ok()?;
    if (path == "/hook" && !is_start(&q)) || (path == "/handoff" && q.get("inbox_only").is_some_and(|v| v == "1" || v == "true")) {
        return None;
    }
    let cwd = q.get("cwd").filter(|c| !c.is_empty())?.clone();
    Some((cwd, q.get("workspace").filter(|w| !w.is_empty()).cloned()))
}

/// Middleware on the inner router: after a SessionStart or its `/handoff`
/// succeeds, record its project (in a task: the hook must not wait).
pub(crate) async fn watch(State(ctx): State<Arc<Ctx>>, req: Request, next: Next) -> Response {
    let found = resolving(&req);
    let response = next.run(req).await;
    if let Some((cwd, workspace)) = found
        && response.status().is_success()
    {
        tokio::spawn(async move {
            record_folder(&ctx, &cwd, workspace.as_deref(), ROW_WAIT).await;
        });
    }
    response
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::fs::PermissionsExt;

    fn entry(project: &str, root: Option<&str>) -> Entry {
        Entry { workspace: "default".into(), project: project.into(), root: root.map(Into::into), wiki_dir: format!("/w/{project}") }
    }

    #[test]
    fn an_entry_replaces_its_project_and_keeps_a_known_root() {
        let tmp = tempfile::tempdir().unwrap();
        upsert(tmp.path(), entry("b", Some("/r/b"))).unwrap();
        upsert(tmp.path(), entry("a", None)).unwrap();
        upsert(tmp.path(), entry("b", None)).unwrap();
        let path = tmp.path().join(FILE);
        let file: File = serde_json::from_slice(&std::fs::read(&path).unwrap()).unwrap();
        assert_eq!(file.projects, vec![entry("a", None), entry("b", Some("/r/b"))]);
        assert_eq!(std::fs::metadata(&path).unwrap().permissions().mode() & 0o777, 0o600);
        assert!(!tmp.path().join("projects.json.tmp").exists());
    }
}
