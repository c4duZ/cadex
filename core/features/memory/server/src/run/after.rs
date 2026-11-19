//! The managed run after the child exits: which native session it was
//! (following a Claude `/clear` or background continuation), the sessions
//! that continuation left behind, the transcript import and the finish; an
//! engine gone meanwhile journals the run for the next launch.
//!
//! Follows the tail of `run_once_with_wiring` in ai-memory v3.4.7 (fa0ec25; compared at v3.5.0, 411d90d, on 2026-11-19: unchanged),
//! crates/ai-memory-cli/src/commands/run.rs (lines ~1640–1960), with its
//! stderr lines, and `offline_import_warning` and `missing_context_warning`
//! copied. Changed for Cadex (2026-11-16): the journal is Cadex's
//! (journal.rs) and the warnings name the next `cadex-memory run` instead of
//! `ai-memory recover`.

use std::time::SystemTime;

use ai_memory_core::{ManagedRunStatus, SessionId};
use ai_memory_workstream::{
    ExportedTranscript, LaunchMode, LaunchPlan, ManagedHarness, TranscriptCapability, inspect_repository, transcript_interval_digests,
};

use super::flow::Failed;
use super::import::{export_after_flush, import_batches, import_incomplete_batches};
use super::journal::{FinishFailed, JournalScope, journal_finish_failed_run};
use super::launch::Run;
use super::ledger_capture::LedgerCapture;
use super::plan::{claude_left_behind_session_ids, display_session_id, own_native_session, resolve_native_session_after_run};
use super::uds_http::is_unreachable_error;

pub(crate) fn missing_context_warning(harness: ManagedHarness, resumes_linked_session: bool) -> &'static str {
    if harness == ManagedHarness::Codex && resumes_linked_session {
        "ai-memory: Codex did not acknowledge the managed context in the linked thread; if you used `/new`, that new thread was not adopted because Codex exposes no trustworthy parent link. Resume the intended thread explicitly on the next managed run; otherwise refresh the ai-memory hooks"
    } else {
        "ai-memory: this harness did not acknowledge its managed context packet; refresh its ai-memory hooks before the next run"
    }
}

fn offline_import_warning(harness: ManagedHarness, native_session_id: Option<&str>, workspace: &str, project: &str,
    error: &anyhow::Error) -> String {
    let session = native_session_id.map(SessionId::from_native).map_or_else(|| "unknown".to_string(), |s| s.to_string());
    format!(
        "ai-memory: warning: {error:#}; the transcript for {} session {session} in {}/{} was \
         not imported and the orphaned lease will expire automatically within 90 seconds. The \
         harness exit code is preserved. The next `cadex-memory run` with the memory engine up recovers it.",
        harness.as_str(),
        workspace,
        project,
    )
}

/// Transcripts of the Claude sessions a continuation left behind.
async fn left_behind(run: &Run<'_>, plan: &LaunchPlan, own: Option<&str>, followed: Option<&str>, started_at: SystemTime)
    -> (Vec<String>, Vec<ExportedTranscript>, Vec<String>) {
    let (Some(own), Some(followed)) = (own, followed) else { return Default::default() };
    let cwd = &run.repository.cwd;
    let ids = claude_left_behind_session_ids(run.harness, &run.home, cwd, plan.session_dir.as_deref(), own, followed, started_at)
        .unwrap_or_else(|error| {
            eprintln!(
                "ai-memory: could not enumerate Claude sessions left behind by continuation ({error:#}); only the followed session will be imported"
            );
            Vec::new()
        });
    let (mut transcripts, mut losses) = (Vec::new(), Vec::new());
    for id in &ids {
        let prepared = &run.prep.prepared;
        let cursor = (prepared.native_session_id.as_deref() == Some(id.as_str())).then_some(prepared.source_cursor.as_deref()).flatten();
        let mut exported = export_after_flush(run.harness, &run.home, cwd, plan.session_dir.as_deref(), Some(id), cursor).await;
        losses.extend(exported.losses.drain(..).map(|loss| {
            format!("Claude session {} was left behind before continuation: {loss}", display_session_id(id))
        }));
        if !exported.events.is_empty() {
            transcripts.push(exported);
        }
    }
    (ids, transcripts, losses)
}

/// The run's own session, or the hookless-finalize hint when it cannot be tied.
fn own_session(run: &Run<'_>, plan: &LaunchPlan, status: Option<&ManagedRunStatus>) -> Option<String> {
    match own_native_session(plan, run.harness, &run.home, &run.repository.cwd, status, &run.privacy) {
        Ok(own) => own,
        Err(error) => {
            if run.harness.lacks_session_end_hook() && let Some(linked) = status.and_then(|s| s.native_session_id.as_deref()) {
                eprintln!(
                    "ai-memory: not finalizing the {} session: could not tie it to this run ({error:#}); session {} stays open",
                    run.harness.as_str(),
                    SessionId::from_native(linked)
                );
            }
            None
        }
    }
}

/// Import, finish and report; the child's exit code.
pub(crate) async fn after_exit(run: &Run<'_>, plan: &LaunchPlan, started_at: SystemTime, exit_code: i32,
    resumes_linked_session: bool, attached_background: bool) -> Result<i32, Failed> {
    let (harness, cwd, prepared) = (run.harness, &run.repository.cwd, &run.prep.prepared);
    let (client, run_path) = (&run.prep.client, run.prep.run_path.as_str());
    let status = if plan.mode == LaunchMode::Session { client.get_json::<ManagedRunStatus>(run_path).await.ok() } else { None };
    let own = own_session(run, plan, status.as_ref());
    let native_session_id =
        resolve_native_session_after_run(plan, harness, &run.home, cwd, started_at, status.as_ref(), &run.privacy).await?;
    let recovery_start_cursor =
        if native_session_id.as_deref() == prepared.native_session_id.as_deref() { prepared.source_cursor.clone() } else { None };
    let (left_ids, left_transcripts, left_losses) = left_behind(run, plan, own.as_deref(), native_session_id.as_deref(), started_at).await;
    let (mut transcript, exact) = if plan.mode == LaunchMode::Session && harness.transcript_capability() == TranscriptCapability::Export {
        let exported = export_after_flush(harness, &run.home, cwd, plan.session_dir.as_deref(), native_session_id.as_deref(),
            recovery_start_cursor.as_deref()).await;
        let exact = exported.losses.iter().all(|loss| {
            !loss.starts_with("native session id could not be discovered") && !loss.starts_with("native transcript import failed")
        }) && exported.source_cursor.is_some();
        (exported, exact)
    } else {
        (ExportedTranscript { native_session_id: native_session_id.clone().unwrap_or_default(), ..ExportedTranscript::default() }, false)
    };
    transcript.losses.extend(left_losses);
    let digests = exact.then(|| transcript_interval_digests(&transcript.events));
    let final_cursor = exact.then(|| transcript.source_cursor.clone()).flatten();
    let checkpoint = inspect_repository(cwd).map(|identity| identity.checkpoint).unwrap_or_else(|_| run.repository.checkpoint.clone());
    let capture = LedgerCapture::for_checkout(cwd);
    let imported = async {
        let mut imported = 0;
        for abandoned in left_transcripts {
            imported += import_incomplete_batches(client, run_path, abandoned, checkpoint.clone(), &run.privacy, &capture).await?;
        }
        let last = import_batches(client, run_path, transcript, checkpoint, Some(exit_code), &run.privacy, &capture);
        Ok::<usize, anyhow::Error>(imported + last.await?)
    }
    .await;
    let imported = match imported {
        Ok(imported) => imported,
        Err(error) if is_unreachable_error(&error) => {
            eprintln!("{}", offline_import_warning(harness, native_session_id.as_deref(), &run.workspace, &run.project, &error));
            if !left_ids.is_empty() {
                eprintln!(
                    "ai-memory: offline recovery records only the followed session; verify the left-behind Claude session(s) {} after the server returns",
                    left_ids.iter().map(|id| display_session_id(id)).collect::<Vec<_>>().join(", ")
                );
            }
            let scope = JournalScope { run_dir: &run.prep.run_dir, server: &run.prep.env.socket, cwd, workspace: &run.workspace,
                project: &run.project };
            let failed = FinishFailed { native_session_id: native_session_id.as_deref(), run_id: prepared.run_id,
                event_digests: digests.as_deref(), source_cursor: recovery_start_cursor.as_deref(), final_cursor: final_cursor.as_deref() };
            journal_finish_failed_run(&scope, harness, plan, started_at, exit_code, failed, &run.privacy);
            return Ok(exit_code);
        }
        Err(error) => return Err(error.into()),
    };
    if plan.mode == LaunchMode::Session
        && let Some(id) = native_session_id.as_deref()
        && plan.expected_session_id.as_deref() != Some(id)
    {
        run.records().remember_session_store(harness, id, &run.linked_store);
    }
    if plan.mode == LaunchMode::Session
        && prepared.sync_through > prepared.sync_after
        && !status.is_some_and(|s| s.context_delivered)
        && !attached_background
    {
        eprintln!("{}", missing_context_warning(harness, resumes_linked_session));
    }
    eprintln!("ai-memory: workstream '{}' saved {imported} new event(s)", super::terminal_text(&prepared.workstream_name));
    super::hookless::report(run, own.as_deref()).await;
    Ok(exit_code)
}
