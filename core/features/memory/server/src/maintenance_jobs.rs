//! The maintenance jobs upstream's server schedules that need no LLM, run
//! with upstream's defaults (plan 22 phase F, 2026-11-16). When they run is
//! maintenance.rs's: on events, never by a clock.
//!
//! **Copied code.** Origin: ai-memory fa0ec25dbe987b7574a7487ecf92f0873040c2f2
//! (v3.4.7), crates/ai-memory-cli/src/commands/serve.rs, copied 2026-11-16:
//! - `run_scheduled_sweep_tick` and `ABANDONED_SESSION_CUTOFF` → `forget_sweep`;
//! - `run_scheduled_lint_tick` → `rule_lint`;
//! - the hollow-project task in `start_maintenance_scheduler` (its constants
//!   `HOLLOW_PROJECT_MIN_AGE_DAYS`) → `hollow_projects`;
//! - `run_scheduled_embedding_backfill_tick` → `embedding_backfill`.
//!
//! The arguments are what upstream's defaults give (crates/ai-memory-cli/src/config.rs
//! `DecaySettings::default`, `MaintenanceSettings::default`, `Config::default`):
//! `DecayParams::default()` (λ 0.02/day, cold threshold 0.20, tombstones
//! hard-deleted after 180 days), breadth weight 0, observation and ledger
//! retention off, A2 compaction off, A3 cold-cluster dedup off, and the
//! scheduled lint rule-based (`use_llm: false`, no embedding: upstream keeps
//! the A5 detector for the lint a user asks for). Cadex has no config file
//! for these: the engine mirrors upstream's defaults.

use std::sync::Arc;
use std::time::{Duration, Instant};

use ai_memory_consolidate::{
    ColdClusterDedup, EmbedBackfillOptions, EmbeddingCoord, LedgerRetention, LintOptions,
    ObservationRetention, run_embedding_backfill, run_lint, run_sweep_with_ledgers,
};
use ai_memory_llm::Embedder;
use ai_memory_store::{DecayParams, ReaderPool, WriterHandle};
use ai_memory_wiki::Wiki;
use anyhow::{Result, bail};
use tokio_util::sync::CancellationToken;
use tracing::info;

const DAY: Duration = Duration::from_secs(86_400);

/// Upstream's `ABANDONED_SESSION_CUTOFF` (serve.rs): a session open this
/// long with no activity is closed by the forget sweep (no usage, no
/// consolidation, no handoff).
const ABANDONED_SESSION_CUTOFF: Duration = Duration::from_secs(48 * 60 * 60);
/// Upstream's `HOLLOW_PROJECT_MIN_AGE_DAYS`: a week before an empty project
/// row counts as noise, so a project made just before its first event is
/// never raced.
const HOLLOW_PROJECT_MIN_AGE_DAYS: u32 = 7;

/// One job, its stamp name and how often it may run.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum Job {
    ForgetSweep,
    HollowProjects,
    RuleLint,
    EmbeddingBackfill,
}

impl Job {
    pub(crate) const ALL: [Job; 4] = [Job::ForgetSweep, Job::HollowProjects, Job::RuleLint, Job::EmbeddingBackfill];

    pub(crate) fn name(self) -> &'static str {
        match self {
            Job::ForgetSweep => "forget-sweep",
            Job::HollowProjects => "hollow-projects",
            Job::RuleLint => "rule-lint",
            Job::EmbeddingBackfill => "embedding-backfill",
        }
    }

    /// The least time between two runs. Sweep and lint: upstream's
    /// `forget_sweep_interval_secs` and `lint_interval_secs` (86,400); hollow
    /// projects: its `HOLLOW_SWEEP_INTERVAL` (a day). The embedding backfill
    /// upstream runs once per server start; Cadex's engine starts with each
    /// working period, so it gets an hour between runs (Cadex's choice,
    /// 2026-11-16): pages written while the model was absent get vectors
    /// soon, and a busy day does not rescan every scope at every start.
    pub(crate) fn min_interval(self) -> Duration {
        match self {
            Job::ForgetSweep | Job::HollowProjects | Job::RuleLint => DAY,
            Job::EmbeddingBackfill => Duration::from_secs(3_600),
        }
    }

    /// Whether a SessionEnd may run it. The backfill is upstream's start-up
    /// pass only; the others are its timers, which here any event stands in for.
    pub(crate) fn on_session_end(self) -> bool {
        !matches!(self, Job::EmbeddingBackfill)
    }
}

/// What the jobs read and write.
pub(crate) struct Stores {
    pub(crate) reader: ReaderPool,
    pub(crate) writer: WriterHandle,
    pub(crate) wiki: Wiki,
    pub(crate) embedder: Option<Arc<dyn Embedder>>,
}

/// Run one job. `Ok(true)`: it did its work (the stamp is written);
/// `Ok(false)`: nothing to run it with (no embedder), no stamp; `Err`: it
/// failed in some scope, and the next event tries again, as upstream retries
/// a failed tick instead of waiting a full interval.
pub(crate) async fn run(job: Job, s: &Stores, stop: &CancellationToken) -> Result<bool> {
    let started = Instant::now();
    match job {
        Job::ForgetSweep => forget_sweep(s, stop).await?,
        Job::HollowProjects => hollow_projects(s).await?,
        Job::RuleLint => rule_lint(s, stop).await?,
        Job::EmbeddingBackfill => {
            let Some(embedder) = s.embedder.as_ref() else { return Ok(false) };
            embedding_backfill(s, embedder, stop).await?;
        }
    }
    info!(job = job.name(), ms = started.elapsed().as_millis() as u64, "maintenance job completed");
    Ok(true)
}

/// Upstream's forget sweep over every scope: TTL-expired pages hard-deleted,
/// cold episodic pages evicted (file removed, row tombstoned), tombstones past
/// 180 days hard-deleted; then sessions idle 48 h closed.
async fn forget_sweep(s: &Stores, stop: &CancellationToken) -> Result<()> {
    let params = DecayParams::default();
    // Upstream's A3 coordinate is the running embedder's; with dedup off
    // (its default) the coordinate only matters if someone turns it on.
    let embedding = s.embedder.as_ref().map(|e| EmbeddingCoord {
        provider: e.provider().to_string(),
        model: e.model_identity(),
        dim: e.dim(),
    });
    let dedup = ColdClusterDedup { enabled: false, embedding, min_pts: 0, max_eps: 0.0 };
    let (mut errors, mut evicted, mut expired, mut hard_deleted) = (0usize, 0usize, 0usize, 0usize);
    for scope in s.reader.list_all_scopes().await? {
        if stop.is_cancelled() {
            bail!("engine stopping");
        }
        match run_sweep_with_ledgers(
            &s.reader, &s.writer, Some(&s.wiki), scope.workspace_id, scope.project_id, &params, 0.0,
            ObservationRetention::default(), false, dedup.clone(), LedgerRetention::default(), false,
        )
        .await
        {
            Ok(report) => {
                evicted += report.evicted.iter().filter(|p| p.deleted).count();
                expired += report.expired.len();
                hard_deleted += report.hard_deleted;
            }
            Err(e) => {
                errors += 1;
                tracing::warn!(workspace = %scope.workspace_name, project = %scope.project_name, error = %e, "forget sweep failed for scope");
            }
        }
    }
    let cutoff = crate::maintenance_state::now_us() - i64::try_from(ABANDONED_SESSION_CUTOFF.as_micros()).unwrap_or(i64::MAX);
    let closed = match s.writer.close_abandoned_sessions(cutoff).await {
        Ok(closed) => closed,
        Err(e) => {
            errors += 1;
            tracing::warn!(error = %e, "abandoned-session close failed");
            0
        }
    };
    info!(evicted, expired, hard_deleted, abandoned_sessions_closed = closed, errors, "forget sweep");
    if errors > 0 {
        bail!("forget sweep had {errors} errors");
    }
    Ok(())
}

/// Upstream's hollow-project sweep: project rows with nothing in them
/// (no pages, sessions, observations, handoffs, workstreams, messages),
/// older than a week, deleted. Nothing exists to lose.
async fn hollow_projects(s: &Stores) -> Result<()> {
    let deleted = s.writer.sweep_hollow_projects(HOLLOW_PROJECT_MIN_AGE_DAYS).await?;
    if !deleted.is_empty() {
        info!(count = deleted.len(), projects = deleted.join(", "), "hollow-project sweep deleted empty project rows");
    }
    Ok(())
}

/// Upstream's scheduled lint, rule-based: per project, `_lint/report.md`
/// written with the findings (stale episodic pages, empty bodies, duplicate
/// titles, broken cross-project links, declared contradictions, flagged
/// feedback, rule pages to copy into CLAUDE.md), or removed when clean.
async fn rule_lint(s: &Stores, stop: &CancellationToken) -> Result<()> {
    let (mut findings, mut errors) = (0usize, 0usize);
    for scope in s.reader.list_all_scopes().await? {
        if stop.is_cancelled() {
            bail!("engine stopping");
        }
        let options = LintOptions {
            dry_run: false,
            use_llm: false,
            decay: DecayParams::default(),
            embedding: None,
            contradiction_band_min: ai_memory_consolidate::DEFAULT_CONTRADICTION_SIM_LOW,
            contradiction_band_max: ai_memory_consolidate::DEFAULT_CONTRADICTION_SIM_HIGH,
        };
        match run_lint(&s.reader, &s.wiki, None, scope.workspace_id, scope.project_id, options).await {
            Ok(report) => findings += report.findings.len(),
            Err(e) => {
                errors += 1;
                tracing::warn!(workspace = %scope.workspace_name, project = %scope.project_name, error = %e, "lint failed for scope");
            }
        }
    }
    info!(findings, errors, "rule-based lint");
    if errors > 0 {
        bail!("lint had {errors} scope errors");
    }
    Ok(())
}

/// Upstream's start-up embedding backfill: vectors for the pages that have
/// none under the local model (written while it was absent). A page whose
/// embedding failed (the model still downloading) leaves the run unstamped,
/// so the next start tries again.
async fn embedding_backfill(s: &Stores, embedder: &Arc<dyn Embedder>, stop: &CancellationToken) -> Result<()> {
    let (mut embedded, mut failed, mut errors) = (0usize, 0usize, 0usize);
    for scope in s.reader.list_all_scopes().await? {
        if stop.is_cancelled() {
            bail!("engine stopping");
        }
        match run_embedding_backfill(&s.reader, &s.writer, &s.wiki, embedder, scope.workspace_id, scope.project_id, EmbedBackfillOptions::default()).await {
            Ok(counts) => {
                embedded += counts.embedded;
                failed += counts.failed;
            }
            Err(e) => {
                errors += 1;
                tracing::warn!(workspace = %scope.workspace_name, project = %scope.project_name, error = %e, "embedding backfill failed for scope");
            }
        }
    }
    info!(embedded, failed, errors, "embedding backfill");
    if errors > 0 || failed > 0 {
        bail!("embedding backfill: {failed} pages failed, {errors} scope errors");
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn names_are_unique_and_intervals_follow_upstream() {
        let names: std::collections::HashSet<_> = Job::ALL.iter().map(|j| j.name()).collect();
        assert_eq!(names.len(), Job::ALL.len());
        assert_eq!(Job::ForgetSweep.min_interval(), Duration::from_secs(86_400));
        assert_eq!(Job::RuleLint.min_interval(), Duration::from_secs(86_400));
        assert_eq!(Job::HollowProjects.min_interval(), Duration::from_secs(86_400));
        assert!(!Job::EmbeddingBackfill.on_session_end() && Job::ForgetSweep.on_session_end());
    }
}
