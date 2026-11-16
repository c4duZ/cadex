//! The file a tool call named, kept with its observation (plan 22, phase C,
//! the handoff that lists the files edited). Upstream stores an observation's
//! `file_path` (`[ingest] index_file_paths`, engine.rs) only when the hook
//! client sends it, in the reserved `_ai_memory_file` field, relative to the
//! checkout: its own client works it out (ai-memory-cli hook.rs,
//! `file_path_field`), while `cadex memory-hook` passes Claude Code's payload
//! as it is. So the engine does it (hook_body.rs calls `insert` on each live
//! PostToolUse), the same way: upstream's
//! `file_target` reads the one file a file tool names; the checkout is the
//! nearest folder above the event's cwd holding `.git` (so two worktrees
//! give the same key); the paths are compared lexically, never resolved.
//! A replayed transcript (`/hook/batch`) is not classified by upstream anyway.

use std::path::{Component, Path, PathBuf};

use ai_memory_core::AgentKind;
use ai_memory_hooks::{FILE_FIELD_KEY, FileSkip, FileTarget, file_field, file_target};

/// `path` with `.` and `..` worked out, without asking the disk.
fn lexical(path: &Path) -> PathBuf {
    let mut out = PathBuf::new();
    for part in path.components() {
        match part {
            Component::CurDir => {}
            Component::ParentDir => {
                out.pop();
            }
            other => out.push(other),
        }
    }
    out
}

fn checkout_root(start: &Path) -> Option<PathBuf> {
    start.ancestors().find(|dir| dir.join(".git").exists()).map(Path::to_path_buf)
}

/// The field for one call: the path relative to the checkout, or why none.
/// `None` when the call names no single file.
pub(crate) fn field_for(payload: &serde_json::Value, cwd: &str) -> Option<serde_json::Value> {
    let FileTarget::One(path) = file_target(AgentKind::ClaudeCode, payload)? else { return None };
    let cwd = lexical(Path::new(cwd));
    let Some(root) = checkout_root(&cwd) else { return Some(file_field(Err(FileSkip::NoCheckout))) };
    let absolute = lexical(&cwd.join(path));
    let Ok(relative) = absolute.strip_prefix(&root) else { return Some(file_field(Err(FileSkip::OutsideCheckout))) };
    let key = relative
        .components()
        .map(|c| c.as_os_str().to_str())
        .collect::<Option<Vec<_>>>()
        .map(|parts| parts.join("/"))
        .filter(|key| ai_memory_core::valid_file_path_key(key));
    Some(file_field(key.as_deref().ok_or(FileSkip::Refused)))
}

/// Add the field to a PostToolUse payload, unless it has one or names no
/// single file; the cwd is the payload's, else the query's.
pub(crate) fn insert(payload: &mut serde_json::Value, query_cwd: Option<&str>) {
    if payload.get(FILE_FIELD_KEY).is_some() {
        return;
    }
    let Some(cwd) = payload.get("cwd").and_then(|c| c.as_str()).or(query_cwd).map(str::to_string) else { return };
    if let (Some(field), Some(object)) = (field_for(payload, &cwd), payload.as_object_mut()) {
        object.insert(FILE_FIELD_KEY.into(), field);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn edit(path: &str) -> serde_json::Value {
        json!({"hook_event_name": "PostToolUse", "tool_name": "Edit",
               "tool_input": {"file_path": path, "old_string": "a", "new_string": "b"}})
    }

    #[test]
    fn the_file_is_kept_relative_to_the_checkout() {
        let tmp = tempfile::tempdir().unwrap();
        let repo = tmp.path().join("acme");
        std::fs::create_dir_all(repo.join(".git")).unwrap();
        std::fs::create_dir_all(repo.join("src")).unwrap();
        let cwd = repo.join("src");
        let cwd = cwd.to_str().unwrap();
        let path = |f: serde_json::Value| f.get("path").and_then(|p| p.as_str()).map(str::to_string);
        assert_eq!(path(field_for(&edit(&format!("{}/src/lib.rs", repo.display())), cwd).unwrap()).as_deref(), Some("src/lib.rs"));
        assert_eq!(path(field_for(&edit("../README.md"), cwd).unwrap()).as_deref(), Some("README.md"), "relative to the cwd");
        let outside = field_for(&edit("/etc/hosts"), cwd).unwrap();
        assert_eq!(outside.get("skipped").and_then(|s| s.as_str()), Some("outside_checkout"));
        let bash = json!({"tool_name": "Bash", "tool_input": {"command": "ls"}});
        assert!(field_for(&bash, cwd).is_none(), "not a file tool");
        let loose = tmp.path().join("loose");
        std::fs::create_dir_all(&loose).unwrap();
        let none = field_for(&edit("/x/y.rs"), loose.to_str().unwrap()).unwrap();
        assert_eq!(none.get("skipped").and_then(|s| s.as_str()), Some("no_checkout"));

        let mut out = json!({"cwd": cwd, "tool_name": "Write", "tool_input": {"file_path": "a.rs", "content": "x"}});
        insert(&mut out, None);
        assert_eq!(out[FILE_FIELD_KEY]["path"], "src/a.rs");
        out[FILE_FIELD_KEY] = json!({"path": "kept.rs"});
        insert(&mut out, None);
        assert_eq!(out[FILE_FIELD_KEY]["path"], "kept.rs", "a field already there is left alone");
    }
}
