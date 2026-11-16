//! The degraded launch: the engine could not be reached or started, so the
//! agent runs anyway, with a loud warning, no lease and no context; its
//! hooks queue events in the spool, and the session is journaled so the next
//! run with the engine up replays it (recover.rs). `--require-server` (or
//! `run.require_server`, or `--project-id`) fails closed instead (flow.rs).
//!
//! Copied from ai-memory v3.4.7 (fa0ec25), crates/ai-memory-cli/src/commands/
//! run.rs: `run_degraded_offline`, `degraded_launch`, `journal_degraded_run`,
//! `DEGRADED_SESSION_SNAPSHOT_LIMIT`, `snapshot_native_sessions`,
//! `resolve_degraded_session`, `unique_new_session`, `export_exact_after_run`,
//! `spooled_events_note`, `offline_launch_warning`, and `status::spool_age_line`.
//! Changed for Cadex (2026-11-16): the warning names memory.sock, not a URL,
//! and Cadex's spool (`<data-dir>/spool`, drained by the engine when it
//! starts, with no attempt cap); the kit's words still go to the agent; the
//! messages name the next `cadex-memory run` instead of `ai-memory recover`
//! and `ai-memory backfill`.

use std::collections::HashSet;
use std::path::Path;
use std::process::Stdio;
use std::time::{Duration, SystemTime};

use ai_memory_core::{NativeSessionIdentity, Sanitizer};
use ai_memory_workstream::{
    ExportedTranscript, LaunchMode, LaunchPlan, ManagedHarness, NativeSessionCandidate, TranscriptCapability, apply_yolo,
    export_transcript, is_interactive_session_invocation, kiro_yolo_engine_is_unverified, list_native_sessions,
    native_session_exists, transcript_baseline, transcript_interval_digests, wait_for_transcript_flush,
};
use anyhow::{Context, Result, anyhow};
use tokio::process::Command;
use tokio_util::sync::CancellationToken;

use super::flow::{RunOutcome, capture_interrupts};
use super::jail::{JailOffer, confirm_yolo_and_maybe_reexec};
use super::jail_exec::JailContext;
use super::journal::{JournalKind, JournalScope, append_journal_entry, new_entry};
use super::local::Local;
use super::plan::{append_kit_args, build_preflighted_launch_plan, display_session_id};

const DEGRADED_SESSION_SNAPSHOT_LIMIT: usize = 2_000;

fn spool_age_line(age_ms: Option<u64>) -> String {
    let Some(ms) = age_ms else { return "-".to_string() };
    let secs = ms / 1000;
    if secs < 60 {
        format!("{secs}s")
    } else if secs < 3600 {
        format!("{}m {}s", secs / 60, secs % 60)
    } else if secs < 86_400 {
        format!("{}h {}m", secs / 3600, (secs % 3600) / 60)
    } else {
        format!("{}d {}h", secs / 86_400, (secs % 86_400) / 3600)
    }
}

/// What remains queued in Cadex's spool (`<ms>-<hex>.json` files).
fn spooled_events_note(spool_dir: &Path) -> String {
    let names: Vec<String> = std::fs::read_dir(spool_dir)
        .map(|dir| dir.flatten().filter_map(|e| e.file_name().into_string().ok()).filter(|n| n.ends_with(".json")).collect())
        .unwrap_or_default();
    let oldest = names.iter().filter_map(|n| n.get(..13)?.parse::<u64>().ok()).min();
    let now = super::journal::system_time_ms(SystemTime::now());
    let age = spool_age_line(oldest.map(|ms| now.saturating_sub(ms)));
    match names.len() {
        0 => "no hook events remain spooled locally".to_string(),
        1 => format!("1 hook event remains spooled locally (oldest {age})"),
        pending => format!("{pending} hook events remain spooled locally (oldest {age})"),
    }
}

fn offline_launch_warning(socket: &Path, harness: ManagedHarness, error: &anyhow::Error) -> String {
    format!(
        "ai-memory: WARNING: the memory engine at {} is unreachable — launching {} \
         WITHOUT server support.\n  {error:#}\n  Lost this run: no workstream lease or \
         cross-harness context, no immediate transcript import, no handoff delivery.\n  Still \
         works: lifecycle hooks spool events locally, and the native transcript is journaled \
         after session discovery. The next `cadex-memory run` with the engine up replays the \
         exact transcript, and the engine drains the spool when it starts.\n  Pass \
         --require-server to fail instead of degrading.",
        socket.display(),
        harness.as_str(),
    )
}

pub(crate) async fn run_degraded_offline(local: &Local, ctx: &JailContext<'_>, error: anyhow::Error) -> Result<RunOutcome> {
    eprintln!("{}", offline_launch_warning(&ctx.env.socket, local.provisional, &error));
    let interrupted = CancellationToken::new();
    let interrupt_task = tokio::spawn(capture_interrupts(interrupted.clone()));
    let outcome = degraded_launch(local, ctx, &interrupted).await;
    interrupt_task.abort();
    outcome
}

async fn degraded_launch(local: &Local, ctx: &JailContext<'_>, interrupted: &CancellationToken) -> Result<RunOutcome> {
    let (harness, home, cwd) = (local.provisional, &local.home, &local.repository.cwd);
    // No lease: never adopt or resume implicitly; only an explicit selector.
    let (mut plan, _) = build_preflighted_launch_plan(harness, local.executable.clone(), local.native_args.clone(), None,
        local.force_fresh, home, cwd, &local.child_env)?;
    let offer = JailOffer { ai_jail: local.ai_jail.as_deref(), harness };
    confirm_yolo_and_maybe_reexec(ctx, &local.jail_plan, offer, &local.jail_facts, &local.jail_inputs, None, interrupted).await?;
    if local.yolo {
        if kiro_yolo_engine_is_unverified(harness, &plan.args) {
            eprintln!("ai-memory: --yolo maps to no verified flag on the selected Kiro engine (only v2 and v3 take --trust-all-tools); launching without it");
        }
        apply_yolo(harness, &mut plan.args);
    }
    append_kit_args(&mut plan, harness, &local.claude_kit_args, &local.codex_kit_args);
    let program = super::child_env::resolve_program(&plan.program, local.child_env.executable_search())
        .unwrap_or_else(|| plan.program.clone().into());
    let mut command = Command::new(&program);
    local.child_env.apply_to_tokio(&mut command);
    command
        .args(&plan.args)
        .current_dir(cwd)
        .env_remove("AI_MEMORY_RUN_ID")
        .env_remove("AI_MEMORY_WORKSTREAM_ID")
        .env_remove("AI_MEMORY_HOOK_URL")
        .env_remove("AI_MEMORY_PREVIOUS_SESSION_HISTORY")
        .stdin(Stdio::inherit())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit());
    for name in super::child_env::blank_home_overrides(harness, &|name| local.child_env.lookup(name)) {
        command.env_remove(name);
    }
    let before = snapshot_native_sessions(harness, home, cwd, plan.session_dir.as_deref()).await;
    let prelaunch_cursor = match plan.expected_session_id.as_deref() {
        Some(session) if harness.transcript_capability() == TranscriptCapability::Export => {
            match native_session_exists(harness, home, cwd, plan.session_dir.as_deref(), session) {
                Ok(true) => Some(transcript_baseline(harness, home, cwd, plan.session_dir.as_deref(), session).await),
                Ok(false) => None,
                Err(error) => Some(Err(error)),
            }
        }
        _ => None,
    };
    let started_at = SystemTime::now();
    let mut child = command.spawn().map_err(|spawn_error| {
        anyhow!(spawn_error.to_string()).context(format!("starting managed {} executable {}", harness.as_str(), plan.program.to_string_lossy()))
    })?;
    let exit_code = child.wait().await.context("waiting for managed harness")?.code().unwrap_or(1);
    eprintln!("ai-memory: this run was not recorded on the server; {}", spooled_events_note(&ctx.env.data_dir.join("spool")));
    let scope = JournalScope { run_dir: &ctx.env.run_dir(), server: &ctx.env.socket, cwd, workspace: &local.workspace,
        project: &local.project };
    journal_degraded_run(local, &scope, &plan, exit_code, started_at, before, prelaunch_cursor).await;
    Ok(RunOutcome {
        exit_code,
        harness,
        interactive_session: is_interactive_session_invocation(harness, &local.native_args),
        mode: plan.mode,
        workstream_name: "(offline)".to_string(),
        degraded: true,
    })
}

/// The exact interval this run added to its session, for the journal.
async fn exact_interval(harness: ManagedHarness, local: &Local, plan: &LaunchPlan, session: &str, cursor: Option<&str>)
    -> Result<ExportedTranscript> {
    let (home, cwd, dir) = (&local.home, &local.repository.cwd, plan.session_dir.as_deref());
    wait_for_transcript_flush(harness, home, cwd, dir, session).await?;
    export_transcript(harness, home, cwd, dir, session, cursor).await
}

async fn journal_degraded_run(local: &Local, scope: &JournalScope<'_>, plan: &LaunchPlan, exit_code: i32, started_at: SystemTime,
    before: Option<HashSet<String>>, prelaunch_cursor: Option<Result<String>>) {
    if plan.mode != LaunchMode::Session {
        return;
    }
    let harness = local.provisional;
    let resolved = resolve_degraded_session(plan, harness, local, started_at, before.as_ref(), &Sanitizer::builtin()).await;
    let session = match resolved {
        Ok(Some(session)) => session,
        Ok(None) => {
            eprintln!("ai-memory: no native session was discovered, so this run could not be journaled; retain the harness transcript for manual backfill");
            return;
        }
        Err(error) => {
            eprintln!("ai-memory: could not uniquely identify the session this run used ({error:#}); nothing was journaled; preserve the local transcript");
            return;
        }
    };
    let source_cursor = match prelaunch_cursor {
        Some(Ok(cursor)) => Some(cursor),
        Some(Err(error)) => {
            eprintln!("ai-memory: could not record a safe delta baseline for resumed session {} ({error:#}); nothing was journaled; retain the native transcript for manual repair", display_session_id(&session));
            return;
        }
        None => None,
    };
    let mut entry = new_entry(scope, JournalKind::DegradedRun, harness, plan, started_at, exit_code);
    if !entry.spool_only {
        let export = match exact_interval(harness, local, plan, &session, source_cursor.as_deref()).await {
            Ok(export) => export,
            Err(error) => {
                eprintln!("ai-memory: could not capture an exact post-run transcript bound for session {} ({error:#}); nothing was journaled; retain the native transcript for manual repair", display_session_id(&session));
                return;
            }
        };
        let Some(final_cursor) = export.source_cursor.clone() else {
            eprintln!("ai-memory: the {} transcript adapter produced no post-run cursor; nothing was journaled; retain the native transcript for manual repair", harness.as_str());
            return;
        };
        entry.event_digests = Some(transcript_interval_digests(&export.events));
        entry.final_cursor = Some(final_cursor);
    }
    entry.native_session_id = Some(session);
    entry.source_cursor = source_cursor;
    match append_journal_entry(scope.run_dir, entry) {
        Ok(()) => eprintln!("ai-memory: recorded for recovery — the next `cadex-memory run` with the memory engine up replays this session's exact native transcript"),
        Err(error) => eprintln!("ai-memory: could not record this run for recovery ({error:#}); the native transcript remains in the harness store"),
    }
}

async fn snapshot_native_sessions(harness: ManagedHarness, home: &Path, cwd: &Path, session_dir: Option<&Path>) -> Option<HashSet<String>> {
    let sessions = list_native_sessions(harness, home, cwd, session_dir, DEGRADED_SESSION_SNAPSHOT_LIMIT + 1).await.ok()?;
    if sessions.len() > DEGRADED_SESSION_SNAPSHOT_LIMIT {
        return None;
    }
    Some(sessions.into_iter().map(|session| session.native_session_id).collect())
}

async fn resolve_degraded_session(plan: &LaunchPlan, harness: ManagedHarness, local: &Local, started_at: SystemTime,
    before: Option<&HashSet<String>>, sanitizer: &Sanitizer) -> Result<Option<String>> {
    if let Some(expected) = plan.expected_session_id.as_deref() {
        return Ok(Some(NativeSessionIdentity::parse(expected, sanitizer)?.into_string()));
    }
    let before = before.ok_or_else(|| anyhow!("pre-launch native-session snapshot was unavailable"))?;
    let after = list_native_sessions(harness, &local.home, &local.repository.cwd, plan.session_dir.as_deref(),
        DEGRADED_SESSION_SNAPSHOT_LIMIT + 1).await?;
    if after.len() > DEGRADED_SESSION_SNAPSHOT_LIMIT {
        return Err(anyhow!("post-launch native-session snapshot exceeded its {DEGRADED_SESSION_SNAPSHOT_LIMIT}-record limit"));
    }
    let id = unique_new_session(after, before, started_at)?;
    Ok(Some(NativeSessionIdentity::parse(&id, sanitizer)?.into_string()))
}

fn unique_new_session(after: Vec<NativeSessionCandidate>, before: &HashSet<String>, started_at: SystemTime) -> Result<String> {
    let mut new = after
        .into_iter()
        .filter(|c| c.updated_at + Duration::from_secs(2) >= started_at && !before.contains(&c.native_session_id))
        .collect::<Vec<_>>();
    if new.len() != 1 {
        return Err(anyhow!("expected one new native session after launch, found {}", new.len()));
    }
    Ok(new.remove(0).native_session_id)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_degraded_session_is_the_one_new_session_and_the_spool_is_counted() {
        let now = SystemTime::now();
        let candidate = |id: &str| NativeSessionCandidate { native_session_id: id.into(), updated_at: now };
        let before: HashSet<String> = ["old".to_owned()].into();
        assert_eq!(unique_new_session(vec![candidate("old"), candidate("new")], &before, now).unwrap(), "new");
        assert!(unique_new_session(vec![candidate("a"), candidate("b")], &before, now).is_err());
        let tmp = tempfile::tempdir().unwrap();
        assert_eq!(spooled_events_note(tmp.path()), "no hook events remain spooled locally");
        std::fs::write(tmp.path().join("0000000000000-ab.json"), "{}").unwrap();
        assert!(spooled_events_note(tmp.path()).starts_with("1 hook event remains spooled locally (oldest "));
        assert_eq!(spool_age_line(Some(3_661_000)), "1h 1m");
    }
}
