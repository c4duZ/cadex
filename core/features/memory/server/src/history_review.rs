//! Imported history is never reviewed by auto-improve on its own (plan 35
//! phase G, 2026-11-19).
//!
//! **Why.** Upstream's scheduler reviews only sessions that end after it
//! first sees a project: serve.rs calls `initialize_auto_improve_scheduler_scopes`
//! at startup, and `ensure_scheduler_state` puts the watermark at the newest
//! `ended_at` ("Historical sessions are not reviewed automatically",
//! docs/auto-improvement-loop.md). Cadex imports a project's history after it
//! is up (import_jobs.rs), and in the owner's bkdg-center the watermark was
//! born at 0 before the import (2026-11-18 15:38): the whole backfill was
//! queued, oldest first, and the first review (98ee49fa) wrote four pages
//! about a system the Center does not have.
//!
//! **How.** At the start, upstream's own initialization (`init`). Then each
//! session an import writes is claimed for the scheduler at once
//! (`claim_auto_improve_scheduler_session`, upstream's public writer call,
//! after `ensure_auto_improve_scheduler_state`): a claim with no failure is
//! never a candidate again, whatever the watermark says. Upstream has no
//! public call that moves the watermark, and moving it past the newest
//! imported session would also drop the live sessions still waiting their
//! turn (one review per project per hour, agent/improve.rs); a claim drops
//! exactly the imported one. A session at or behind the watermark is not
//! claimable and not a candidate either. The owner can still review any of
//! them by hand (upstream's manual path does not look at claims), or have the
//! history distilled by the bootstrap, with approval.
//!
//! Both imports go through here: the project's history and the sessions that
//! ran outside Cadex (Claude Code with no Cadex hooks). The second are history
//! too: what upstream's own `backfill` brings in, which its scheduler skips.

use std::time::{Duration, Instant};

use ai_memory_core::SessionId;
use ai_memory_store::{ReaderPool, WriterHandle};

/// How long an imported session's end may take to show in the store.
const END_WAIT: Duration = Duration::from_secs(5);

/// Upstream's startup step: a scheduler state, watermark at the newest end,
/// for every project that has none.
pub(crate) async fn init(reader: &ReaderPool, writer: &WriterHandle) {
    match ai_memory_consolidate::auto_improve_schedule::initialize_auto_improve_scheduler_scopes(reader, writer).await {
        Ok((scopes, 0)) => tracing::debug!(scopes, "auto-improve scheduler state initialized"),
        Ok((scopes, errors)) => tracing::warn!(scopes, errors, "auto-improve scheduler state partly initialized"),
        Err(error) => tracing::warn!(%error, "auto-improve scheduler state init failed"),
    }
}

/// Keep the imported session `id` out of the auto-improve queue. Returns
/// whether a claim was made (false: already behind the watermark, already
/// claimed or reviewed, or not ended).
pub(crate) async fn skip(reader: &ReaderPool, writer: &WriterHandle, id: &str) -> bool {
    let session = SessionId::from_native(id);
    let Ok(Some((ws, proj, _))) = reader.find_session_scope(session).await else { return false };
    if let Err(error) = writer.ensure_auto_improve_scheduler_state(ws, proj).await {
        tracing::warn!(%error, "auto-improve state init failed");
        return false;
    }
    let Some(ended_at) = ended_at(reader, session).await else {
        tracing::debug!(session = %id, "imported session has no end; not claimed");
        return false;
    };
    match writer.claim_auto_improve_scheduler_session(ws, proj, session, ended_at).await {
        Ok(claimed) => claimed,
        Err(error) => {
            tracing::warn!(%error, session = %id, "imported session not kept from auto-improve");
            false
        }
    }
}

/// The session's `ended_at`; the replayed end may land a moment after the
/// batch is answered.
async fn ended_at(reader: &ReaderPool, session: SessionId) -> Option<i64> {
    let deadline = Instant::now() + END_WAIT;
    loop {
        let read = reader
            .with_conn(move |conn| {
                let ended = conn.query_row(
                    "SELECT ended_at FROM sessions WHERE id = ?1",
                    rusqlite::params![session.as_bytes()],
                    |row| row.get::<_, Option<i64>>(0),
                );
                Ok(ended.ok().flatten())
            })
            .await;
        if let Ok(Some(ended)) = read {
            return Some(ended);
        }
        if Instant::now() >= deadline {
            return None;
        }
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
}
