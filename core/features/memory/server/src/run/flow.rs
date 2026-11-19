//! One managed run: resolve the launch on this machine, re-run it inside
//! ai-jail when asked, reach the engine (or launch degraded without it),
//! replay what an earlier outage left in the journal, prepare the run and
//! hand it to launch.rs.
//!
//! Follows `run_once_with_wiring` of ai-memory v3.4.7 (fa0ec25; compared at v3.5.0, 411d90d, on 2026-11-19: the jail launch now names the harness, jail_exec.rs),
//! crates/ai-memory-cli/src/commands/run.rs (lines ~613–1000), with
//! `capture_interrupts` and `RunOutcome` copied. Changed for Cadex
//! (2026-11-16): the engine is started here when it does not answer
//! (server.rs; never from inside ai-jail), and the journal is replayed at the
//! start of the next run with the engine up (upstream leaves it to a manual
//! `ai-memory recover`). Not ported, see mod.rs: autowire, the project
//! registry binding and split repair.

use ai_memory_core::PrepareManagedRunRequest;
use ai_memory_workstream::{LaunchMode, ManagedHarness, ai_jail_support, apply_jail_process_isolation, jail_checklist, parse_jail_toggles};
use anyhow::{Context, Result, anyhow};
use tokio_util::sync::CancellationToken;

use super::args::{Env, RunArgs};
use super::auto::unique_auto_agents;
use super::jail::{JailMode, folders_need_a_jail};
use super::jail_exec::{JailContext, JailLaunch, exec_under_ai_jail, jail_contract_for};
use super::local::{Local, resolve};
use super::profiles::Settings;
use super::server;
use super::uds_http::Client;
use super::yolo::{Paint, read_yolo_confirmation};

/// What one launch ended with, for the post-run menu.
#[derive(Debug)]
pub(crate) struct RunOutcome {
    pub(crate) exit_code: i32,
    pub(crate) harness: ManagedHarness,
    pub(crate) interactive_session: bool,
    pub(crate) mode: LaunchMode,
    pub(crate) workstream_name: String,
    /// Made without the engine: no workstream, so no post-run menu.
    pub(crate) degraded: bool,
}

/// A failure, and whether the prepared run must still be cancelled.
pub(crate) struct Failed {
    pub(crate) error: anyhow::Error,
    pub(crate) cancel: bool,
}

impl From<anyhow::Error> for Failed {
    fn from(error: anyhow::Error) -> Self {
        Self { error, cancel: true }
    }
}

pub(crate) async fn capture_interrupts(interrupted: CancellationToken) {
    while tokio::signal::ctrl_c().await.is_ok() {
        interrupted.cancel();
    }
}

/// An explicit `--jail`: re-run inside ai-jail before any run is prepared.
async fn exec_explicit_jail(local: &Local, ctx: &JailContext<'_>, spec: &str) -> Result<anyhow::Error> {
    let ai_jail = local.ai_jail.as_deref().context("ai-jail was not resolved")?;
    let support = ai_jail_support(ai_jail).with_context(|| format!("reading the toggles {} supports", ai_jail.display()))?;
    let contract = jail_contract_for(ai_jail, &support, local.requested.is_some().then_some(local.provisional));
    let checklist = if contract.is_some() { Vec::new() } else { jail_checklist(&local.jail_facts, &support) };
    let toggles = parse_jail_toggles(spec, &checklist, &support)?;
    if local.jail_plan.warn {
        let paint = Paint::for_stderr();
        let confirmation = tokio::task::spawn_blocking(move || {
            read_yolo_confirmation(paint, false, &mut std::io::stdin().lock(), &mut std::io::stderr())
        })
        .await
        .context("waiting for the --yolo confirmation")?
        .context("reading the --yolo confirmation from stdin")?;
        if !confirmation.proceed {
            return Err(anyhow!("aborted: --yolo not confirmed"));
        }
    }
    // The jailed launcher cannot start the engine (it must not write the
    // memory folder from inside the jail), so it is started out here.
    let client = Client::new(&ctx.env.socket, &ctx.env.token);
    if let Err(error) = server::ensure_engine(&client, ctx.env).await {
        eprintln!("ai-memory: {error:#}; the jailed run will launch without the memory engine");
    }
    Ok(exec_under_ai_jail(ai_jail, ctx, JailLaunch {
        support: &support,
        contract: contract.as_ref(),
        harness: local.requested.is_some().then_some(local.provisional),
    }, &toggles,
        local.jail_facts.project_config, &local.jail_inputs.flag_folders, None))
}

/// Reach the engine: started here if needed, only probed inside ai-jail.
async fn reach_engine(client: &Client, env: &Env, jailed: bool) -> Result<()> {
    if jailed {
        return if client.healthy().await {
            Ok(())
        } else {
            Err(anyhow!("the memory engine does not answer on {} inside ai-jail", env.socket.display()))
        };
    }
    server::ensure_engine(client, env).await
}

/// The whole run.
pub(crate) async fn run_once(args: RunArgs, env: &Env, settings: &Settings) -> Result<RunOutcome> {
    let require_server = args.require_server || settings.run.require_server || args.project_id.is_some();
    let mut local = resolve(args, env, settings).await?;
    let ctx = JailContext { env, settings };
    if local.jail_plan.mode == JailMode::Stay {
        folders_need_a_jail(&local.jail_inputs)?;
    }
    if let JailMode::Explicit(spec) = &local.jail_plan.mode && local.ai_jail.is_some() {
        let spec = spec.clone();
        return Err(exec_explicit_jail(&local, &ctx, &spec).await?);
    }
    let client = Client::new(&env.socket, &env.token);
    if let Err(error) = reach_engine(&client, env, local.jailed).await {
        if require_server {
            return Err(error.context("opening managed workstream; the agent was not started"));
        }
        if local.jailed && apply_jail_process_isolation(local.provisional, &mut local.native_args) {
            eprintln!("ai-memory: OpenCode is running --standalone so its server and tool processes stay inside ai-jail");
        }
        return super::offline::run_degraded_offline(&local, &ctx, error).await;
    }
    super::recover::replay_journal(&client, env).await;
    let request = PrepareManagedRunRequest {
        project_id: local.project_id,
        workspace: local.workspace.clone(),
        project: if local.project_id.is_some() { String::new() } else { local.project.clone() },
        cwd: local.repository.cwd.to_string_lossy().into_owned(),
        repo_fingerprint: local.repository.repo_fingerprint.clone(),
        worktree_fingerprint: local.repository.worktree_fingerprint.clone(),
        agent: local.provisional.agent_kind(),
        automatic_harness: local.automatic,
        available_agents: unique_auto_agents(&local.auto_candidates),
        workstream: local.workstream.clone(),
        new_workstream: local.new_workstream.clone(),
        force_unlock: local.force_unlock,
        lease_owner: server::lease_owner(),
        repository_identity: None,
    };
    let interrupted = CancellationToken::new();
    let interrupt_task = tokio::spawn(capture_interrupts(interrupted.clone()));
    let prepared = server::prepare(&client, &request, local.interactive, &interrupted).await;
    let prepared = match prepared.context("opening managed workstream; the agent was not started") {
        Ok(prepared) => prepared,
        Err(error) => {
            interrupt_task.abort();
            return Err(error);
        }
    };
    let run_path = format!("/workstream/runs/{}", prepared.run_id);
    let outcome = super::launch::launch(&mut local, &ctx, client.clone(), prepared, &interrupted).await;
    interrupt_task.abort();
    match outcome {
        Ok(outcome) => Ok(outcome),
        Err(Failed { error, cancel }) => {
            if cancel {
                server::cancel_after_failure(&client, &run_path).await;
            }
            Err(error)
        }
    }
}
