//! A repository's `[capture] ignore_paths` (`.ai-memory.toml`) applied to
//! each tool event before it is stored, as upstream's hook client does
//! (`commands::hook::run` in the cli at fa0ec25: `capture_policy`, then
//! `inspect`, then drop, metadata only, or keep with the claim). The
//! matching is upstream's own `CapturePolicy`; only finding and reading the
//! marker is Cadex's (marker.rs), since `cadex memory-hook` does not
//! (plan 22, 2026-11-16).
//!
//! Not done here: upstream's check of another checkout's `ignore_paths`
//! (`cat ../other/secret.env`), and the allowlist mode (Cadex captures every
//! repository, upstream's default).

use std::path::Path;

use ai_memory_core::AgentKind;
use ai_memory_hooks::capture_policy::metadata_only_body;
use ai_memory_hooks::{CaptureDisposition, CapturePolicy, CaptureSource, PolicyState};
use serde_json::Value;

use crate::marker;

/// What happens to one event.
#[derive(Debug, PartialEq)]
pub(crate) enum Capture {
    Keep,
    Drop,
}

fn is_tool_event(event: &str) -> bool {
    matches!(event.to_ascii_lowercase().replace(['-', '_'], "").as_str(), "pretooluse" | "posttooluse" | "tooluse")
}

/// The policy of the nearest marker above `cwd` (a `[capture]`-only marker
/// counts here, unlike for the query pairs).
pub(crate) fn policy(cwd: &str) -> CapturePolicy {
    let home = marker::home_dir();
    let home = home.as_deref().and_then(Path::to_str);
    let Some(found) = marker::find_marker(cwd, home.map(Path::new)) else {
        return CapturePolicy::resolve(CaptureSource::Absent, cwd, home);
    };
    let dir = found.parent().and_then(Path::to_str).unwrap_or(cwd);
    match marker::read_capture_config(&found) {
        Ok(config) => CapturePolicy::resolve(CaptureSource::Parsed(&config), dir, home),
        Err(_) => CapturePolicy::resolve(CaptureSource::Invalid, dir, home),
    }
}

/// Applies the policy to `payload` in place; `Drop` means the event must not
/// be stored. Events other than tool calls pass untouched.
pub(crate) fn apply(payload: &mut Value, event: &str, agent: &str, query_cwd: Option<&str>) -> Capture {
    if !is_tool_event(event) {
        return Capture::Keep;
    }
    let cwd = payload.get("cwd").and_then(Value::as_str).map(str::to_owned).or(query_cwd.map(str::to_owned));
    let Some(cwd) = cwd else { return Capture::Keep };
    let inspection_cwd = marker::absolute_normalized(Path::new(&cwd)).to_string_lossy().into_owned();
    let decision = policy(&cwd).inspect(AgentKind::from_wire(agent), payload, &inspection_cwd);
    match decision.protocol().disposition() {
        CaptureDisposition::Drop => Capture::Drop,
        CaptureDisposition::MetadataOnly => {
            let session = payload.get("session_id").and_then(Value::as_str).map(str::to_owned);
            let occurred = payload.get("occurred_at").cloned();
            *payload = metadata_only_body(session.as_deref(), Some(&cwd), &decision);
            if let (Some(at), Some(object)) = (occurred, payload.as_object_mut()) {
                object.insert("occurred_at".into(), at);
            }
            Capture::Keep
        }
        CaptureDisposition::Keep => {
            if decision.protocol().policy_state() != PolicyState::Inactive
                && let (Ok(claim), Some(object)) = (serde_json::to_value(decision.protocol()), payload.as_object_mut())
            {
                object.insert("_ai_memory_capture".into(), claim);
            }
            Capture::Keep
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn write(cwd: &str, path: &str) -> Value {
        serde_json::json!({
            "session_id": "s-1", "cwd": cwd, "hook_event_name": "PostToolUse",
            "tool_name": "Write", "tool_input": {"file_path": path, "content": "SECRET=1"},
        })
    }

    #[test]
    fn an_ignored_path_is_dropped_and_others_carry_the_claim() {
        let repo = tempfile::tempdir().unwrap();
        std::fs::create_dir(repo.path().join(".git")).unwrap();
        std::fs::write(repo.path().join(".ai-memory.toml"), "[capture]\nignore_paths = [\"**/*.env\"]\n").unwrap();
        let cwd = repo.path().to_str().unwrap();
        let mut secret = write(cwd, &format!("{cwd}/config/prod.env"));
        assert_eq!(apply(&mut secret, "post-tool-use", "claude-code", None), Capture::Drop);
        let mut code = write(cwd, &format!("{cwd}/src/main.rs"));
        assert_eq!(apply(&mut code, "post-tool-use", "claude-code", None), Capture::Keep);
        assert!(code.get("_ai_memory_capture").is_some());
        assert_eq!(code["tool_input"]["content"], "SECRET=1", "kept events keep their content");
        let mut prompt = serde_json::json!({"cwd": cwd, "prompt": "x"});
        assert_eq!(apply(&mut prompt, "user-prompt-submit", "claude-code", None), Capture::Keep);
        assert!(prompt.get("_ai_memory_capture").is_none());
    }

    #[test]
    fn a_broken_capture_table_keeps_only_metadata() {
        let repo = tempfile::tempdir().unwrap();
        std::fs::create_dir(repo.path().join(".git")).unwrap();
        std::fs::write(repo.path().join(".ai-memory.toml"), "[capture]\nignore_paths = \"*.env\"\n").unwrap();
        let cwd = repo.path().to_str().unwrap();
        let mut event = write(cwd, &format!("{cwd}/src/main.rs"));
        event["occurred_at"] = "2026-11-16T10:00:00Z".into();
        assert_eq!(apply(&mut event, "post-tool-use", "claude-code", None), Capture::Keep);
        assert!(event.get("tool_input").is_none(), "content gone: {event}");
        assert!(event.get("tool_name").is_some() && event.get("_ai_memory_capture").is_some(), "{event}");
        assert_eq!(event["occurred_at"], "2026-11-16T10:00:00Z");
    }
}
