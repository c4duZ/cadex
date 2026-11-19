//! A prepared run up to the child's exit: the harness the engine settled on
//! (automatic precedence, Kiro's engine), the `--yolo` gate, the plan
//! (adopt.rs), `--yolo` itself, the link, Claude's background attach, the
//! dossier, the Crush/Grok context, then the agent with the terminal and the
//! heartbeat while it runs.
//!
//! Follows `run_once_with_wiring` of ai-memory v3.4.7 (fa0ec25; compared at v3.5.0, 411d90d, on 2026-11-19: its new `--or-new` not brought, `cadex continue` does not use it),
//! crates/ai-memory-cli/src/commands/run.rs (lines ~1000–1640). Changed for
//! Cadex (2026-11-16): no autowire (the kit wires hooks and MCP; `--no-autowire`
//! is ignored); the kit's words for the resolved harness go after the plan
//! (none on a background attach, which connects to a running session); no
//! `AI_MEMORY_HOOK_URL` (the engine has no TCP endpoint), and an inherited
//! one is removed.

use std::ffi::OsString;
use std::path::PathBuf;
use std::process::Stdio;
use std::time::SystemTime;

use ai_memory_core::{FinishManagedRunRequest, LinkManagedRunRequest, NativeSessionIdentity, PrepareManagedRunResponse, Sanitizer};
use ai_memory_workstream::{
    LaunchMode, LaunchPlan, ManagedHarness, RepositoryIdentity, apply_jail_process_isolation, apply_yolo,
    kiro_v3_resume_uses_default_store, kiro_yolo_engine_is_unverified,
};
use anyhow::{Context, Result, anyhow};
use tokio::process::Command;
use tokio_util::sync::CancellationToken;

use super::args::Env;
use super::auto::{automatic_harness_flavor, resolve_kiro_harness};
use super::child_env::{blank_home_overrides, ensure_executable_available, resolve_program};
use super::choice::managed_harness_from_agent;
use super::flow::{Failed, RunOutcome};
use super::history::{prepare_previous_session_history, previous_session_for_history};
use super::jail::{JailOffer, confirm_yolo_and_maybe_reexec};
use super::jail_exec::JailContext;
use super::local::Local;
use super::plan::{append_kit_args, display_session_id};
use super::server::{self, HEARTBEAT_INTERVAL, HeartbeatHealth};
use super::store_record::{StoreRecords, effective_store};
use super::uds_http::Client;

/// The prepared run and where its records go.
pub(crate) struct Prepared<'a> {
    pub(crate) client: Client,
    pub(crate) run_path: String,
    pub(crate) prepared: PrepareManagedRunResponse,
    pub(crate) env: &'a Env,
    pub(crate) run_dir: PathBuf,
}

/// What the stages after the spawn share.
pub(crate) struct Run<'a> {
    pub(crate) prep: Prepared<'a>,
    pub(crate) repository: RepositoryIdentity,
    pub(crate) harness: ManagedHarness,
    pub(crate) home: PathBuf,
    pub(crate) privacy: Sanitizer,
    pub(crate) workspace: String,
    pub(crate) project: String,
    /// The store the linked session lives in (remembered after the finish).
    pub(crate) linked_store: PathBuf,
}

impl Run<'_> {
    pub(crate) fn records(&self) -> StoreRecords<'_> {
        StoreRecords { run_dir: &self.prep.run_dir, server: &self.prep.env.socket }
    }
}

fn not_started(interrupted: &CancellationToken) -> Result<()> {
    if interrupted.is_cancelled() {
        return Err(anyhow!("managed run interrupted before the agent started"));
    }
    Ok(())
}

fn validate_prepared(prepared: &PrepareManagedRunResponse, privacy: &Sanitizer) -> Result<()> {
    if let Some(id) = prepared.native_session_id.as_deref() {
        NativeSessionIdentity::parse(id, privacy)?;
    }
    if let Some(previous) = prepared.previous_native_session.as_ref() {
        NativeSessionIdentity::parse(&previous.native_session_id, privacy)?;
    }
    Ok(())
}

/// The harness the engine settled on, Kiro's engine included.
fn resolve_harness(local: &Local, prepared: &PrepareManagedRunResponse) -> Result<ManagedHarness> {
    let resolved = if local.automatic {
        let agent = prepared.resolved_agent.unwrap_or_else(|| {
            eprintln!("ai-memory: the server does not support managed harness precedence; using the newest checkout-local session. Upgrade the server for established-workstream selection");
            local.provisional.agent_kind()
        });
        let selected = managed_harness_from_agent(agent)
            .ok_or_else(|| anyhow!("the server selected unsupported automatic harness '{}'", agent.as_str()))?;
        automatic_harness_flavor(selected, local.provisional, prepared.native_session_id.as_deref(), local.opencode_harness())
    } else {
        local.provisional
    };
    if resolved.agent_kind() == ai_memory_core::AgentKind::KiroCli {
        return resolve_kiro_harness(&local.native_args, prepared.native_session_id.as_deref(), prepared.source_cursor.as_deref(),
            resolved, &local.home, &local.repository.cwd);
    }
    Ok(resolved)
}

fn yolo(local: &Local, harness: ManagedHarness, plan: &mut LaunchPlan) {
    if !local.yolo {
        return;
    }
    if kiro_yolo_engine_is_unverified(harness, &plan.args) {
        eprintln!("ai-memory: --yolo maps to no verified flag on the selected Kiro engine (only v2 and v3 take --trust-all-tools); launching without it");
    }
    apply_yolo(harness, &mut plan.args);
}

async fn link(run: &Run<'_>, plan: &LaunchPlan) -> Result<()> {
    let planned = plan.expected_session_id.as_deref().map(|id| NativeSessionIdentity::parse(id, &run.privacy)).transpose()?;
    if plan.mode == LaunchMode::Session && let Some(identity) = planned {
        let body = LinkManagedRunRequest { native_session_id: identity.as_str().to_owned() };
        run.prep.client.post_json_no_content(&format!("{}/link", run.prep.run_path), &body).await
            .context("linking the managed native session; the agent was not started")?;
        run.records().remember_session_store(run.harness, identity.as_str(), &run.linked_store);
    }
    Ok(())
}

pub(crate) async fn launch(local: &mut Local, ctx: &JailContext<'_>, client: Client, prepared: PrepareManagedRunResponse,
    interrupted: &CancellationToken) -> Result<RunOutcome, Failed> {
    let run_path = format!("/workstream/runs/{}", prepared.run_id);
    let prep = Prepared { client, run_path, prepared, env: ctx.env, run_dir: ctx.env.run_dir() };
    not_started(interrupted)?;
    let privacy = Sanitizer::builtin();
    validate_prepared(&prep.prepared, &privacy)?;
    let harness = resolve_harness(local, &prep.prepared)?;
    if local.jailed && apply_jail_process_isolation(harness, &mut local.native_args) {
        eprintln!("ai-memory: OpenCode is running --standalone so its server and tool processes stay inside ai-jail");
    }
    if local.automatic {
        local.pin_opencode_executable(harness);
    }
    ensure_executable_available(harness, local.executable.as_deref(), local.child_env.executable_search())?;
    let offer = JailOffer { ai_jail: local.ai_jail.as_deref(), harness };
    confirm_yolo_and_maybe_reexec(ctx, &local.jail_plan, offer, &local.jail_facts, &local.jail_inputs,
        Some((&prep.client, &prep.run_path)), interrupted).await?;
    let native_grok_rules = super::harness_ctx::user_supplied_grok_rules(&local.native_args);
    let planned = super::adopt::plan_launch(local, &prep, harness, interrupted).await?;
    let mut plan = planned.plan;
    yolo(local, harness, &mut plan);
    let remove_kiro_home = match plan.expected_session_id.as_deref() {
        Some(id) if harness == ManagedHarness::KiroV3 => {
            kiro_v3_resume_uses_default_store(&local.home, &local.repository.cwd, plan.session_dir.as_deref(), id)?
        }
        _ => false,
    };
    if remove_kiro_home {
        eprintln!("ai-memory: Kiro v3 stored this session under the default home despite custom KIRO_HOME; using the default home for this resume");
    }
    let store_dir = if remove_kiro_home { None } else { plan.session_dir.as_deref() };
    let run = Run {
        linked_store: effective_store(harness, &local.home, &local.repository.cwd, store_dir),
        prep,
        repository: local.repository.clone(),
        harness,
        home: local.home.clone(),
        privacy,
        workspace: local.workspace.clone(),
        project: local.project.clone(),
    };
    link(&run, &plan).await?;
    let attached = attach(local, &run, &mut plan, planned.resumes_linked_session).await;
    let child = Child { native_grok_rules, remove_kiro_home, attached: attached.is_some(), planned_interactive: planned.interactive_session };
    spawn_and_wait(local, run, plan, child, planned.resumes_linked_session, interrupted).await
}

/// Claude refuses `--resume` on a live background session: attach instead.
async fn attach(local: &Local, run: &Run<'_>, plan: &mut LaunchPlan, resumes_linked_session: bool) -> Option<String> {
    if run.harness != ManagedHarness::Claude || plan.mode != LaunchMode::Session || !resumes_linked_session {
        return None;
    }
    let id = plan.expected_session_id.clone()?;
    let attach_id = super::attach::claude_background_attach_id(plan, &local.home, &local.repository.cwd, &local.child_env, &id).await?;
    eprintln!(
        "ai-memory: Claude session {} is still running in the background; attaching to it (`claude attach {attach_id}`). Native arguments and the workstream context packet do not reach an attached session",
        display_session_id(&id)
    );
    plan.args = vec![OsString::from("attach"), OsString::from(&attach_id)];
    Some(attach_id)
}

pub(crate) struct Child {
    native_grok_rules: bool,
    remove_kiro_home: bool,
    pub(crate) attached: bool,
    pub(crate) planned_interactive: bool,
}

async fn spawn_and_wait(local: &Local, run: Run<'_>, mut plan: LaunchPlan, child: Child, resumes_linked_session: bool,
    interrupted: &CancellationToken) -> Result<RunOutcome, Failed> {
    let prepared = &run.prep.prepared;
    let previous = previous_session_for_history(prepared.previous_native_session.as_ref(), prepared.native_session_id.as_deref(),
        local.force_fresh, plan.mode, run.harness);
    let history = match previous.as_ref() {
        Some(previous) => prepare_previous_session_history(previous, &run.home, &run.repository.cwd, &local.child_env, &run.records())
            .await
            .unwrap_or_else(|error| {
                eprintln!("ai-memory: could not prepare the previous {} session history ({error:#}); continuing with the portable workstream packet",
                    previous.agent.as_str());
                None
            }),
        None => None,
    };
    let contexts = super::harness_ctx::contexts(local, &run, &plan, child.native_grok_rules).await?;
    if let Some(context) = &contexts.grok {
        plan.args.extend([OsString::from("--rules"), OsString::from(context)]);
    }
    if !child.attached {
        append_kit_args(&mut plan, run.harness, &local.claude_kit_args, &local.codex_kit_args);
    }
    not_started(interrupted)?;
    let started_at = SystemTime::now();
    let mut command = Command::new(resolve_program(&plan.program, local.child_env.executable_search()).unwrap_or_else(|| plan.program.clone().into()));
    local.child_env.apply_to_tokio(&mut command);
    command
        .args(&plan.args)
        .current_dir(&run.repository.cwd)
        .env("AI_MEMORY_RUN_ID", prepared.run_id.to_string())
        .env("AI_MEMORY_WORKSTREAM_ID", prepared.workstream_id.to_string())
        .env_remove("AI_MEMORY_PREVIOUS_SESSION_HISTORY")
        .env_remove("AI_MEMORY_HOOK_URL")
        .stdin(Stdio::inherit())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit());
    if let Some(history) = &history {
        command.env("AI_MEMORY_PREVIOUS_SESSION_HISTORY", history.path());
    }
    for name in blank_home_overrides(run.harness, &|name| local.child_env.lookup(name)) {
        command.env_remove(name);
    }
    if child.remove_kiro_home {
        command.env_remove("KIRO_HOME");
    }
    if let Some(context) = &contexts.crush {
        command.env("CRUSH_GLOBAL_CONFIG", context.path());
    }
    let mut spawned = match command.spawn() {
        Ok(spawned) => spawned,
        Err(error) => return Err(spawn_failed(&run, &plan, error).await),
    };
    let mut health = HeartbeatHealth::default();
    if run.harness == ManagedHarness::Crush || contexts.grok.is_some() {
        let accept = format!("{}/context/accept", run.prep.run_path);
        if let Err(error) = server::post_empty_with_retry(&run.prep.client, &accept, "acknowledging managed context").await {
            health.notify(format!("ai-memory: {error}; the context may be delivered again on the next {} run", run.harness.as_str()));
        }
    }
    let mut heartbeat = tokio::time::interval(HEARTBEAT_INTERVAL);
    heartbeat.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
    heartbeat.tick().await;
    let waited = loop {
        tokio::select! {
            result = spawned.wait() => break result,
            _ = heartbeat.tick() => server::send_heartbeat(&run.prep.client, &run.prep.run_path, &mut health).await,
        }
    };
    for notice in health.into_deferred() {
        eprintln!("{}", super::terminal_text(&notice));
    }
    let exit_code = waited.context("waiting for managed harness")?.code().unwrap_or(1);
    let outcome = super::after::after_exit(&run, &plan, started_at, exit_code, resumes_linked_session, child.attached).await;
    drop(history);
    drop(contexts);
    outcome.map(|exit_code| RunOutcome {
        exit_code,
        harness: run.harness,
        interactive_session: child.planned_interactive,
        mode: plan.mode,
        workstream_name: run.prep.prepared.workstream_name.clone(),
        degraded: false,
    })
}

/// The agent never started: close the run with that loss (cancel only if
/// even that fails).
async fn spawn_failed(run: &Run<'_>, plan: &LaunchPlan, spawn_error: std::io::Error) -> Failed {
    let message = spawn_error.to_string();
    let request = FinishManagedRunRequest {
        native_session_id: plan.expected_session_id.clone(),
        source_cursor: run.prep.prepared.source_cursor.clone(),
        events: Vec::new(),
        complete: true,
        checkpoint: run.repository.checkpoint.clone(),
        losses: vec![format!("native process could not be started: {message}")],
        exit_code: None,
    };
    let finished = server::finish_with_retry(&run.prep.client, &run.prep.run_path, &request).await.is_ok();
    Failed {
        error: anyhow!(message).context(format!("starting managed {} executable {}", run.harness.as_str(), plan.program.to_string_lossy())),
        cancel: !finished,
    }
}
