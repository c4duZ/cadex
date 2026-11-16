//! The end of a session (plan 22, phase C): Cadex's handoff lists what the
//! session did (its prompts, the 10 files of 10 edits, the tools), and the
//! engine dying by a panic loses no hook event: what arrives meanwhile waits
//! in the queue and the next engine takes it.

mod common;

use std::path::Path;
use std::time::{Duration, Instant};

use common::{TOKEN, ok, query, repo, request, start, start_with_env, tool};

fn hook(socket: &Path, event: &str, cwd: &str, session: &str, key: &str, body: serde_json::Value) {
    let qs = query(&[("event", event), ("agent", "claude-code"), ("cwd", cwd), ("session_id", session),
        ("project_strategy", "repo-root"), ("ingest_key", key)]);
    ok(socket, "POST", &format!("/hook?{qs}"), Some(&body.to_string())).unwrap_or_else(|| panic!("{event} refused"));
}

fn wait_for(what: &str, mut ok: impl FnMut() -> bool) {
    let deadline = Instant::now() + Duration::from_secs(15);
    while Instant::now() < deadline {
        if ok() {
            return;
        }
        std::thread::sleep(Duration::from_millis(100));
    }
    panic!("timed out waiting for {what}");
}

fn observations(socket: &Path, session: &str) -> String {
    tool(socket, "memory_read_session_observations", serde_json::json!({
        "session_id": session, "workspace": "default", "project": "acme", "limit": 100,
    }))
}

#[test]
fn the_handoff_of_a_session_with_ten_edits_lists_the_ten_files() {
    let tmp = tempfile::tempdir().unwrap();
    let project = repo(tmp.path(), "acme");
    let cwd = project.to_str().unwrap();
    let engine = start(tmp.path(), &["--keep-alive"]);
    let s = &engine.socket;
    let session = "44444444-4444-4444-8444-444444444444";
    let base = |name: &str| serde_json::json!({"session_id": session, "cwd": cwd, "hook_event_name": name});

    hook(s, "session-start", cwd, session, "h0", serde_json::json!({"session_id": session, "cwd": cwd, "source": "startup"}));
    let mut prompt = base("UserPromptSubmit");
    prompt["prompt"] = "split the parser into ten modules".into();
    hook(s, "user-prompt-submit", cwd, session, "h1", prompt);
    for i in 0..10 {
        let mut edit = base("PostToolUse");
        edit["tool_name"] = "Edit".into();
        edit["tool_input"] = serde_json::json!({"file_path": format!("{cwd}/src/part{i}.rs"), "old_string": "a", "new_string": "b"});
        edit["tool_response"] = serde_json::json!({"filePath": format!("{cwd}/src/part{i}.rs"), "success": true});
        hook(s, "post-tool-use", cwd, session, &format!("e{i}"), edit);
    }
    let mut last = base("UserPromptSubmit");
    last["prompt"] = "now update the docs".into();
    hook(s, "user-prompt-submit", cwd, session, "h2", last);
    // The route answers before it stores; the session's end must find
    // every event in the store, as a real session's (seconds apart) does.
    wait_for("the events stored", || {
        let seen = observations(s, session);
        seen.matches("tool file: Edit").count() >= 10 && seen.contains("now update the docs")
    });
    hook(s, "session-end", cwd, session, "h3", base("SessionEnd"));

    let list = || tool(s, "memory_handoff_list", serde_json::json!({"workspace": "default", "project": "acme"}));
    wait_for("the rewritten handoff", || list().contains("src/part9.rs"));

    let next = "55555555-5555-4555-8555-555555555555";
    hook(s, "session-start", cwd, next, "n0", serde_json::json!({"session_id": next, "cwd": cwd, "source": "startup"}));
    let qs = query(&[("agent", "claude-code"), ("cwd", cwd), ("project_strategy", "repo-root"), ("briefing", "1"), ("session_id", next)]);
    let briefing = ok(s, "GET", &format!("/handoff?{qs}"), None).unwrap_or_default();
    for i in 0..10 {
        assert!(briefing.contains(&format!("src/part{i}.rs")), "part{i} missing from the briefing: {briefing}");
    }
    assert!(briefing.contains("Session with 2 prompts, 10 tool calls and 10 files edited."), "{briefing}");
    assert!(briefing.contains("Tools used: Edit ×10."), "{briefing}");
    assert!(briefing.contains("1. split the parser into ten modules") && briefing.contains("Last prompt: now update the docs"), "{briefing}");
    assert!(!briefing.contains("Single-prompt") && !briefing.contains("Continue from"), "upstream's text left: {briefing}");
}

#[test]
fn a_forced_panic_loses_no_event() {
    let tmp = tempfile::tempdir().unwrap();
    let project = repo(tmp.path(), "acme");
    let cwd = project.to_str().unwrap();
    let session = "66666666-6666-4666-8666-666666666666";
    let prompt = |word: &str| serde_json::json!({"session_id": session, "cwd": cwd, "hook_event_name": "UserPromptSubmit", "prompt": format!("remember the {word}")});

    let mut first = start_with_env(tmp.path(), &["--keep-alive"], &[("CADEX_MEMORY_TEST_PANIC", "1")]);
    hook(&first.socket, "session-start", cwd, session, "p0", serde_json::json!({"session_id": session, "cwd": cwd, "source": "startup"}));
    hook(&first.socket, "user-prompt-submit", cwd, session, "p1", prompt("albatross"));
    wait_for("the first prompt stored", || observations(&first.socket, session).contains("albatross"));
    assert!(request(&first.socket, "POST", "/debug/panic", Some("{}"), Some(TOKEN)).is_none_or(|(s, _)| s >= 500));
    assert!(first.exits_within(Duration::from_secs(5)), "the engine survived its panic");
    let status = first.child.wait().unwrap();
    assert!(!status.success(), "a panic ends the process like release's abort: {status}");

    // Meanwhile the hooks find no engine and queue (hook_client.zig, spool.zig).
    let spool = tmp.path().join("data/spool");
    std::fs::create_dir_all(&spool).unwrap();
    for (n, word) in ["pelican", "cormorant"].iter().enumerate() {
        let path = format!("/hook?{}", query(&[("event", "user-prompt-submit"), ("agent", "claude-code"), ("cwd", cwd),
            ("session_id", session), ("project_strategy", "repo-root"), ("ingest_key", &format!("q{n}"))]));
        let file = serde_json::json!({"v": 1, "path": path, "body": prompt(word).to_string()});
        std::fs::write(spool.join(format!("000000000000{n}-q{n}.json")), file.to_string()).unwrap();
    }

    // The next SessionStart's hook starts a new engine, which drains the queue.
    let second = start(tmp.path(), &["--keep-alive"]);
    wait_for("the queue drained", || std::fs::read_dir(&spool).unwrap().flatten().all(|e| e.path().extension().is_none_or(|x| x != "json")));
    wait_for("every prompt stored", || {
        let seen = observations(&second.socket, session);
        ["albatross", "pelican", "cormorant"].iter().all(|w| seen.contains(w))
    });
    #[cfg(debug_assertions)]
    assert_eq!(request(&second.socket, "POST", "/debug/panic", Some("{}"), Some(TOKEN)).map(|r| r.0), Some(404), "the route exists only with the variable");
}
