//! The memory agent's audit (plan 35 phase D, 2026-11-19): what each
//! `claude -p` call was sent and answered, and the briefing each SessionStart
//! received, next to the ledger:
//!
//! ```text
//! <data-dir>/agent/ledger.jsonl                  one line per call, `call` names its file
//! <data-dir>/agent/calls/<UTC time>-<kind>-<id>.json   request and response of one call
//! <data-dir>/agent/briefings/<session id>.md     the briefing that session started with
//! ```
//!
//! Why: the owner's Center memory got pages about another system and the
//! ledger only said a call cost so much (plan 35, "Decidido com o dono");
//! without the prompt and the answer nobody could say what the agent read.
//!
//! Folders 0700, files 0600 (they hold the sessions' prompts), each written
//! to a hidden temporary file and renamed. Each folder keeps at most
//! `KEEP_DAYS` days and `KEEP_FILES` files, pruned on every write (one
//! directory listing of at most a few hundred entries: cheap next to a
//! `claude -p` run or a SessionStart).

use std::io::Write;
use std::os::unix::fs::{DirBuilderExt, OpenOptionsExt};
use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime};

/// A month covers "what did the agent do to my memory last week" and the
/// plan 35 H screen (a session's briefing); older calls only cost disk.
pub(crate) const KEEP_DAYS: u64 = 30;
/// At ~20 calls a busy day (a SessionEnd makes up to 3), 500 files are about
/// three weeks of calls; it bounds the folder when the days bound does not.
pub(crate) const KEEP_FILES: usize = 500;

pub(crate) const CALLS: &str = "calls";
pub(crate) const BRIEFINGS: &str = "briefings";

/// `<data-dir>/agent/<name>`, made 0700 if missing.
pub(crate) fn folder(data_dir: &Path, name: &str) -> std::io::Result<PathBuf> {
    let dir = super::ledger::dir(data_dir)?.join(name);
    if !dir.is_dir() {
        std::fs::DirBuilder::new().recursive(true).mode(0o700).create(&dir)?;
    }
    Ok(dir)
}

/// Write `bytes` to `dir/name`, 0600, through a temporary file and a rename,
/// then prune the folder.
pub(crate) fn write(dir: &Path, name: &str, bytes: &[u8]) -> std::io::Result<()> {
    let tmp = dir.join(format!(".{name}.{}.tmp", uuid::Uuid::new_v4().simple()));
    let written = std::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(&tmp)
        .and_then(|mut file| file.write_all(bytes))
        .and_then(|()| std::fs::rename(&tmp, dir.join(name)));
    if written.is_err() {
        let _ = std::fs::remove_file(&tmp);
    }
    prune(dir, SystemTime::now(), Duration::from_secs(KEEP_DAYS * 86_400), KEEP_FILES);
    written
}

/// Remove what is older than `max_age`, then the oldest past `max_files`
/// (by modification time, the name breaking ties).
pub(crate) fn prune(dir: &Path, now: SystemTime, max_age: Duration, max_files: usize) {
    let Ok(entries) = std::fs::read_dir(dir) else { return };
    let mut kept: Vec<(SystemTime, PathBuf)> = Vec::new();
    for entry in entries.flatten() {
        let Ok(meta) = entry.metadata() else { continue };
        if !meta.is_file() {
            continue;
        }
        let modified = meta.modified().unwrap_or(now);
        if now.duration_since(modified).is_ok_and(|age| age > max_age) {
            let _ = std::fs::remove_file(entry.path());
        } else {
            kept.push((modified, entry.path()));
        }
    }
    if kept.len() <= max_files {
        return;
    }
    kept.sort();
    for (_, path) in &kept[..kept.len() - max_files] {
        let _ = std::fs::remove_file(path);
    }
}

/// A file name for one call: sortable UTC time, the job kind, a short id.
pub(crate) fn call_name(kind: &str) -> String {
    let now = jiff::Timestamp::now();
    let kind: String = kind.chars().map(|c| if c.is_ascii_alphanumeric() || c == '-' { c } else { '_' }).take(40).collect();
    let id = uuid::Uuid::new_v4().simple().to_string();
    format!("{}{:03}Z-{kind}-{}.json", now.strftime("%Y%m%dT%H%M%S."), now.subsec_millisecond(), &id[..8])
}

/// Store one call's record; the path the ledger names (relative to
/// `<data-dir>/agent`), or `None` when it could not be written (logged:
/// the audit never stops a job).
pub(crate) fn keep_call(data_dir: &Path, kind: &str, record: &serde_json::Value) -> Option<String> {
    let name = call_name(kind);
    let result = folder(data_dir, CALLS).and_then(|dir| {
        let bytes = serde_json::to_vec_pretty(record).map_err(std::io::Error::other)?;
        write(&dir, &name, &bytes)
    });
    match result {
        Ok(()) => Some(format!("{CALLS}/{name}")),
        Err(error) => {
            tracing::warn!(%error, "memory agent call not audited");
            None
        }
    }
}

/// A session id usable as a file name: Claude Code's are UUIDs; anything
/// with a path separator or a dot is refused.
pub(crate) fn session_file_name(session: &str) -> Option<String> {
    let fits = !session.is_empty()
        && session.len() <= 128
        && session.chars().all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_');
    fits.then(|| format!("{session}.md"))
}

/// Store the briefing `session` started with (an empty one is not stored).
pub(crate) fn keep_briefing(data_dir: &Path, session: &str, text: &str) {
    let Some(name) = session_file_name(session) else { return };
    if text.trim().is_empty() {
        return;
    }
    if let Err(error) = folder(data_dir, BRIEFINGS).and_then(|dir| write(&dir, &name, text.as_bytes())) {
        tracing::warn!(%error, "session briefing not kept");
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::fs::PermissionsExt;

    fn touch(dir: &Path, name: &str, age_days: u64) {
        let path = dir.join(name);
        std::fs::write(&path, name).unwrap();
        let at = SystemTime::now() - Duration::from_secs(age_days * 86_400 + 60);
        std::fs::File::options().write(true).open(&path).unwrap().set_modified(at).unwrap();
    }

    #[test]
    fn pruning_drops_the_old_and_the_oldest_past_the_cap() {
        let tmp = tempfile::tempdir().unwrap();
        let dir = tmp.path();
        touch(dir, "ancient.json", 45);
        touch(dir, "old.json", 31);
        for (i, age) in [20, 10, 5, 1, 0].into_iter().enumerate() {
            touch(dir, &format!("f{i}.json"), age);
        }
        prune(dir, SystemTime::now(), Duration::from_secs(30 * 86_400), 3);
        let mut left: Vec<String> = std::fs::read_dir(dir).unwrap().flatten().map(|e| e.file_name().into_string().unwrap()).collect();
        left.sort();
        assert_eq!(left, ["f2.json", "f3.json", "f4.json"]);
    }

    #[test]
    fn a_call_file_is_private_and_named_by_time_and_kind() {
        let tmp = tempfile::tempdir().unwrap();
        let rel = keep_call(tmp.path(), "auto-improve", &serde_json::json!({"a": 1})).unwrap();
        let path = tmp.path().join("agent").join(&rel);
        let mode = |p: &Path| std::fs::metadata(p).unwrap().permissions().mode() & 0o777;
        assert_eq!((mode(&path), mode(path.parent().unwrap())), (0o600, 0o700));
        assert!(rel.starts_with("calls/2") && rel.contains("Z-auto-improve-") && rel.ends_with(".json"), "{rel}");
        let leftovers = std::fs::read_dir(path.parent().unwrap()).unwrap().count();
        assert_eq!(leftovers, 1, "no temporary file left");
    }

    #[test]
    fn a_session_id_with_a_path_is_refused() {
        assert_eq!(session_file_name("a1-b2_c3").as_deref(), Some("a1-b2_c3.md"));
        for bad in ["", "../x", "a/b", "a.b", &"x".repeat(129)] {
            assert_eq!(session_file_name(bad), None, "{bad}");
        }
        let tmp = tempfile::tempdir().unwrap();
        keep_briefing(tmp.path(), "s-1", "   \n");
        assert!(!tmp.path().join("agent").join(BRIEFINGS).join("s-1.md").exists(), "an empty briefing is not kept");
    }
}
