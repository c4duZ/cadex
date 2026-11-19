//! The fallback scope of a `cadex mcp` call: the project of the folder it
//! started in, sent in upstream's own headers (`x-memory-actor-fallback-*`,
//! ai-memory-mcp's launch_scope.rs at fa0ec25), which the engine uses only
//! when the session's id did not resolve a project (before the session's
//! first hook, after a `/resume`). Upstream's bridge works the project out
//! itself (the marker, else the git remote); `cadex mcp` sends the folder
//! (`X-Cadex-Cwd`) and the account's workspace (`X-Cadex-Workspace`) and the
//! engine names the project the way its hooks do: the marker's `project`,
//! else the main repository root's name (`project_strategy=repo-root`).
//! Plan 22 phase D, 2026-11-16.

use std::path::Path;

use ai_memory_mcp::launch_scope::{
    FALLBACK_PROJECT_HEADER, FALLBACK_WORKSPACE_HEADER, decode_header_value, encode_header_value,
};
use axum::extract::Request;
use axum::http::{HeaderMap, HeaderValue};
use axum::middleware::Next;
use axum::response::Response;

use crate::marker;

const CWD_HEADER: &str = "x-cadex-cwd";
const WORKSPACE_HEADER: &str = "x-cadex-workspace";

/// The `(workspace, project)` of a folder; `None` outside a repository
/// without a marker naming the project.
pub(crate) fn scope_of(cwd: &str, account_workspace: Option<&str>) -> Option<(String, String)> {
    let home = marker::home_dir();
    let text = crate::marker_query::settings_marker(cwd, home.as_deref()).and_then(|m| std::fs::read_to_string(m).ok());
    let from_marker = |key: &str| text.as_deref().and_then(|t| marker::parse_key_in(t, key));
    let project = from_marker("project").or_else(|| {
        let root = ai_memory_consolidate::discover_main_repo_root(Path::new(cwd)).ok()?;
        root.file_name().and_then(|s| s.to_str()).filter(|s| !s.is_empty()).map(str::to_owned)
    })?;
    let workspace = account_workspace
        .map(str::to_owned)
        .or_else(|| from_marker("workspace"))
        .unwrap_or_else(|| ai_memory_core::DEFAULT_WORKSPACE_NAME.to_owned());
    Some((workspace, project))
}

fn fill(headers: &mut HeaderMap) {
    let read = |name: &str| headers.get(name).and_then(|v| v.to_str().ok()).and_then(decode_header_value);
    let cwd = read(CWD_HEADER);
    let workspace = read(WORKSPACE_HEADER);
    headers.remove(CWD_HEADER);
    headers.remove(WORKSPACE_HEADER);
    if headers.contains_key(FALLBACK_PROJECT_HEADER) {
        return;
    }
    let Some((ws, project)) = cwd.and_then(|cwd| scope_of(&cwd, workspace.as_deref())) else { return };
    if let (Ok(ws), Ok(project)) =
        (HeaderValue::from_str(&encode_header_value(&ws)), HeaderValue::from_str(&encode_header_value(&project)))
    {
        headers.insert(FALLBACK_WORKSPACE_HEADER, ws);
        headers.insert(FALLBACK_PROJECT_HEADER, project);
    }
}

/// Middleware on the inner router.
pub(crate) async fn scope(mut req: Request, next: Next) -> Response {
    if req.uri().path().starts_with("/mcp") {
        fill(req.headers_mut());
    }
    next.run(req).await
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_repository_or_its_marker_names_the_project() {
        let tmp = tempfile::tempdir().unwrap();
        let repo = tmp.path().join("acme");
        std::fs::create_dir_all(repo.join("src")).unwrap();
        let init = std::process::Command::new("git").args(["init", "-q"]).current_dir(&repo).status().unwrap();
        assert!(init.success());
        let sub = repo.join("src");
        let (ws, project) = scope_of(sub.to_str().unwrap(), None).unwrap();
        assert_eq!((ws.as_str(), project.as_str()), ("default", "acme"));
        std::fs::write(repo.join(".ai-memory.toml"), "project = \"named\"\nworkspace = \"team\"\n").unwrap();
        assert_eq!(scope_of(sub.to_str().unwrap(), None).unwrap(), ("team".into(), "named".into()));
        assert_eq!(scope_of(sub.to_str().unwrap(), Some("acct")).unwrap().0, "acct");
        let mut headers = HeaderMap::new();
        headers.insert(CWD_HEADER, HeaderValue::from_str(&encode_header_value(sub.to_str().unwrap())).unwrap());
        fill(&mut headers);
        assert!(!headers.contains_key(CWD_HEADER));
        assert_eq!(headers[FALLBACK_PROJECT_HEADER], "named");
    }
}
