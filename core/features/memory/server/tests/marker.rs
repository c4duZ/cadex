//! A repository's `.ai-memory.toml` read by the engine as upstream's hook
//! client reads it (marker.rs, marker_query.rs, capture.rs), and the MCP
//! call of a session going to that session's project (plan 22, real-session
//! test of 2026-11-16: an unscoped `memory_status` read another project).

mod common;

use common::{ok, query, repo, start, tool, tool_in_session};

const SESSION: &str = "22222222-2222-4222-8222-222222222222";

fn session_start(socket: &std::path::Path, cwd: &str) {
    let event = serde_json::json!({
        "session_id": SESSION, "cwd": cwd, "hook_event_name": "SessionStart", "source": "startup",
    });
    let qs = query(&[("event", "session-start"), ("agent", "claude-code"), ("cwd", cwd),
        ("project_strategy", "repo-root"), ("ingest_key", "m1"), ("session_id", SESSION)]);
    ok(socket, "POST", &format!("/hook?{qs}"), Some(&event.to_string())).expect("session-start accepted");
}

fn handoff(socket: &std::path::Path, cwd: &str) -> String {
    let qs = query(&[("agent", "claude-code"), ("cwd", cwd), ("project_strategy", "repo-root"),
        ("briefing", "1"), ("session_id", SESSION)]);
    ok(socket, "GET", &format!("/handoff?{qs}"), None).unwrap_or_default()
}

#[test]
fn the_marker_names_the_project_and_can_turn_the_brief_off() {
    let tmp = tempfile::tempdir().unwrap();
    let project = repo(tmp.path(), "checkout-dir");
    let cwd = project.to_str().unwrap();
    std::fs::write(project.join(".ai-memory.toml"), "project = \"named\"\n").unwrap();
    let engine = start(tmp.path(), &["--keep-alive"]);
    let page = serde_json::json!({
        "workspace": "default", "project": "named", "path": "_rules/style.md",
        "body": "# Style\n\nTabs, never spaces.\n",
    });
    assert!(!tool(&engine.socket, "memory_write_page", page).contains("\"isError\":true"));

    session_start(&engine.socket, cwd);
    assert!(handoff(&engine.socket, cwd).contains("Tabs, never spaces"), "the marker's project gives the brief");
    let status = tool_in_session(&engine.socket, SESSION, "memory_status", serde_json::json!({}));
    // Without the header the call takes the last project any hook touched
    // (`shared_slot`), which in the real test was another one.
    assert!(status.contains(r#"\"project\": \"named\""#) && status.contains(r#"\"resolved_by\": \"session\""#), "{status}");

    std::fs::write(project.join(".ai-memory.toml"), "project = \"named\"\n[briefing]\ninject_on_session_start = false\n").unwrap();
    session_start(&engine.socket, cwd);
    assert!(!handoff(&engine.socket, cwd).contains("Tabs, never spaces"), "the brief is off");
}

#[test]
fn an_ignored_file_never_reaches_the_store() {
    let tmp = tempfile::tempdir().unwrap();
    let project = repo(tmp.path(), "acme");
    let cwd = project.to_str().unwrap();
    std::fs::write(project.join(".ai-memory.toml"), "[capture]\nignore_paths = [\"*.env\"]\n").unwrap();
    let engine = start(tmp.path(), &["--keep-alive"]);
    session_start(&engine.socket, cwd);
    for (n, file) in ["prod.env", "main.rs"].iter().enumerate() {
        let event = serde_json::json!({
            "session_id": SESSION, "cwd": cwd, "hook_event_name": "PostToolUse", "tool_name": "Write",
            "tool_input": {"file_path": format!("{cwd}/{file}"), "content": format!("CONTENT-{file}")},
        });
        let key = format!("w{n}");
        let qs = query(&[("event", "post-tool-use"), ("agent", "claude-code"), ("cwd", cwd),
            ("project_strategy", "repo-root"), ("ingest_key", &key), ("session_id", SESSION)]);
        ok(&engine.socket, "POST", &format!("/hook?{qs}"), Some(&event.to_string())).expect("accepted");
    }
    let args = serde_json::json!({"session_id": SESSION, "workspace": "default", "project": "acme", "limit": 50});
    // Observations keep no file content here (no tool_response), so count:
    // the session start and the one kept edit.
    let total = || {
        let seen = tool(&engine.socket, "memory_read_session_observations", args.clone());
        (seen.matches("\\\"kind\\\": \\\"post-tool-use\\\"").count(), seen)
    };
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(10);
    while total().0 < 1 {
        assert!(std::time::Instant::now() < deadline, "the kept edit never arrived: {}", total().1);
        std::thread::sleep(std::time::Duration::from_millis(100));
    }
    std::thread::sleep(std::time::Duration::from_millis(500));
    let (edits, seen) = total();
    assert_eq!(edits, 1, "the ignored file was stored: {seen}");
}
