//! The server-side checks of the health screen (plan 40 B).
//!
//! **Copied** from ai-memory v3.5.0 (411d90d, 2026-11-18):
//! crates/ai-memory-web/src/health.rs, `ProcessState`, `SpoolState`,
//! `JournalState`, `HealthSnapshot`, `CheckStatus`, `HealthCheck`,
//! `SPOOL_STUCK_AFTER_MS`, `spool_is_stuck` and `localized_checks`. Changed
//! for Cadex: the detail lines are upstream's English text (its
//! locales/en/web.ftl) written in place, since the localizer and its
//! catalogs cost 0.48 MB of the release binary (measured 2026-11-19) and the
//! app writes its own words; the provider checks (`llm_provider`,
//! `llm_task_provider`, `embedding_provider`) are out, Cadex calling no
//! provider. The ids, order, thresholds and fix commands are upstream's,
//! and tests/panel_api.rs holds the ids equal to its health page. At an
//! upstream update, compare with that file.

use ai_memory_core::{IngestMetricsSnapshot, fix_lines};
use ai_memory_store::{DerivedIndexStatus, SessionConsolidationQueue, StorageStatus};

/// Process-side state for one read. `None` means the engine cannot see it.
#[derive(Debug, Clone, Copy, Default)]
pub(crate) struct ProcessState {
    /// `(queued, capacity)` of the single writer's channel.
    pub write_queue: Option<(usize, usize)>,
    pub spool: Option<SpoolState>,
    pub journal: Option<JournalState>,
}

#[derive(Debug, Clone, Copy, Default)]
pub(crate) struct SpoolState {
    pub pending: usize,
    pub oldest_age_ms: Option<u64>,
    pub retries_total: u64,
    /// Most events the spool holds; 0 is no cap.
    pub capacity: usize,
}

#[derive(Debug, Clone, Copy, Default)]
pub(crate) struct JournalState {
    pub pending: usize,
    pub degraded: usize,
    pub finish_failed: usize,
    pub unreadable: bool,
}

/// Every input of one read; providers aside, upstream's `HealthSnapshot`.
pub(crate) struct HealthSnapshot {
    pub ingest: IngestMetricsSnapshot,
    pub process: ProcessState,
    pub derived: DerivedIndexStatus,
    pub storage: Option<StorageStatus>,
    pub consolidation: SessionConsolidationQueue,
    /// The configured embedder's (provider, stored identity, dim).
    pub embedder: Option<(String, String, u32)>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum CheckStatus {
    Warn,
    Error,
}

impl CheckStatus {
    pub(crate) fn label(self) -> &'static str {
        match self {
            Self::Warn => "warn",
            Self::Error => "error",
        }
    }
}

pub(crate) struct HealthCheck {
    pub id: &'static str,
    pub status: CheckStatus,
    pub detail: String,
    pub fix: Option<&'static str>,
}

/// How old the oldest spooled event may get before the spool counts as stuck.
const SPOOL_STUCK_AFTER_MS: u64 = 15 * 60 * 1000;

fn spool_is_stuck(spool: &SpoolState) -> bool {
    spool.pending > 0 && (spool.retries_total > 0 || spool.oldest_age_ms.is_none_or(|age| age >= SPOOL_STUCK_AFTER_MS))
}

fn spool_checks(spool: &SpoolState, push: &mut impl FnMut(&'static str, CheckStatus, String, Option<&'static str>)) {
    if spool.capacity > 0 && spool.pending >= spool.capacity {
        let detail = format!(
            "The hook spool is full ({} events): newly captured events are dropped until space is available.",
            spool.pending
        );
        push("spool_evicting", CheckStatus::Error, detail, Some(fix_lines::RECOVER));
    } else if spool_is_stuck(spool) {
        let age = spool.oldest_age_ms.map_or_else(|| "age unknown".to_owned(), |ms| format!("{} min", ms / 60_000));
        let detail = format!(
            "{} hook event(s) wait in the local spool and delivery looks stuck (oldest {age}, {} failed attempt(s)).",
            spool.pending, spool.retries_total
        );
        push("spool_pending", CheckStatus::Warn, detail, Some(fix_lines::RECOVER));
    }
}

fn vector_checks(s: &HealthSnapshot, push: &mut impl FnMut(&'static str, CheckStatus, String, Option<&'static str>)) {
    let Some((provider, model, dim)) = &s.embedder else { return };
    let stale: u64 = s
        .derived
        .embedding_triples
        .iter()
        .filter(|t| &t.provider != provider || &t.model != model || t.dim != *dim)
        .map(|t| t.count)
        .sum();
    if stale > 0 {
        let detail = format!("{stale} stored vector(s) were made under another provider, model or dimension and are ignored.");
        push("stale_vectors", CheckStatus::Warn, detail, Some(fix_lines::EMBED_FORCE));
    }
    let (missing, failed) = (s.derived.latest_pages_missing_embeddings, s.derived.embed_failures_unresolved);
    if missing > 0 || failed > 0 {
        let detail = format!("{missing} latest page(s) have no vector ({failed} after a failed or skipped embed).");
        push("missing_vectors", CheckStatus::Warn, detail, Some(fix_lines::EMBED));
    }
}

/// The checks that fail for `s`, errors first; empty is a healthy engine.
pub(crate) fn checks(s: &HealthSnapshot) -> Vec<HealthCheck> {
    let mut out = Vec::new();
    let mut push = |id, status, detail: String, fix: Option<&'static str>| out.push(HealthCheck { id, status, detail, fix });
    let shed = s.ingest.shed_saturated + s.ingest.shed_rate_limited;
    if shed > 0 {
        let detail = format!(
            "{shed} hook event(s) were answered 429 since the server started ({} saturated, {} rate-limited); clients spool and retry them.",
            s.ingest.shed_saturated, s.ingest.shed_rate_limited
        );
        push("hook_shed", CheckStatus::Warn, detail, None);
    }
    if s.ingest.failed > 0 {
        let detail = format!("{} hook delivery(ies) failed to store since the server started.", s.ingest.failed);
        push("hook_failed", CheckStatus::Error, detail, None);
    }
    if let Some((queued, capacity)) = s.process.write_queue
        && capacity > 0
        && queued.saturating_mul(4) >= capacity.saturating_mul(3)
    {
        push("write_queue", CheckStatus::Warn, format!("The write queue holds {queued} of {capacity} commands."), None);
    }
    if let Some(spool) = s.process.spool {
        spool_checks(&spool, &mut push);
    }
    if let Some(journal) = s.process.journal {
        if journal.unreadable {
            push("journal_unreadable", CheckStatus::Error, "The recovery journal could not be read.".into(), Some(fix_lines::RECOVER));
        } else if journal.pending > 0 {
            let detail = format!(
                "{} run(s) wait in the recovery journal ({} degraded, {} finish-failed).",
                journal.pending, journal.degraded, journal.finish_failed
            );
            push("journal_pending", CheckStatus::Warn, detail, Some(fix_lines::RECOVER));
        }
    }
    vector_checks(s, &mut push);
    match s.storage {
        None => push(
            "storage_unreadable",
            CheckStatus::Warn,
            "The database storage figures could not be read; reclaim advice is unavailable.".into(),
            None,
        ),
        Some(st) if fix_lines::reclaim_advised(st.reclaimable_bytes, st.database_bytes) => {
            let detail = format!(
                "{} of the {}-byte database is reclaimable; compacting blocks writes while it runs.",
                st.reclaimable_bytes, st.database_bytes
            );
            push("storage_reclaim", CheckStatus::Warn, detail, Some(fix_lines::COMPACT));
        }
        Some(_) => {}
    }
    if s.consolidation.failed > 0 {
        let detail = format!("{} session consolidation job(s) gave up after their retries.", s.consolidation.failed);
        push("consolidation_failed", CheckStatus::Warn, detail, None);
    }
    out.sort_by_key(|check| match check.status {
        CheckStatus::Error => 0,
        CheckStatus::Warn => 1,
    });
    out
}
