//! The recovery journal: what the engine missed while it was unreachable
//! (a degraded launch's session, or a run whose `/finish` could not reach
//! it), as locators and digests only, never transcript content, so the next
//! run with the engine up replays it (recover.rs).
//!
//! Copied from ai-memory v3.4.7 (fa0ec25; compared at v3.5.0, 411d90d, on 2026-11-19: unchanged): `JournalKind`, `JournalEntry`,
//! `JournalFile`, `load_journal`, `append_journal_entry`, `mutate_journal`,
//! `finish_journal`, `MAX_JOURNAL_ENTRIES`, `MAX_JOURNAL_BYTES`,
//! `MAX_ENTRY_FAILURES`, `MAX_FAILURE_REASON_BYTES` (crates/ai-memory-cli/src/
//! commands/recovery.rs) and `journal_finish_failed_run`, `system_time_ms`,
//! `absolute_session_dir` (commands/run.rs). Changed for Cadex (2026-11-16):
//! the file is `<data-dir>/run/recovery-journal.json` (0600, tmp + rename),
//! never upstream's data dir; `server_url` holds the memory.sock path; no
//! fs2 lock (not in this tree) nor upstream's symlink/ACL checks; the
//! messages name the next `cadex-memory run` instead of `ai-memory recover`.

use std::path::{Path, PathBuf};
use std::time::SystemTime;

use ai_memory_core::{ManagedRunId, NativeSessionIdentity, Sanitizer};
use ai_memory_workstream::{LaunchPlan, ManagedHarness, TranscriptCapability, clean_path};
use anyhow::{Context, Result, bail};
use serde::{Deserialize, Serialize};

const JOURNAL_FILE: &str = "recovery-journal.json";
const JOURNAL_VERSION: u32 = 1;
const MAX_JOURNAL_ENTRIES: usize = 256;
const MAX_JOURNAL_BYTES: u64 = 16 * 1024 * 1024;
const MAX_ENTRY_FAILURES: usize = 3;
const MAX_FAILURE_REASON_BYTES: usize = 2_048;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub(crate) enum JournalKind {
    DegradedRun,
    FinishFailed,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct JournalEntry {
    pub(crate) id: String,
    pub(crate) recorded_at: String,
    pub(crate) interval_started_ms: u64,
    pub(crate) interval_ended_ms: u64,
    pub(crate) kind: JournalKind,
    pub(crate) harness: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(crate) native_session_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(crate) session_dir: Option<String>,
    pub(crate) cwd: String,
    pub(crate) workspace: String,
    pub(crate) project: String,
    pub(crate) server_url: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(crate) run_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(crate) event_digests: Option<Vec<String>>,
    #[serde(default)]
    pub(crate) spool_only: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(crate) source_cursor: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(crate) final_cursor: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(crate) exit_code: Option<i32>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub(crate) failures: Vec<String>,
}

#[derive(Debug, Serialize, Deserialize)]
struct JournalFile {
    version: u32,
    entries: Vec<JournalEntry>,
}

fn journal_path(run_dir: &Path) -> PathBuf {
    run_dir.join(JOURNAL_FILE)
}

/// The journal; a missing file is empty, a corrupt one an error (never reset).
pub(crate) fn load_journal(run_dir: &Path) -> Result<Vec<JournalEntry>> {
    let path = journal_path(run_dir);
    let bytes = match std::fs::read(&path) {
        Ok(bytes) => bytes,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(Vec::new()),
        Err(error) => return Err(error).with_context(|| format!("reading {}", path.display())),
    };
    if bytes.len() as u64 > MAX_JOURNAL_BYTES {
        bail!("recovery journal {} exceeds the {} byte limit", path.display(), MAX_JOURNAL_BYTES);
    }
    let journal: JournalFile = serde_json::from_slice(&bytes)
        .with_context(|| format!("parsing {}; refusing to discard the recorded recovery work", path.display()))?;
    if journal.version != JOURNAL_VERSION {
        bail!("unsupported recovery journal version {} in {} (expected {JOURNAL_VERSION})", journal.version, path.display());
    }
    Ok(journal.entries)
}

fn mutate_journal(run_dir: &Path, mutate: impl FnOnce(&mut Vec<JournalEntry>) -> Result<()>) -> Result<()> {
    let mut entries = load_journal(run_dir)?;
    mutate(&mut entries)?;
    let mut rendered = serde_json::to_vec_pretty(&JournalFile { version: JOURNAL_VERSION, entries })?;
    rendered.push(b'\n');
    std::fs::create_dir_all(run_dir).with_context(|| format!("creating {}", run_dir.display()))?;
    let path = journal_path(run_dir);
    ai_memory_wiki::write_atomic(&path, &rendered).map(|_| ()).with_context(|| format!("writing {}", path.display()))?;
    use std::os::unix::fs::PermissionsExt as _;
    std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o600)).with_context(|| format!("securing {}", path.display()))
}

pub(crate) fn append_journal_entry(run_dir: &Path, entry: JournalEntry) -> Result<()> {
    mutate_journal(run_dir, |entries| {
        if entries.len() >= MAX_JOURNAL_ENTRIES {
            bail!("recovery journal is full ({MAX_JOURNAL_ENTRIES} entries); run `cadex-memory run` with the engine up before another degraded launch");
        }
        entries.push(entry);
        Ok(())
    })
}

/// Clear the recovered entries and note why the others failed; the count left.
pub(crate) fn finish_journal(run_dir: &Path, sanitizer: &Sanitizer, cleared: &[String], annotated: &[(String, String)]) -> Result<usize> {
    if cleared.is_empty() && annotated.is_empty() {
        return Ok(load_journal(run_dir).map_or(0, |entries| entries.len()));
    }
    let mut remaining = 0;
    mutate_journal(run_dir, |entries| {
        entries.retain(|entry| !cleared.contains(&entry.id));
        for (id, reason) in annotated {
            if let Some(entry) = entries.iter_mut().find(|entry| &entry.id == id) {
                let reason = ai_memory_core::truncate_utf8_bytes(&sanitizer.scrub(reason), MAX_FAILURE_REASON_BYTES);
                if !entry.failures.contains(&reason) {
                    entry.failures.push(reason);
                }
                let overflow = entry.failures.len().saturating_sub(MAX_ENTRY_FAILURES);
                entry.failures.drain(..overflow);
            }
        }
        remaining = entries.len();
        Ok(())
    })?;
    Ok(remaining)
}

pub(crate) fn system_time_ms(time: SystemTime) -> u64 {
    time.duration_since(std::time::UNIX_EPOCH).unwrap_or_default().as_millis().try_into().unwrap_or(u64::MAX)
}

pub(crate) fn absolute_session_dir(session_dir: Option<&Path>, cwd: &Path) -> Option<PathBuf> {
    session_dir.map(|path| if path.is_absolute() { clean_path(path) } else { clean_path(&cwd.join(path)) })
}

/// Where a journaled run happened.
pub(crate) struct JournalScope<'a> {
    pub(crate) run_dir: &'a Path,
    pub(crate) server: &'a Path,
    pub(crate) cwd: &'a Path,
    pub(crate) workspace: &'a str,
    pub(crate) project: &'a str,
}

/// An entry with the common fields filled.
pub(crate) fn new_entry(scope: &JournalScope<'_>, kind: JournalKind, harness: ManagedHarness, plan: &LaunchPlan,
    started_at: SystemTime, exit_code: i32) -> JournalEntry {
    JournalEntry {
        id: uuid::Uuid::new_v4().to_string(),
        recorded_at: jiff::Timestamp::now().to_string(),
        interval_started_ms: system_time_ms(started_at),
        interval_ended_ms: system_time_ms(SystemTime::now()),
        kind,
        harness: harness.as_str().to_string(),
        native_session_id: None,
        session_dir: absolute_session_dir(plan.session_dir.as_deref(), scope.cwd).map(|p| p.to_string_lossy().into_owned()),
        cwd: scope.cwd.to_string_lossy().into_owned(),
        workspace: scope.workspace.to_string(),
        project: scope.project.to_string(),
        server_url: scope.server.to_string_lossy().into_owned(),
        run_id: None,
        event_digests: None,
        spool_only: harness.transcript_capability() == TranscriptCapability::SpoolOnly,
        source_cursor: None,
        final_cursor: None,
        exit_code: Some(exit_code),
        failures: Vec::new(),
    }
}

/// The exact interval a finish could not deliver: the next run re-imports it.
pub(crate) struct FinishFailed<'a> {
    pub(crate) native_session_id: Option<&'a str>,
    pub(crate) run_id: ManagedRunId,
    pub(crate) event_digests: Option<&'a [String]>,
    pub(crate) source_cursor: Option<&'a str>,
    pub(crate) final_cursor: Option<&'a str>,
}

pub(crate) fn journal_finish_failed_run(scope: &JournalScope<'_>, harness: ManagedHarness, plan: &LaunchPlan,
    started_at: SystemTime, exit_code: i32, failed: FinishFailed<'_>, sanitizer: &Sanitizer) {
    let mut entry = new_entry(scope, JournalKind::FinishFailed, harness, plan, started_at, exit_code);
    entry.native_session_id = failed
        .native_session_id
        .and_then(|id| NativeSessionIdentity::parse(id, sanitizer).ok())
        .map(NativeSessionIdentity::into_string);
    entry.run_id = Some(failed.run_id.to_string());
    entry.event_digests = failed.event_digests.map(<[String]>::to_vec);
    entry.source_cursor = failed.source_cursor.map(str::to_owned);
    entry.final_cursor = failed.final_cursor.map(str::to_owned);
    match append_journal_entry(scope.run_dir, entry) {
        Ok(()) => eprintln!(
            "ai-memory: recorded for recovery — the next `cadex-memory run` with the memory engine up re-imports this transcript"
        ),
        Err(error) => eprintln!(
            "ai-memory: could not record this run for recovery ({error:#}); retain the native transcript and original run id for manual repair"
        ),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn entries_round_trip_clear_and_keep_bounded_failures() {
        let tmp = tempfile::tempdir().unwrap();
        let plan = ai_memory_workstream::build_launch_plan(ManagedHarness::Codex, None, Vec::new(), None).unwrap();
        let scope = JournalScope { run_dir: tmp.path(), server: Path::new("/m.sock"), cwd: Path::new("/r"), workspace: "w", project: "p" };
        let one = new_entry(&scope, JournalKind::DegradedRun, ManagedHarness::Codex, &plan, SystemTime::now(), 3);
        let two = new_entry(&scope, JournalKind::DegradedRun, ManagedHarness::Antigravity, &plan, SystemTime::now(), 0);
        assert!(two.spool_only);
        let (a, b) = (one.id.clone(), two.id.clone());
        append_journal_entry(tmp.path(), one).unwrap();
        append_journal_entry(tmp.path(), two).unwrap();
        let sanitizer = Sanitizer::builtin();
        let reasons: Vec<(String, String)> = (0..5).map(|n| (b.clone(), format!("reason {n}"))).collect();
        assert_eq!(finish_journal(tmp.path(), &sanitizer, &[a], &reasons).unwrap(), 1);
        let left = load_journal(tmp.path()).unwrap();
        assert_eq!(left[0].failures, ["reason 2", "reason 3", "reason 4"]);
        use std::os::unix::fs::PermissionsExt as _;
        assert_eq!(std::fs::metadata(journal_path(tmp.path())).unwrap().permissions().mode() & 0o777, 0o600);
    }
}
