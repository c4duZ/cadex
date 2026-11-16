//! Replaying the recovery journal once the engine answers again: at the
//! start of every run that reached it, before the prepare. A run whose
//! finish failed is re-imported into the same run (`/recover/finish`); a
//! degraded launch's session is replayed through `/hook/batch` like an
//! imported transcript. Both re-export the exact recorded interval from the
//! native store and refuse it when its digests changed. Entries clear as
//! they succeed; failures stay with their reason.
//!
//! Copied from ai-memory v3.4.7 (fa0ec25), crates/ai-memory-cli/src/commands/
//! recovery.rs: `recover_entry`, `recovery_session_dir`,
//! `recover_finish_failed`, `failed_reason`, `recover_spool_only`,
//! `recover_degraded_run`; and backfill.rs's `import_exact_session_range`.
//! Changed for Cadex (2026-11-16): upstream replays only on a manual
//! `ai-memory recover`; Cadex has no such command, so `cadex-memory run` does
//! it; the degraded replay is replay.rs's (the hook items Cadex's own import
//! posts, with the harness's agent and the checkout's `[capture]` applied
//! first); a spool-only entry (no transcript adapter) clears once Cadex's
//! spool is empty, since the engine drains it when it starts (upstream
//! checks per-entry delivery evidence its own spool records).

use std::path::{Path, PathBuf};

use ai_memory_core::{ManagedRunId, Sanitizer, WorkstreamCheckpoint};
use ai_memory_workstream::{ExportedTranscript, TranscriptCapability, export_transcript_range, transcript_interval_digests, wait_for_transcript_flush};
use anyhow::{Result, anyhow, bail};

use super::args::Env;
use super::choice::harness_from_journal_name;
use super::import::import_batches;
use super::journal::{JournalEntry, JournalKind, finish_journal, load_journal};
use super::ledger_capture::LedgerCapture;
use super::uds_http::Client;
use crate::replay::{HookBatchAck, Target, acknowledged, hook_batch_end, items};

fn recovery_session_dir(entry: &JournalEntry) -> Option<PathBuf> {
    entry.session_dir.as_deref().map(|path| {
        let path = Path::new(path);
        if path.is_absolute() { path.to_path_buf() } else { Path::new(&entry.cwd).join(path) }
    })
}

/// The exact recorded interval, refused when it no longer matches.
async fn exact_range(entry: &JournalEntry, home: &Path) -> Result<(ai_memory_workstream::ManagedHarness, ExportedTranscript, String)> {
    let harness = harness_from_journal_name(&entry.harness).ok_or_else(|| anyhow!("journal names unsupported harness '{}'", entry.harness))?;
    let session = entry.native_session_id.as_deref().ok_or_else(|| anyhow!("the entry records no native transcript locator"))?;
    let expected = entry.event_digests.as_ref().ok_or_else(|| anyhow!("the entry has no exact ordered transcript identity; refusing replay"))?;
    let final_cursor = entry.final_cursor.as_deref().ok_or_else(|| anyhow!("the entry has no exact post-run transcript cursor; refusing replay"))?;
    let cwd = Path::new(&entry.cwd);
    let dir = recovery_session_dir(entry);
    let _ = wait_for_transcript_flush(harness, home, cwd, dir.as_deref(), session).await;
    let transcript = export_transcript_range(harness, home, cwd, dir.as_deref(), session, entry.source_cursor.as_deref(), final_cursor)
        .await
        .map_err(|error| anyhow!("native transcript re-export failed: {error:#}"))?;
    if &transcript_interval_digests(&transcript.events) != expected {
        bail!("native transcript changed since it was journaled; refusing non-identical replay");
    }
    Ok((harness, transcript, final_cursor.to_owned()))
}

async fn recover_finish_failed(client: &Client, entry: &JournalEntry, home: &Path, sanitizer: &Sanitizer) -> Result<usize> {
    let run_id = entry.run_id.as_deref().ok_or_else(|| anyhow!("finish-failed entry records no run id"))?;
    run_id.parse::<ManagedRunId>().map_err(|_| anyhow!("journal records an invalid run id {run_id}"))?;
    let (_, transcript, final_cursor) = exact_range(entry, home).await?;
    let transcript = ExportedTranscript { source_cursor: Some(final_cursor), ..transcript };
    let capture = LedgerCapture::for_checkout(Path::new(&entry.cwd));
    let run_path = format!("/workstream/runs/{run_id}/recover");
    import_batches(client, &run_path, transcript, WorkstreamCheckpoint::default(), entry.exit_code, sanitizer, &capture)
        .await
        .map_err(|error| anyhow!("managed finish failed: {error:#}"))
}

async fn post_items(client: &Client, all: &[crate::replay::HookItem]) -> Result<()> {
    let mut offset = 0;
    while offset < all.len() {
        let end = hook_batch_end(all, offset)?;
        let chunk = &all[offset..end];
        let ack: HookBatchAck = client.post_json("/hook/batch", &chunk).await?;
        if acknowledged(&ack, chunk)?.len() != chunk.len() {
            bail!("the engine took only part of a replayed batch");
        }
        offset = end;
    }
    Ok(())
}

async fn recover_degraded_run(client: &Client, entry: &JournalEntry, home: &Path) -> Result<usize> {
    let (harness, transcript, _) = exact_range(entry, home).await?;
    let capture = LedgerCapture::for_checkout(Path::new(&entry.cwd));
    let events = capture.filter_ledger_events(transcript.events);
    let transcript = ExportedTranscript { events, ..transcript };
    let target = Target { cwd: entry.cwd.clone(), workspace: Some(entry.workspace.clone()), agent: harness.agent_kind().as_str() };
    let session = entry.native_session_id.as_deref().unwrap_or_default();
    let (hook_items, content) = items(&target, session, &transcript);
    post_items(client, &hook_items).await.map_err(|error| anyhow!("native transcript replay failed: {error:#}"))?;
    Ok(content)
}

async fn recover_entry(client: &Client, env: &Env, entry: &JournalEntry, sanitizer: &Sanitizer) -> Result<usize> {
    let recorded = entry.server_url.trim_end_matches('/');
    let current = env.socket.to_string_lossy();
    if recorded.is_empty() || recorded != current {
        bail!("refusing to replay an entry recorded for {recorded:?} against {current}");
    }
    let spool_only = entry.spool_only
        || harness_from_journal_name(&entry.harness).is_some_and(|h| h.transcript_capability() == TranscriptCapability::SpoolOnly);
    if spool_only {
        let pending = std::fs::read_dir(env.data_dir.join("spool")).map(|d| d.flatten().count()).unwrap_or(0);
        return if pending == 0 { Ok(0) } else { Err(anyhow!("the hook spool still holds {pending} event(s); retrying on the next run")) };
    }
    match entry.kind {
        JournalKind::FinishFailed => recover_finish_failed(client, entry, &env.home, sanitizer).await,
        JournalKind::DegradedRun => recover_degraded_run(client, entry, &env.home).await,
    }
}

/// Work the journal; a problem with the journal itself only warns.
pub(crate) async fn replay_journal(client: &Client, env: &Env) {
    let run_dir = env.run_dir();
    let entries = match load_journal(&run_dir) {
        Ok(entries) => entries,
        Err(error) => {
            eprintln!("ai-memory: could not read the recovery journal ({error:#}); its runs stay unrecovered");
            return;
        }
    };
    if entries.is_empty() {
        return;
    }
    let sanitizer = Sanitizer::builtin();
    let (mut cleared, mut annotated, mut imported) = (Vec::new(), Vec::new(), 0);
    for entry in &entries {
        match recover_entry(client, env, entry, &sanitizer).await {
            Ok(count) => {
                imported += count;
                cleared.push(entry.id.clone());
            }
            Err(error) => annotated.push((entry.id.clone(), format!("{error:#}"))),
        }
    }
    match finish_journal(&run_dir, &sanitizer, &cleared, &annotated) {
        Ok(left) => eprintln!(
            "ai-memory: recovered {} journaled run(s) ({imported} event(s)){}",
            cleared.len(),
            if left > 0 { format!("; {left} still journaled") } else { String::new() }
        ),
        Err(error) => eprintln!("ai-memory: could not update the recovery journal ({error:#})"),
    }
    for (_, reason) in &annotated {
        eprintln!("ai-memory: recovery skipped: {}", super::terminal_text(reason));
    }
}
