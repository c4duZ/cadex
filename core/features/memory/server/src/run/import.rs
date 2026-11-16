//! After the agent exits: its transcript, read once the writer settled, sent
//! to the run's `/finish` in batches as the workstream's ledger.
//!
//! Copied from ai-memory v3.4.7 (fa0ec25), crates/ai-memory-cli/src/commands/
//! run.rs: `export_after_flush`, `import_batches`,
//! `import_incomplete_batches`, `event_batches`, `nonempty_session` and the
//! batch limits. Changed for Cadex (2026-11-16): the client is uds_http.rs,
//! no i18n, and ledger_capture.rs for the checkout's policy.

use std::path::Path;

use ai_memory_core::{FinishManagedRunRequest, NativeSessionIdentity, NewWorkstreamEvent, Sanitizer, WorkstreamCheckpoint};
use ai_memory_workstream::{ExportedTranscript, ManagedHarness, export_transcript, wait_for_transcript_flush};
use anyhow::Result;

use super::ledger_capture::LedgerCapture;
use super::server::finish_with_retry;
use super::uds_http::Client;

const IMPORT_BATCH_EVENTS: usize = 400;
const IMPORT_BATCH_BYTES: usize = 1024 * 1024;

/// The transcript of `native_session_id` after its writer settled; a
/// failure becomes a recorded loss, never an error.
pub(crate) async fn export_after_flush(harness: ManagedHarness, home: &Path, cwd: &Path, session_dir: Option<&Path>,
    native_session_id: Option<&str>, source_cursor: Option<&str>) -> ExportedTranscript {
    let Some(native_session_id) = native_session_id else {
        return ExportedTranscript {
            losses: vec!["native session id could not be discovered; transcript was not imported".into()],
            ..ExportedTranscript::default()
        };
    };
    if let Err(error) = wait_for_transcript_flush(harness, home, cwd, session_dir, native_session_id).await {
        eprintln!("ai-memory: transcript flush check failed: {error}");
    }
    match export_transcript(harness, home, cwd, session_dir, native_session_id, source_cursor).await {
        Ok(export) => export,
        Err(error) => ExportedTranscript {
            native_session_id: native_session_id.to_owned(),
            source_cursor: source_cursor.map(str::to_owned),
            losses: vec![format!("native transcript import failed: {error}")],
            events: Vec::new(),
        },
    }
}

fn event_batches(events: Vec<NewWorkstreamEvent>) -> Vec<Vec<NewWorkstreamEvent>> {
    let mut batches = Vec::new();
    let mut batch = Vec::new();
    let mut bytes = 0_usize;
    for event in events {
        let event_bytes = serde_json::to_vec(&event).map_or(IMPORT_BATCH_BYTES, |raw| raw.len());
        if !batch.is_empty() && (batch.len() >= IMPORT_BATCH_EVENTS || bytes.saturating_add(event_bytes) > IMPORT_BATCH_BYTES) {
            batches.push(std::mem::take(&mut batch));
            bytes = 0;
        }
        bytes = bytes.saturating_add(event_bytes);
        batch.push(event);
    }
    batches.push(batch);
    batches
}

fn validate(transcript: &ExportedTranscript, sanitizer: &Sanitizer) -> Result<()> {
    for event in &transcript.events {
        NativeSessionIdentity::parse(&event.native_session_id, sanitizer)?;
    }
    Ok(())
}

/// The run's own transcript as the final batches; the last one completes
/// the run (cursor, losses, exit code). The count of new events.
pub(crate) async fn import_batches(client: &Client, run_path: &str, transcript: ExportedTranscript,
    checkpoint: WorkstreamCheckpoint, exit_code: Option<i32>, sanitizer: &Sanitizer, capture: &LedgerCapture) -> Result<usize> {
    let native_identity = Some(transcript.native_session_id.as_str())
        .filter(|id| !id.is_empty())
        .map(|id| NativeSessionIdentity::parse(id, sanitizer))
        .transpose()?;
    validate(&transcript, sanitizer)?;
    let events = capture.filter_ledger_events(transcript.events);
    let mut imported = 0;
    let mut batches = event_batches(events).into_iter().peekable();
    while let Some(batch) = batches.next() {
        let complete = batches.peek().is_none();
        let request = FinishManagedRunRequest {
            native_session_id: native_identity.as_ref().map(|id| id.as_str().to_owned()),
            source_cursor: complete.then(|| transcript.source_cursor.clone()).flatten(),
            events: batch,
            complete,
            checkpoint: checkpoint.clone(),
            losses: if complete { transcript.losses.clone() } else { Vec::new() },
            exit_code: complete.then_some(exit_code).flatten(),
        };
        imported += finish_with_retry(client, run_path, &request).await?.imported_events;
    }
    Ok(imported)
}

/// A session left behind by a Claude continuation, as non-final batches.
pub(crate) async fn import_incomplete_batches(client: &Client, run_path: &str, transcript: ExportedTranscript,
    checkpoint: WorkstreamCheckpoint, sanitizer: &Sanitizer, capture: &LedgerCapture) -> Result<usize> {
    let native_identity = NativeSessionIdentity::parse(&transcript.native_session_id, sanitizer)?;
    validate(&transcript, sanitizer)?;
    let events = capture.filter_ledger_events(transcript.events);
    if events.is_empty() {
        return Ok(0);
    }
    let mut imported = 0;
    for batch in event_batches(events) {
        let request = FinishManagedRunRequest {
            native_session_id: Some(native_identity.as_str().to_owned()),
            source_cursor: None,
            events: batch,
            complete: false,
            checkpoint: checkpoint.clone(),
            losses: Vec::new(),
            exit_code: None,
        };
        imported += finish_with_retry(client, run_path, &request).await?.imported_events;
    }
    Ok(imported)
}
