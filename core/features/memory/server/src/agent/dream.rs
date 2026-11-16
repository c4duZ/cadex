//! The dream pass (plan 22 phase G: "dream (computador parado; para quando
//! o dono volta)", 2026-11-16): upstream's `run_dream_pass` over the job's
//! project, merging clusters of cold pages, with the project's account.
//!
//! When: on the owner's click (`/cadex/agent/run-dream`), or after a live
//! SessionEnd when no other session is live and the Mac has been idle 10
//! min (jobs.rs). Never by a clock.
//!
//! Stopping: an automatic dream reads the Mac's idle time every 30 s while
//! it runs (the only polling the agent does, and only during a dream) and
//! cancels upstream's `DreamCancel` once the owner is back (idle under 60 s);
//! upstream checks it between clusters. Upstream's own scheduler does the
//! same with its activity clock (serve.rs `run_dream_scheduler_loop`, a 2 s
//! poll); the Mac's idle time stands in for its clock, since the owner's
//! activity here is the keyboard and mouse, not the server's requests. A
//! dream the owner asked for is not stopped by his own activity.
//!
//! The idle time comes from `ioreg -c IOHIDSystem` (`HIDIdleTime`, in
//! nanoseconds): no IOKit binding, so no `unsafe`. Upstream's dream clusters
//! the stored vectors; with no embedder (`--no-embeddings`) there is nothing
//! to cluster and the job ends with a note.

use std::sync::Arc;
use std::time::Duration;

use ai_memory_consolidate::{DreamCancel, DreamConfig, EmbeddingCoord, run_dream_pass};
use ai_memory_llm::LlmProvider;
use ai_memory_store::DecayParams;
use tracing::{info, warn};

use super::jobs::Step;

/// Reads how long the Mac has been idle; `None` when it cannot tell.
pub(crate) type IdleReader = Arc<dyn Fn() -> Option<Duration> + Send + Sync>;

/// Owner back: idle under this stops an automatic dream.
pub(crate) const BACK: Duration = Duration::from_secs(60);
/// How often a running automatic dream reads the idle time.
const POLL: Duration = Duration::from_secs(30);

/// `HIDIdleTime` from `ioreg`, the system's time since the last input.
pub(crate) fn system_idle() -> Option<Duration> {
    let out = std::process::Command::new("/usr/sbin/ioreg").args(["-c", "IOHIDSystem", "-d", "4"]).output().ok()?;
    parse_idle(&String::from_utf8_lossy(&out.stdout))
}

/// The first `"HIDIdleTime" = <ns>` of an `ioreg` listing.
pub(crate) fn parse_idle(listing: &str) -> Option<Duration> {
    let line = listing.lines().find(|l| l.contains("\"HIDIdleTime\""))?;
    let ns: u64 = line.rsplit('=').next()?.trim().parse().ok()?;
    Some(Duration::from_nanos(ns))
}

/// The idle reader and its poll interval. In a debug build only,
/// `CADEX_MEMORY_TEST_IDLE_FILE` (a file holding seconds, read each time)
/// and `CADEX_MEMORY_TEST_IDLE_POLL_MS` stand in for the Mac's, for the
/// tests; a release build never reads them.
pub(crate) fn idle_source() -> (IdleReader, Duration) {
    #[cfg(debug_assertions)]
    if let Some(file) = std::env::var_os("CADEX_MEMORY_TEST_IDLE_FILE") {
        let poll = std::env::var("CADEX_MEMORY_TEST_IDLE_POLL_MS").ok().and_then(|v| v.parse().ok()).map_or(POLL, Duration::from_millis);
        let reader: IdleReader = Arc::new(move || {
            let secs: f64 = std::fs::read_to_string(&file).ok()?.trim().parse().ok()?;
            Some(Duration::from_secs_f64(secs))
        });
        return (reader, poll);
    }
    (Arc::new(system_idle), POLL)
}

/// Until `cancel` is cancelled: read the idle time every `poll` and cancel
/// once the owner is back. An unreadable idle time stops the dream too:
/// the agent cannot tell the owner is away.
pub(crate) async fn watch_idle(idle: IdleReader, poll: Duration, cancel: DreamCancel) {
    while !cancel.is_cancelled() {
        tokio::time::sleep(poll).await;
        if idle().is_none_or(|d| d < BACK) {
            info!("the owner is back: the dream stops");
            cancel.cancel();
        }
    }
}

/// Run the dream pass over the job's project.
pub(crate) async fn run(step: &Step<'_>) {
    let ctx = step.ctx;
    let Some(embedder) = ctx.embedder.as_ref() else {
        return step.note("dream", true, "no embedder: nothing to cluster");
    };
    let Some((ws, proj)) = super::improve::scope_ids(step).await else {
        return step.note("dream", false, "project not in the memory");
    };
    let cfg = DreamConfig {
        enabled: true,
        embedding: Some(EmbeddingCoord { provider: embedder.provider().to_string(), model: embedder.model_identity(), dim: embedder.dim() }),
        ..DreamConfig::default()
    };
    let cancel = DreamCancel::new();
    let watcher = (!step.job.manual).then(|| tokio::spawn(watch_idle(ctx.idle.clone(), ctx.idle_poll, cancel.clone())));
    let llm = step.provider("dream");
    // Upstream's defaults (config.rs `DecaySettings::default`): breadth weight 0.
    let result = run_dream_pass(&ctx.reader, &ctx.wiki, Some(&*llm as &dyn LlmProvider), ws, proj, &DecayParams::default(), 0.0, &cfg, &cancel, false).await;
    let stopped = cancel.is_cancelled();
    cancel.cancel();
    if let Some(watcher) = watcher {
        watcher.abort();
    }
    match result {
        Ok(report) => {
            info!(merged = report.clusters_merged, superseded = report.pages_superseded, cancelled = report.cancelled || stopped, "memory agent dream");
            if stopped {
                step.note("dream", true, "stopped: the owner came back");
            }
        }
        Err(error) => warn!(%error, "memory agent dream failed"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU64, Ordering};

    #[test]
    fn the_idle_time_is_read_from_ioreg() {
        let listing = "  | |   \"HIDIdleTime\" = 734000000000\n  | |   \"Other\" = 1";
        assert_eq!(parse_idle(listing), Some(Duration::from_secs(734)));
        assert_eq!(parse_idle("nothing"), None);
    }

    #[tokio::test]
    async fn a_dream_stops_when_the_owner_comes_back() {
        let secs = Arc::new(AtomicU64::new(900));
        let seen = secs.clone();
        let idle: IdleReader = Arc::new(move || Some(Duration::from_secs(seen.load(Ordering::SeqCst))));
        let cancel = DreamCancel::new();
        let watcher = tokio::spawn(watch_idle(idle, Duration::from_millis(20), cancel.clone()));
        tokio::time::sleep(Duration::from_millis(120)).await;
        assert!(!cancel.is_cancelled(), "still away");
        secs.store(5, Ordering::SeqCst);
        tokio::time::timeout(Duration::from_secs(2), watcher).await.unwrap().unwrap();
        assert!(cancel.is_cancelled());
    }
}
