//! When each maintenance job last succeeded, in `<data-dir>/maintenance/<job>.json`,
//! and whether an event finds it due (plan 22 phase F, 2026-11-16).
//!
//! Upstream keeps this cadence in its store (`record_maintenance_job_success`)
//! and sleeps until the next one is due (serve.rs `run_persisted_maintenance_job`).
//! Cadex runs nothing by the clock: a job runs when an event (the engine's
//! start, a SessionEnd) finds it due, and an event that comes sooner is
//! skipped. The time is only read, never waited on. Kept in files of its own,
//! outside the store, so the rate limit is Cadex's and upstream's table is
//! never written from here.

use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};

/// What one job's file holds.
#[derive(Debug, Serialize, Deserialize)]
struct Stamp {
    /// Microseconds since the Unix epoch, as upstream's `last_success_at`.
    last_success_us: i64,
}

/// The folder of the stamps.
pub(crate) fn dir(data_dir: &Path) -> PathBuf {
    data_dir.join("maintenance")
}

fn file(data_dir: &Path, job: &str) -> PathBuf {
    dir(data_dir).join(format!("{job}.json"))
}

pub(crate) fn now_us() -> i64 {
    let since = SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default();
    i64::try_from(since.as_micros()).unwrap_or(i64::MAX)
}

/// The last success of `job`, if one was recorded and the file reads.
pub(crate) fn last_success(data_dir: &Path, job: &str) -> Option<i64> {
    let text = std::fs::read_to_string(file(data_dir, job)).ok()?;
    serde_json::from_str::<Stamp>(&text).ok().map(|s| s.last_success_us)
}

/// Whether a job last run at `last` is due at `now` with `min_interval`
/// between runs. Never run: due. A stamp in the future (the clock was set
/// back, a restored backup) is due too: upstream caps such a wait at one
/// interval (`maintenance_start_delay`), and with no timer the only cap an
/// event can apply is to run now.
pub(crate) fn is_due(last: Option<i64>, now: i64, min_interval: Duration) -> bool {
    let Some(last) = last else { return true };
    if last > now {
        return true;
    }
    let interval = i64::try_from(min_interval.as_micros()).unwrap_or(i64::MAX);
    now.saturating_sub(last) >= interval
}

/// `is_due` for `job` now, read from its file.
pub(crate) fn due_now(data_dir: &Path, job: &str, min_interval: Duration) -> bool {
    is_due(last_success(data_dir, job), now_us(), min_interval)
}

/// Record a success of `job` at `at` (written to a `.tmp`, then renamed, so
/// a crash never leaves half a stamp: half a stamp reads as "never run").
pub(crate) fn record(data_dir: &Path, job: &str, at: i64) -> Result<()> {
    let folder = dir(data_dir);
    std::fs::create_dir_all(&folder).with_context(|| format!("creating {}", folder.display()))?;
    let path = file(data_dir, job);
    let tmp = path.with_extension("json.tmp");
    std::fs::write(&tmp, serde_json::to_string(&Stamp { last_success_us: at })?)
        .with_context(|| format!("writing {}", tmp.display()))?;
    std::fs::rename(&tmp, &path).with_context(|| format!("renaming to {}", path.display()))?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    const DAY: Duration = Duration::from_secs(86_400);
    const DAY_US: i64 = 86_400_000_000;

    #[test]
    fn a_job_never_run_is_due() {
        assert!(is_due(None, 1_000, DAY));
    }

    #[test]
    fn a_job_run_within_its_interval_is_not_due() {
        let now = 100 * DAY_US;
        assert!(!is_due(Some(now - 1), now, DAY));
        assert!(!is_due(Some(now - DAY_US + 1), now, DAY));
        assert!(!is_due(Some(now), now, DAY));
    }

    #[test]
    fn a_job_run_one_interval_ago_or_more_is_due() {
        let now = 100 * DAY_US;
        assert!(is_due(Some(now - DAY_US), now, DAY));
        assert!(is_due(Some(now - 30 * DAY_US), now, DAY));
    }

    #[test]
    fn a_stamp_from_the_future_does_not_block_the_job() {
        let now = 100 * DAY_US;
        assert!(is_due(Some(now + 5 * DAY_US), now, DAY));
    }

    #[test]
    fn a_zero_interval_is_always_due() {
        assert!(is_due(Some(5), 5, Duration::ZERO));
    }

    #[test]
    fn a_recorded_success_reads_back_and_rate_limits() {
        let tmp = tempfile::tempdir().unwrap();
        assert_eq!(last_success(tmp.path(), "forget-sweep"), None);
        assert!(due_now(tmp.path(), "forget-sweep", DAY));
        record(tmp.path(), "forget-sweep", now_us()).unwrap();
        assert!(last_success(tmp.path(), "forget-sweep").is_some());
        assert!(!due_now(tmp.path(), "forget-sweep", DAY));
        assert!(due_now(tmp.path(), "rule-lint", DAY), "each job has its own stamp");
        record(tmp.path(), "forget-sweep", now_us() - 2 * DAY_US).unwrap();
        assert!(due_now(tmp.path(), "forget-sweep", DAY));
    }

    #[test]
    fn an_unreadable_stamp_counts_as_never_run() {
        let tmp = tempfile::tempdir().unwrap();
        std::fs::create_dir_all(dir(tmp.path())).unwrap();
        std::fs::write(file(tmp.path(), "rule-lint"), "{half").unwrap();
        assert_eq!(last_success(tmp.path(), "rule-lint"), None);
        assert!(due_now(tmp.path(), "rule-lint", DAY));
    }
}
