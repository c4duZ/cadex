//! Which native store each linked session was launched under, so a session
//! that only looks missing because this launch resolves another store
//! (another `CLAUDE_CONFIG_DIR`, `CODEX_HOME`, profile) is not replaced by a
//! fresh one.
//!
//! Copied from ai-memory v3.4.7 (fa0ec25): `effective_store`,
//! `canonical_prefix`, `remember_session_store`, `store_mismatch_error`
//! (crates/ai-memory-cli/src/commands/run.rs) and `record_session_store`,
//! `recorded_session_store`, `SessionStore`, `MAX_SESSION_STORES`
//! (commands/project_registry.rs). Changed for Cadex (2026-11-16): the record
//! is `<data-dir>/run/session-stores.json`, Cadex's own, never upstream's
//! client-projects.json; the "server" key is the socket path; written
//! atomically (tmp + rename) without upstream's fs2 lock (no `fs2` here; two
//! launchers finishing in the same instant may drop one record, which only
//! weakens the mismatch check for that session).

use std::path::{Path, PathBuf};

use ai_memory_workstream::{ManagedHarness, clean_path, native_store_root, store_override_vars};
use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};

use super::plan::display_session_id;
use super::terminal_text;

const MAX_SESSION_STORES: usize = 1_000;
const FILE: &str = "session-stores.json";

#[derive(Debug, Clone, Serialize, Deserialize)]
struct SessionStore {
    server: String,
    harness: String,
    native_session_id: String,
    store: PathBuf,
    recorded_at: String,
}

#[derive(Debug, Default, Serialize, Deserialize)]
struct Records {
    #[serde(default)]
    session_stores: Vec<SessionStore>,
}

/// Where the records live and which engine they belong to.
pub(crate) struct StoreRecords<'a> {
    pub(crate) run_dir: &'a Path,
    pub(crate) server: &'a Path,
}

impl StoreRecords<'_> {
    fn path(&self) -> PathBuf {
        self.run_dir.join(FILE)
    }

    fn load(&self) -> Result<Records> {
        match std::fs::read(self.path()) {
            Ok(bytes) => serde_json::from_slice(&bytes).with_context(|| format!("parsing {}", self.path().display())),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(Records::default()),
            Err(error) => Err(error).with_context(|| format!("reading {}", self.path().display())),
        }
    }

    fn server(&self) -> String {
        self.server.to_string_lossy().into_owned()
    }

    fn record(&self, harness: &str, native_session_id: &str, store: &Path) -> Result<()> {
        let mut records = self.load()?;
        let server = self.server();
        records.session_stores.retain(|r| !(r.server == server && r.harness == harness && r.native_session_id == native_session_id));
        records.session_stores.push(SessionStore {
            server,
            harness: harness.to_owned(),
            native_session_id: native_session_id.to_owned(),
            store: store.to_path_buf(),
            recorded_at: jiff::Timestamp::now().to_string(),
        });
        let excess = records.session_stores.len().saturating_sub(MAX_SESSION_STORES);
        records.session_stores.drain(..excess);
        std::fs::create_dir_all(self.run_dir).with_context(|| format!("creating {}", self.run_dir.display()))?;
        let body = serde_json::to_vec_pretty(&records)?;
        ai_memory_wiki::write_atomic(&self.path(), &body).map(|_| ()).with_context(|| format!("writing {}", self.path().display()))
    }

    /// The store a session was linked under, if this client recorded one.
    pub(crate) fn recorded_session_store(&self, harness: &str, native_session_id: &str) -> Result<Option<PathBuf>> {
        let server = self.server();
        Ok(self.load()?.session_stores.into_iter()
            .find(|r| r.server == server && r.harness == harness && r.native_session_id == native_session_id)
            .map(|r| r.store))
    }

    pub(crate) fn remember_session_store(&self, harness: ManagedHarness, native_session_id: &str, store: &Path) {
        if let Err(error) = self.record(harness.as_str(), native_session_id, store) {
            eprintln!("ai-memory: could not record the client-local session store ({error:#}); continuing the managed run");
        }
    }
}

/// The store a launch reads, absolute and normalized.
pub(crate) fn effective_store(harness: ManagedHarness, home: &Path, cwd: &Path, session_dir: Option<&Path>) -> PathBuf {
    let root = native_store_root(harness, home, session_dir);
    let absolute = if root.is_absolute() { root } else { cwd.join(root) };
    std::fs::canonicalize(&absolute).unwrap_or_else(|_| canonical_prefix(&clean_path(&absolute)))
}

/// Canonicalize the deepest existing ancestor and keep the missing tail.
fn canonical_prefix(path: &Path) -> PathBuf {
    let mut tail = Vec::new();
    let mut existing = path;
    loop {
        if let Ok(real) = std::fs::canonicalize(existing) {
            return tail.iter().rev().fold(real, |acc, part| acc.join(part));
        }
        match (existing.parent(), existing.file_name()) {
            (Some(parent), Some(name)) => {
                tail.push(name.to_os_string());
                existing = parent;
            }
            _ => return path.to_path_buf(),
        }
    }
}

/// Refuse to replace a linked session launched under another store.
pub(crate) fn store_mismatch_error(harness: ManagedHarness, native_session_id: &str, recorded: Option<PathBuf>, current: &Path)
    -> Option<anyhow::Error> {
    let recorded = recorded?;
    if recorded == current {
        return None;
    }
    let flags: &[&str] = match harness {
        ManagedHarness::Pi => &["--session-dir"],
        ManagedHarness::Omp => &["--session-dir", "--profile", "OMP_PROFILE"],
        ManagedHarness::Crush => &["--data-dir"],
        _ => &[],
    };
    let selectors = [store_override_vars(harness), flags].concat().join("/");
    let hint = if selectors.is_empty() { " from the original environment".to_owned() } else { format!(" with the same {selectors}") };
    Some(anyhow::anyhow!(
        "linked {} session {} was launched under {} but this launch resolves {}; relaunch{hint} (or the same `ai-memory run --profile`) to resume it, or pass --fresh to start a new session",
        harness.as_str(),
        display_session_id(native_session_id),
        terminal_text(&recorded.to_string_lossy()),
        terminal_text(&current.to_string_lossy()),
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn records_are_keyed_by_engine_harness_and_session() {
        let tmp = tempfile::tempdir().unwrap();
        let one = StoreRecords { run_dir: tmp.path(), server: Path::new("/a.sock") };
        let two = StoreRecords { run_dir: tmp.path(), server: Path::new("/b.sock") };
        one.remember_session_store(ManagedHarness::Claude, "abc", Path::new("/s1"));
        assert_eq!(one.recorded_session_store("claude", "abc").unwrap(), Some(PathBuf::from("/s1")));
        assert_eq!(two.recorded_session_store("claude", "abc").unwrap(), None);
        assert!(store_mismatch_error(ManagedHarness::Claude, "abc", Some("/s1".into()), Path::new("/s1")).is_none());
        let error = store_mismatch_error(ManagedHarness::Claude, "abc", Some("/s1".into()), Path::new("/s2")).unwrap();
        assert!(error.to_string().contains("with the same CLAUDE_CONFIG_DIR"));
        let fresh = tmp.path().join("missing/deeper");
        assert!(effective_store(ManagedHarness::Claude, tmp.path(), tmp.path(), Some(&fresh)).ends_with("missing/deeper"));
    }
}
