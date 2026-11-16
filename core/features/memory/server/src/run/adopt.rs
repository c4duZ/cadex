//! The launch plan of a prepared run: the linked native session, or a fresh
//! one when it is gone from its store (refused when it was linked under
//! another store), or, for a workstream with none linked, the newest
//! checkout-local session (automatic launch) or the one picked on the
//! terminal.
//!
//! Follows `run_once_with_wiring` of ai-memory v3.4.7 (fa0ec25),
//! crates/ai-memory-cli/src/commands/run.rs (lines ~1130–1330): the orphan,
//! store-mismatch and adoption branches. Changed for Cadex (2026-11-16): no
//! i18n; `prepare.project_id.is_none()` is `--project-id` absent.

use std::io::IsTerminal as _;
use std::time::SystemTime;

use ai_memory_workstream::{
    LaunchMode, LaunchPlan, ManagedHarness, allows_native_session_adoption, has_native_session_selector,
    is_interactive_session_invocation, list_native_sessions,
};
use anyhow::{Context, Result};
use tokio_util::sync::CancellationToken;

use super::launch::Prepared;
use super::local::Local;
use super::picker::{ADOPTION_CANDIDATE_LIMIT, choose_native_session_interactive, orphan_resume_hint};
use super::plan::{build_preflighted_launch_plan, display_session_id, plan_for};
use super::store_record::{StoreRecords, effective_store, store_mismatch_error};

/// The plan, and whether it resumes the session the workstream links.
pub(crate) struct Planned {
    pub(crate) plan: LaunchPlan,
    pub(crate) resumes_linked_session: bool,
    pub(crate) interactive_session: bool,
}

fn orphaned(local: &Local, prep: &Prepared<'_>, harness: ManagedHarness, plan: &LaunchPlan, orphaned_session: &str)
    -> Result<()> {
    let records = StoreRecords { run_dir: &prep.run_dir, server: &prep.env.socket };
    let recorded = records.recorded_session_store(harness.as_str(), orphaned_session).unwrap_or_else(|error| {
        eprintln!("ai-memory: could not read the client-local session store record ({error:#}); treating the linked session as deleted");
        None
    });
    let current = effective_store(harness, &local.home, &local.repository.cwd, plan.session_dir.as_deref());
    if let Some(error) = store_mismatch_error(harness, orphaned_session, recorded, &current) {
        return Err(error);
    }
    eprintln!(
        "ai-memory: linked {} session {} is missing from its native store; starting fresh and repointing workstream '{}' after the new session is established",
        harness.as_str(),
        display_session_id(orphaned_session),
        super::terminal_text(&prep.prepared.workstream_name)
    );
    Ok(())
}

async fn orphan_hint(local: &Local, harness: ManagedHarness, plan: &LaunchPlan, orphaned_session: &str) {
    let sessions = list_native_sessions(harness, &local.home, &local.repository.cwd, plan.session_dir.as_deref(), 1).await;
    if let Some(hint) = orphan_resume_hint(harness, orphaned_session, sessions, SystemTime::now()) {
        eprintln!("{}", super::terminal_text(&hint));
    }
}

fn replan(local: &Local, harness: ManagedHarness, session: &str) -> Result<LaunchPlan> {
    plan_for(harness, local.executable.clone(), local.native_args.clone(), Some(session), &local.home, &local.repository.cwd,
        &local.child_env)
}

/// Picker for a workstream with no linked session, on a terminal.
async fn pick(local: &Local, prep: &Prepared<'_>, harness: ManagedHarness, plan: LaunchPlan, interrupted: &CancellationToken)
    -> Result<LaunchPlan> {
    let listed = list_native_sessions(harness, &local.home, &local.repository.cwd, plan.session_dir.as_deref(),
        ADOPTION_CANDIDATE_LIMIT).await;
    let candidates = match listed {
        Ok(candidates) if !candidates.is_empty() => candidates,
        Ok(_) => return Ok(plan),
        Err(error) => {
            eprintln!("ai-memory: could not inspect prior {} sessions ({error}); starting a new session", harness.as_str());
            return Ok(plan);
        }
    };
    let selection = choose_native_session_interactive(harness, prep.prepared.workstream_name.clone(), candidates, &prep.client,
        &prep.run_path, interrupted).await?;
    match selection {
        Ok(Some(id)) => replan(local, harness, &id),
        Ok(None) => Ok(plan),
        Err(error) => {
            eprintln!("ai-memory: could not read the native session choice ({error}); starting a new {} session", harness.as_str());
            Ok(plan)
        }
    }
}

pub(crate) async fn plan_launch(local: &Local, prep: &Prepared<'_>, harness: ManagedHarness, interrupted: &CancellationToken)
    -> Result<Planned> {
    let linked = prep.prepared.native_session_id.as_deref();
    let (mut plan, orphaned_session) = build_preflighted_launch_plan(harness, local.executable.clone(), local.native_args.clone(),
        linked, local.force_fresh, &local.home, &local.repository.cwd, &local.child_env)?;
    let interactive_session = is_interactive_session_invocation(harness, &local.native_args);
    let resumes_linked_session = !local.force_fresh
        && orphaned_session.is_none()
        && linked.is_some()
        && plan.expected_session_id.as_deref() == linked
        && !has_native_session_selector(harness, &local.native_args);
    if let Some(orphaned_session) = orphaned_session {
        orphaned(local, prep, harness, &plan, &orphaned_session)?;
        if interactive_session && !local.automatic {
            orphan_hint(local, harness, &plan, &orphaned_session).await;
        }
    } else if local.force_fresh && plan.mode == LaunchMode::Session {
        eprintln!("ai-memory: starting a fresh {} session in workstream '{}'", harness.as_str(),
            super::terminal_text(&prep.prepared.workstream_name));
    }
    let may_adopt = prep.prepared.native_session_id.is_none()
        && prep.prepared.may_adopt_existing_session
        && local.may_adopt
        && local.project_id.is_none();
    if local.automatic && may_adopt {
        let candidate = local
            .auto_candidates
            .iter()
            .find(|candidate| candidate.harness == harness)
            .context("the selected automatic harness no longer has a checkout-local session")?;
        plan = replan(local, harness, &candidate.session.native_session_id)?;
        eprintln!("ai-memory: continuing newest checkout-local {} session {}", harness.as_str(),
            display_session_id(&candidate.session.native_session_id));
    } else if may_adopt
        && allows_native_session_adoption(harness, &local.native_args)
        && std::io::stdin().is_terminal()
        && std::io::stderr().is_terminal()
    {
        plan = pick(local, prep, harness, plan, interrupted).await?;
    }
    Ok(Planned { plan, resumes_linked_session, interactive_session })
}
