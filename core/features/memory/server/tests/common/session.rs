//! A Claude Code session told to the engine the way `cadex memory-hook`
//! tells it (the same events as tests/agent.rs and tests/session_end.rs),
//! for the Memory page's tests (plan 22 phase H, 2026-11-16).

use std::path::Path;
use std::time::{Duration, Instant};

use super::{ok, query, tool};

pub fn hook(socket: &Path, event: &str, cwd: &str, session: &str, key: &str, body: serde_json::Value) {
    let qs = query(&[("event", event), ("agent", "claude-code"), ("cwd", cwd), ("session_id", session),
        ("project_strategy", "repo-root"), ("ingest_key", key)]);
    ok(socket, "POST", &format!("/hook?{qs}"), Some(&body.to_string())).unwrap_or_else(|| panic!("{event} refused"));
}

pub fn wait_for(what: &str, limit: Duration, mut done: impl FnMut() -> bool) {
    let deadline = Instant::now() + limit;
    while Instant::now() < deadline {
        if done() {
            return;
        }
        std::thread::sleep(Duration::from_millis(100));
    }
    panic!("timed out waiting for {what}");
}

fn at(ago_secs: i64) -> String {
    jiff::Timestamp::now().checked_sub(jiff::SignedDuration::from_secs(ago_secs)).unwrap().to_string()
}

/// A session in project `acme` with a prompt and `tools` edits; events `ago`
/// seconds back, 10 s apart, when given. Not ended; its events stored.
pub fn work(socket: &Path, cwd: &str, id: &str, tools: usize, ago: Option<i64>) {
    let stamp = |body: &mut serde_json::Value, i: i64| {
        if let Some(ago) = ago {
            body["occurred_at"] = at(ago - i * 10).into();
        }
    };
    let mut start = serde_json::json!({"session_id": id, "cwd": cwd, "source": "startup"});
    stamp(&mut start, 0);
    hook(socket, "session-start", cwd, id, &format!("{id}-s"), start);
    let mut prompt = serde_json::json!({"session_id": id, "cwd": cwd, "hook_event_name": "UserPromptSubmit",
        "prompt": "fix the WAL lock in the cache"});
    stamp(&mut prompt, 1);
    hook(socket, "user-prompt-submit", cwd, id, &format!("{id}-p"), prompt);
    for i in 0..tools {
        let mut edit = serde_json::json!({"session_id": id, "cwd": cwd, "hook_event_name": "PostToolUse", "tool_name": "Edit",
            "tool_input": {"file_path": format!("{cwd}/src/cache{i}.rs")},
            "tool_response": {"filePath": format!("{cwd}/src/cache{i}.rs"), "success": true}});
        stamp(&mut edit, 2 + i as i64);
        hook(socket, "post-tool-use", cwd, id, &format!("{id}-t{i}"), edit);
    }
    let stored = || {
        let out = tool(socket, "memory_read_session_observations", serde_json::json!({
            "session_id": id, "workspace": "default", "project": "acme", "limit": 100}));
        out.matches("tool file: Edit").count() >= tools && out.contains("WAL lock")
    };
    wait_for("the events stored", Duration::from_secs(15), stored);
}

pub fn end(socket: &Path, cwd: &str, id: &str, ago: Option<i64>) {
    let mut body = serde_json::json!({"session_id": id, "cwd": cwd, "hook_event_name": "SessionEnd", "reason": "exit"});
    if let Some(ago) = ago {
        body["occurred_at"] = at(ago).into();
    }
    hook(socket, "session-end", cwd, id, &format!("{id}-e"), body);
}
