//! No brief without core pages (plan 35 E, the owner on 2026-11-19, reading
//! docs/research/ai-memory-upstream.md point 2): upstream's
//! `render_session_brief` (ai-memory-hooks router.rs at fa0ec25) sends the
//! brief when it has core pages (pinned, _rules/, _slots/) **or** recent
//! ones, and with no core it is only the titles of the last pages changed,
//! under the footer "compiled from this project's pinned / _rules/ / _slots/
//! wiki pages", which then is not true. In the bkdg-center case those titles
//! were session pages named by their first prompt ("s", "pode fazer.") and
//! the four pages about another system. So, when the brief is asked
//! (`briefing` truthy, after the marker's pairs: marker_query.rs) and the
//! project has no core page, the ask goes on with `briefing=0`: the
//! handoff, the snapshot and the profile still come, as upstream sends them.
//! A divergence from upstream with this reason; nothing in its crates changes.
//!
//! The project is found the way the hooks name it (mcp_scope.rs
//! `scope_of`: the marker's `project`, else the main repository root's
//! name), with the query's own `project` and `workspace` first. A project
//! the store does not know has no pages: no brief. A store error leaves the
//! ask as it was.

use std::collections::HashMap;

use ai_memory_core::SlotVisibility;
use ai_memory_store::ReaderPool;
use axum::extract::{Query, Request, State};
use axum::middleware::Next;
use axum::response::Response;
use tracing::debug;

use crate::mcp_scope;

/// The routes that render the brief: the SessionStart's and a subagent's.
fn asks_brief(path: &str, query: &HashMap<String, String>) -> bool {
    matches!(path, "/handoff" | "/brief")
        && query.get("briefing").is_some_and(|v| matches!(v.trim().to_ascii_lowercase().as_str(), "1" | "true" | "yes" | "on"))
}

/// The (workspace, project) names the ask is about.
fn names(query: &HashMap<String, String>) -> Option<(String, String)> {
    let given = |k: &str| query.get(k).filter(|v| !v.is_empty()).cloned();
    if let (Some(ws), Some(project)) = (given("workspace"), given("project")) {
        return Some((ws, project));
    }
    let (ws, project) = mcp_scope::scope_of(query.get("cwd")?, given("workspace").as_deref())?;
    Some((ws, given("project").unwrap_or(project)))
}

/// Whether the project has a core page; `None` when the store could not say.
async fn has_core(reader: &ReaderPool, workspace: &str, project: &str) -> Option<bool> {
    let scopes = reader.list_all_scopes().await.ok()?;
    let Some(scope) = scopes.into_iter().find(|s| s.workspace_name == workspace && s.project_name == project) else {
        return Some(false);
    };
    let (core, _) = reader
        .session_brief_pages_with_slot_visibility(scope.workspace_id, scope.project_id, 1, 1, SlotVisibility::All)
        .await
        .ok()?;
    Some(!core.is_empty())
}

/// The query with `briefing=0` in place of what it had.
fn without_brief(path: &str, query: &str) -> Option<axum::http::Uri> {
    let mut pairs: Vec<(String, String)> = serde_urlencoded::from_str(query).ok()?;
    pairs.retain(|(k, _)| k != "briefing");
    pairs.push(("briefing".into(), "0".into()));
    format!("{path}?{}", serde_urlencoded::to_string(&pairs).ok()?).parse().ok()
}

/// Middleware on the inner router, inside the marker's (hook_body.rs).
pub(crate) async fn gate(State(reader): State<ReaderPool>, mut req: Request, next: Next) -> Response {
    let path = req.uri().path().to_owned();
    let query = Query::<HashMap<String, String>>::try_from_uri(req.uri()).ok().map(|Query(q)| q);
    if let Some(query) = query.filter(|q| asks_brief(&path, q))
        && let Some((workspace, project)) = names(&query)
        && has_core(&reader, &workspace, &project).await == Some(false)
        && let Some(uri) = req.uri().query().and_then(|q| without_brief(&path, q))
    {
        debug!(%project, "no core page: the brief is not sent (plan 35 E)");
        *req.uri_mut() = uri;
    }
    next.run(req).await
}

#[cfg(test)]
mod tests {
    use super::*;

    fn q(pairs: &[(&str, &str)]) -> HashMap<String, String> {
        pairs.iter().map(|(k, v)| (k.to_string(), v.to_string())).collect()
    }

    #[test]
    fn only_an_asked_brief_is_looked_at() {
        assert!(asks_brief("/handoff", &q(&[("briefing", "true")])));
        assert!(asks_brief("/brief", &q(&[("briefing", "1")])));
        assert!(!asks_brief("/handoff", &q(&[("briefing", "0")])));
        assert!(!asks_brief("/handoff", &q(&[])));
        assert!(!asks_brief("/hook", &q(&[("briefing", "1")])));
    }

    #[test]
    fn the_query_names_win_and_the_brief_turns_off_in_place() {
        assert_eq!(names(&q(&[("workspace", "w"), ("project", "p"), ("cwd", "/nowhere")])), Some(("w".into(), "p".into())));
        let uri = without_brief("/handoff", "cwd=%2Fr&briefing=true&session_id=s").unwrap();
        assert_eq!(uri.to_string(), "/handoff?cwd=%2Fr&session_id=s&briefing=0");
    }
}
