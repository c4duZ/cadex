//! The memory agent's cost ledger, `<data-dir>/agent/ledger.jsonl` (ADR
//! 0029: "cada um registrado com custo e versão do Claude Code"; plan 22
//! phase G, 2026-11-16). One line per `claude -p` call, and one line with
//! no cost for a job that ended without a call worth knowing about (the
//! daily budget reached, the session page the agent kept, a dream with no
//! vectors). The day's spend is summed from it before every job and every
//! call, in the local day (the owner's "per day" is the one on his clock).
//!
//! The folder is 0700 and the file 0600: lines name projects and sessions.

use std::io::Write;
use std::os::unix::fs::{DirBuilderExt, OpenOptionsExt};
use std::path::{Path, PathBuf};
use std::sync::Mutex;

use serde::{Deserialize, Serialize};

/// One line.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub(crate) struct Entry {
    /// RFC 3339, UTC.
    pub(crate) at: String,
    pub(crate) kind: String,
    pub(crate) workspace: String,
    pub(crate) project: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(crate) session: Option<String>,
    /// The session whose end set the job off, when it is not `session`: an
    /// auto-improve line names the session it reviewed, and the ledger read
    /// "session 3cd2e5f6" for the review of 98ee49fa (plan 35 G, the
    /// bkdg-center case 2026-11-18).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(crate) trigger: Option<String>,
    pub(crate) cost_usd: f64,
    pub(crate) ok: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(crate) error: Option<String>,
    #[serde(default)]
    pub(crate) claude_version: Option<String>,
    pub(crate) model: String,
    /// The call's request and response, relative to `<data-dir>/agent`
    /// (audit.rs, plan 35 D); absent on a line with no call.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(crate) call: Option<String>,
}

/// Appends from the worker and from a call never interleave.
static WRITE: Mutex<()> = Mutex::new(());

/// `<data-dir>/agent`, made 0700 if missing.
pub(crate) fn dir(data_dir: &Path) -> std::io::Result<PathBuf> {
    let dir = data_dir.join("agent");
    if !dir.is_dir() {
        std::fs::DirBuilder::new().recursive(true).mode(0o700).create(&dir)?;
    }
    Ok(dir)
}

fn file(data_dir: &Path) -> PathBuf {
    data_dir.join("agent").join("ledger.jsonl")
}

/// Now, as the ledger writes it.
pub(crate) fn now() -> String {
    jiff::Timestamp::now().to_string()
}

/// Append one line. A ledger that cannot be written is logged, never fatal:
/// the spend check then reads less than was spent, so the caller's per-call
/// `--max-budget-usd` stays the bound.
pub(crate) fn append(data_dir: &Path, entry: &Entry) {
    let _guard = WRITE.lock().unwrap_or_else(|e| e.into_inner());
    let result = dir(data_dir).and_then(|_| {
        let mut line = serde_json::to_string(entry).map_err(std::io::Error::other)?;
        line.push('\n');
        std::fs::OpenOptions::new().create(true).append(true).mode(0o600).open(file(data_dir))?.write_all(line.as_bytes())
    });
    if let Err(error) = result {
        tracing::warn!(%error, "memory agent ledger not written");
    }
}

/// Every readable line, oldest first.
pub(crate) fn read(data_dir: &Path) -> Vec<Entry> {
    let Ok(text) = std::fs::read_to_string(file(data_dir)) else { return Vec::new() };
    text.lines().filter_map(|line| serde_json::from_str(line).ok()).collect()
}

/// The local date of an `at`.
fn local_day(at: &str) -> Option<jiff::civil::Date> {
    let ts: jiff::Timestamp = at.parse().ok()?;
    Some(ts.to_zoned(jiff::tz::TimeZone::system()).date())
}

/// What the agent spent today, local day.
pub(crate) fn spent_today(data_dir: &Path) -> f64 {
    let today = jiff::Zoned::now().date();
    read(data_dir)
        .iter()
        .filter(|e| local_day(&e.at) == Some(today))
        .map(|e| if e.cost_usd.is_finite() { e.cost_usd.max(0.0) } else { 0.0 })
        .sum::<f64>()
        // An empty f64 sum is -0.0, which the status showed as "-0.0"
        // (real test, 2026-11-16).
        + 0.0
}

/// Whether one more call at `call_budget` stays within `daily_budget`.
pub(crate) fn fits(data_dir: &Path, call_budget: f64, daily_budget: f64) -> bool {
    spent_today(data_dir) + call_budget <= daily_budget + 1e-9
}

/// The last `n` lines, newest last.
pub(crate) fn recent(data_dir: &Path, n: usize) -> Vec<Entry> {
    let all = read(data_dir);
    let skip = all.len().saturating_sub(n);
    all.into_iter().skip(skip).collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::fs::PermissionsExt;

    #[test]
    fn today_counts_and_yesterday_does_not() {
        let tmp = tempfile::tempdir().unwrap();
        let day = jiff::SignedDuration::from_hours(26);
        let old = jiff::Timestamp::now().checked_sub(day).unwrap().to_string();
        append(tmp.path(), &Entry { at: old, cost_usd: 5.0, ..Entry::default() });
        append(tmp.path(), &Entry { at: now(), cost_usd: 0.5, ..Entry::default() });
        append(tmp.path(), &Entry { at: now(), cost_usd: 0.2, ..Entry::default() });
        assert!((spent_today(tmp.path()) - 0.7).abs() < 1e-9);
        assert!(fits(tmp.path(), 0.3, 1.0) && !fits(tmp.path(), 0.31, 1.0));
        assert_eq!(recent(tmp.path(), 2).len(), 2);
        let mode = |p: &Path| std::fs::metadata(p).unwrap().permissions().mode() & 0o777;
        assert_eq!(mode(&tmp.path().join("agent")), 0o700);
        assert_eq!(mode(&file(tmp.path())), 0o600);
    }
}
