//! The memory turned off (plan 35 I; docs/spec/memory.md, "Desligar"), a
//! switch upstream does not have:
//!
//! - in a project: the app writes `<data-dir>/off-projects.json`,
//!   `{"roots":["<main repository root>",…]}`, from the flag in Cadex's own
//!   projects file (the choice is the Mac's, not the repository's
//!   `.ai-memory.toml`, which is committed and would turn it off for the
//!   team). A folder is off when it is under a root, or its main checkout
//!   (project_key.rs, read from the files: a worktree outside the root) is one.
//! - in a conversation: the app makes `<data-dir>/paused/<session id>`;
//!   `cadex memory-hook` sends nothing for it (hook_client.zig) and the gate
//!   below drops what still comes (an event queued before the pause).
//!
//! The file is read again only when its mtime or size changes: the gate runs
//! on every event. Nothing recorded before is deleted.

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::time::SystemTime;

use axum::extract::{Query, Request, State};
use axum::http::{Method, StatusCode};
use axum::middleware::Next;
use axum::response::{IntoResponse, Response};
use serde::Deserialize;

pub(crate) const FILE: &str = "off-projects.json";
pub(crate) const PAUSED: &str = "paused";

/// The off projects: their roots (canonical) and the names the store knows
/// them by (the marker's `project`, else the root's folder; mcp_scope.rs).
#[derive(Debug, Default)]
pub(crate) struct Off {
    pub(crate) roots: Vec<PathBuf>,
    pub(crate) names: Vec<String>,
}

#[derive(Deserialize)]
struct OffFile {
    #[serde(default)]
    roots: Vec<String>,
}

type Stamp = Option<(SystemTime, u64)>;

/// Per data folder (the tests run several engines' worth in one process).
static CACHE: Mutex<Option<HashMap<PathBuf, (Stamp, Arc<Off>)>>> = Mutex::new(None);

fn canonical(path: &Path) -> PathBuf {
    path.canonicalize().unwrap_or_else(|_| path.to_path_buf())
}

fn stamp(file: &Path) -> Stamp {
    let meta = std::fs::metadata(file).ok()?;
    Some((meta.modified().ok()?, meta.len()))
}

fn load(file: &Path) -> Off {
    let Some(parsed) = std::fs::read(file).ok().and_then(|b| serde_json::from_slice::<OffFile>(&b).ok()) else {
        return Off::default();
    };
    let roots: Vec<PathBuf> = parsed.roots.iter().filter(|r| r.starts_with('/')).map(|r| canonical(Path::new(r))).collect();
    // The name the hooks give it; a root git does not answer for keeps its folder's name.
    let names = roots.iter().filter_map(|r| {
        let named = r.to_str().and_then(|r| crate::mcp_scope::scope_of(r, None)).map(|(_, p)| p);
        named.or_else(|| r.file_name()?.to_str().map(str::to_owned))
    }).collect();
    Off { roots, names }
}

/// What `<data_dir>/off-projects.json` says now.
pub(crate) fn current(data_dir: &Path) -> Arc<Off> {
    let file = data_dir.join(FILE);
    let now = stamp(&file);
    let mut cache = CACHE.lock().unwrap_or_else(|e| e.into_inner());
    let map = cache.get_or_insert_with(HashMap::new);
    if let Some((seen, off)) = map.get(data_dir)
        && *seen == now
    {
        return off.clone();
    }
    let off = Arc::new(if now.is_some() { load(&file) } else { Off::default() });
    map.insert(data_dir.to_path_buf(), (now, off.clone()));
    off
}

impl Off {
    /// Whether `cwd` is in an off project.
    pub(crate) fn contains(&self, cwd: &Path) -> bool {
        if self.roots.is_empty() || cwd.as_os_str().is_empty() {
            return false;
        }
        let folder = canonical(cwd);
        if self.roots.iter().any(|r| folder.starts_with(r)) {
            return true;
        }
        let main = crate::project_key::main_root(cwd);
        self.roots.iter().any(|r| main.starts_with(r))
    }

    /// Whether a job's project is off: its root when known, else its name.
    pub(crate) fn covers(&self, root: Option<&Path>, project: &str) -> bool {
        match root {
            Some(root) => self.contains(root),
            None => self.names.iter().any(|n| n == project),
        }
    }
}

/// Whether `cwd` is in an off project of `data_dir`.
pub(crate) fn is_off(data_dir: &Path, cwd: &Path) -> bool {
    current(data_dir).contains(cwd)
}

/// A session id that can name a file: what the app writes (MemoryOff.swift).
fn plain(id: &str) -> bool {
    !id.is_empty() && id.len() <= 128 && id.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-' || b == b'_')
}

/// Whether the owner paused the memory in this conversation.
pub(crate) fn is_paused(data_dir: &Path, session: &str) -> bool {
    plain(session) && data_dir.join(PAUSED).join(session).exists()
}

/// Why an event or a read is refused, if it is.
fn refusal(data_dir: &Path, query: &HashMap<String, String>) -> Option<&'static str> {
    if query.get("session_id").is_some_and(|s| is_paused(data_dir, s)) {
        return Some("memory paused in this session");
    }
    if query.get("cwd").is_some_and(|c| is_off(data_dir, Path::new(c))) {
        return Some("memory off in this project");
    }
    None
}

/// The paths that record a session or hand it something: a refused event is
/// taken (202, nothing stored), a refused read answers empty (204).
fn gated(path: &str) -> Option<StatusCode> {
    match path {
        "/hook" => Some(StatusCode::ACCEPTED),
        "/handoff" | "/brief" | "/recap" | "/cadex/consolidate" => Some(StatusCode::NO_CONTENT),
        _ => None,
    }
}

/// Middleware outside every watcher (import, sessions, the agent, the
/// handoff): an event it drops sets nothing off. The engine's own replays
/// (the queue, the import) go through it too.
pub(crate) async fn gate(State(data_dir): State<Arc<PathBuf>>, req: Request, next: Next) -> Response {
    let path = req.uri().path().to_owned();
    if path == "/mcp" && req.method() == Method::POST {
        return crate::off_search::filter(&data_dir, req, next).await;
    }
    let Some(status) = gated(&path) else { return next.run(req).await };
    let Ok(Query(query)) = Query::<HashMap<String, String>>::try_from_uri(req.uri()) else { return next.run(req).await };
    match refusal(&data_dir, &query) {
        Some(why) => {
            tracing::debug!(path, why, "memory event dropped");
            (status, why).into_response()
        }
        None => next.run(req).await,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn repo(dir: &Path, name: &str) -> PathBuf {
        let root = dir.join(name);
        std::fs::create_dir_all(root.join(".git")).unwrap();
        std::fs::create_dir_all(root.join("src")).unwrap();
        canonical(&root)
    }

    #[test]
    fn a_folder_under_an_off_root_or_a_worktree_of_it_is_off() {
        let tmp = tempfile::tempdir().unwrap();
        let data = tmp.path().join("data");
        std::fs::create_dir_all(&data).unwrap();
        let acme = repo(tmp.path(), "acme");
        let other = repo(tmp.path(), "other");
        assert!(!is_off(&data, &acme), "no file: nothing off");
        std::fs::write(data.join(FILE), serde_json::json!({"roots": [acme]}).to_string()).unwrap();
        assert!(is_off(&data, &acme) && is_off(&data, &acme.join("src")));
        assert!(!is_off(&data, &other));
        assert_eq!(current(&data).names, ["acme"]);
        // A task's worktree outside the root: its `.git` file leads to the main checkout.
        let tree = tmp.path().join("acme-task");
        std::fs::create_dir_all(acme.join(".git/worktrees/t")).unwrap();
        std::fs::write(acme.join(".git/worktrees/t/commondir"), "../..\n").unwrap();
        std::fs::create_dir_all(&tree).unwrap();
        std::fs::write(tree.join(".git"), format!("gitdir: {}\n", acme.join(".git/worktrees/t").display())).unwrap();
        assert!(is_off(&data, &tree), "a worktree of an off project");
        // Turned back on: the file changes, the cache follows.
        std::fs::write(data.join(FILE), r#"{"roots":[]}"#).unwrap();
        assert!(!is_off(&data, &acme));
    }

    #[test]
    fn a_paused_session_is_one_with_its_marker_and_a_plain_id() {
        let tmp = tempfile::tempdir().unwrap();
        std::fs::create_dir_all(tmp.path().join(PAUSED)).unwrap();
        std::fs::write(tmp.path().join(PAUSED).join("s-1"), "").unwrap();
        assert!(is_paused(tmp.path(), "s-1"));
        assert!(!is_paused(tmp.path(), "s-2"));
        assert!(!is_paused(tmp.path(), "../paused/s-1"), "never a path");
    }

    #[test]
    fn events_and_reads_of_an_off_project_or_a_paused_session_are_refused() {
        let tmp = tempfile::tempdir().unwrap();
        let acme = repo(tmp.path(), "acme");
        std::fs::write(tmp.path().join(FILE), serde_json::json!({"roots": [acme]}).to_string()).unwrap();
        std::fs::create_dir_all(tmp.path().join(PAUSED)).unwrap();
        std::fs::write(tmp.path().join(PAUSED).join("p"), "").unwrap();
        let q = |pairs: &[(&str, &str)]| pairs.iter().map(|(k, v)| (k.to_string(), v.to_string())).collect::<HashMap<_, _>>();
        let off = acme.join("src");
        assert!(refusal(tmp.path(), &q(&[("cwd", off.to_str().unwrap()), ("session_id", "s")])).is_some());
        assert!(refusal(tmp.path(), &q(&[("cwd", "/elsewhere"), ("session_id", "p")])).is_some());
        assert!(refusal(tmp.path(), &q(&[("cwd", "/elsewhere"), ("session_id", "s")])).is_none());
        assert_eq!(gated("/hook"), Some(StatusCode::ACCEPTED));
        assert_eq!(gated("/handoff"), Some(StatusCode::NO_CONTENT));
        assert_eq!(gated("/cadex/agent/status"), None);
    }
}
