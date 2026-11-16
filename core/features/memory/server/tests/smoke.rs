//! The engine end to end, the way the Cadex hooks and MCP reach it: start the
//! binary on a socket in a temporary folder, write pages through MCP, open a
//! session through the hook routes and read the briefing back, then search.
//! Runs without the embedding model (no download in tests) and without the
//! wiki watcher, as `make check` does.

mod common;

use common::{ok, query, repo, start, tool};

#[test]
fn a_session_gets_the_projects_pages_and_search_finds_them() {
    let tmp = tempfile::tempdir().unwrap();
    let project = repo(tmp.path(), "acme");
    let engine = start(tmp.path(), &["--keep-alive"]);

    let page = |path: &str, body: &str| {
        let args = serde_json::json!({
            "workspace": "default", "project": "acme", "path": path, "body": body,
        });
        let out = tool(&engine.socket, "memory_write_page", args);
        assert!(!out.contains("\"isError\":true"), "{path}: {out}");
    };
    page("_rules/style.md", "# Style\n\nIdentifiers are in English; specs are in Portuguese.\n");
    page("decisions/socket.md", "# Engine socket\n\nThe engine listens on a pelican socket.\n");

    let cwd = project.to_str().unwrap();
    let session = "11111111-1111-4111-8111-111111111111";
    let start_event = serde_json::json!({
        "session_id": session, "cwd": cwd, "hook_event_name": "SessionStart",
        "source": "startup", "transcript_path": project.join("t.jsonl"),
    });
    let qs = query(&[("event", "session-start"), ("agent", "claude-code"), ("cwd", cwd),
        ("project_strategy", "repo-root"), ("ingest_key", "smoke1")]);
    ok(&engine.socket, "POST", &format!("/hook?{qs}"), Some(&start_event.to_string()))
        .expect("session-start accepted");

    let qs = query(&[("agent", "claude-code"), ("cwd", cwd), ("project_strategy", "repo-root"),
        ("briefing", "1"), ("session_id", session)]);
    let briefing = ok(&engine.socket, "GET", &format!("/handoff?{qs}"), None).unwrap_or_default();
    assert!(briefing.contains("Identifiers are in English"), "briefing without the rule: {briefing}");

    let found = tool(&engine.socket, "memory_query", serde_json::json!({
        "query": "pelican", "workspace": "default", "project": "acme", "limit": 5,
    }));
    assert!(found.contains("decisions/socket.md"), "search missed the page: {found}");
}
