//! Everything a launch resolves before it talks to the engine: the wrapper
//! flags left in the native argv, the launch environment (`--profile`,
//! `--env-file`, `--env`), the harness (named, or the newest checkout-local
//! session's), its executable, the scope and the jail plan.
//!
//! Follows the head of `run_once_with_wiring` in ai-memory v3.4.7 (fa0ec25; compared at v3.5.0, 411d90d, on 2026-11-19: unchanged),
//! crates/ai-memory-cli/src/commands/run.rs (lines ~619–820). Changed for
//! Cadex (2026-11-16): the scope is the hooks' (mod.rs `scope`, with
//! `--workspace`/`--project` over it); `--no-autowire` is read and ignored.

use std::ffi::{OsStr, OsString};
use std::io::{self, IsTerminal as _};
use std::path::PathBuf;
use std::str::FromStr as _;

use ai_memory_core::ProjectId;
use ai_memory_workstream::{
    JailHostFacts, ManagedHarness, RepositoryIdentity, inside_ai_jail_here, inspect_repository, usable_ai_jail_here,
};
use anyhow::{Context, Result, anyhow};

use super::args::{Env, RunArgs};
use super::auto::{AutoSessionCandidate, list_auto_sessions, no_auto_session_error, usable_auto_sessions};
use super::child_env::{EffectiveChildEnv, default_claude_wrapper, ensure_executable_available};
use super::choice::{RunHarnessChoice, managed_harness_for_args};
use super::jail::{JailInputs, JailPlan, NextRun, jail_decision, validate_flag_folders};
use super::opencode::{ResolvedOpenCode, resolve_opencode_for_launch};
use super::profiles::{Settings, profile, resolve_run_env};
use super::wrapper::{
    jail_request, remove_wrapper_force_unlock, remove_wrapper_fresh, remove_wrapper_jail, remove_wrapper_no_autowire,
    remove_wrapper_no_exit_prompt, take_wrapper_yolo, yolo_deprecation_notes,
};

/// The launch as resolved on this machine.
pub(crate) struct Local {
    pub(crate) repository: RepositoryIdentity,
    pub(crate) home: PathBuf,
    pub(crate) automatic: bool,
    pub(crate) requested: Option<RunHarnessChoice>,
    pub(crate) provisional: ManagedHarness,
    pub(crate) executable: Option<OsString>,
    pub(crate) native_args: Vec<OsString>,
    pub(crate) yolo: bool,
    pub(crate) force_fresh: bool,
    pub(crate) force_unlock: bool,
    pub(crate) may_adopt: bool,
    pub(crate) child_env: EffectiveChildEnv,
    pub(crate) workspace: String,
    pub(crate) project: String,
    pub(crate) project_id: Option<ProjectId>,
    pub(crate) interactive: bool,
    pub(crate) jailed: bool,
    pub(crate) ai_jail: Option<PathBuf>,
    pub(crate) jail_facts: JailHostFacts,
    pub(crate) jail_plan: JailPlan,
    pub(crate) jail_inputs: JailInputs,
    pub(crate) auto_candidates: Vec<AutoSessionCandidate>,
    pub(crate) opencode: Option<ResolvedOpenCode>,
    pub(crate) workstream: Option<String>,
    pub(crate) new_workstream: Option<String>,
    pub(crate) claude_kit_args: Vec<OsString>,
    pub(crate) codex_kit_args: Vec<OsString>,
}

impl Local {
    pub(crate) fn opencode_harness(&self) -> Option<ManagedHarness> {
        self.opencode.as_ref().map(ResolvedOpenCode::harness)
    }

    /// The resolved OpenCode executable, for an OpenCode launch.
    pub(crate) fn pin_opencode_executable(&mut self, harness: ManagedHarness) {
        if matches!(harness, ManagedHarness::OpenCode | ManagedHarness::OpenCode2) && let Some(resolved) = &self.opencode {
            self.executable = Some(resolved.executable.clone().into_os_string());
        }
    }
}

fn scope(args: &RunArgs, env: &Env, repository: &RepositoryIdentity) -> (String, String) {
    let (workspace, project) = super::scope(&repository.cwd, env.workspace.as_deref());
    (args.workspace.clone().unwrap_or(workspace), args.project.clone().unwrap_or(project))
}

/// Resolve the launch; `args` as typed.
pub(crate) async fn resolve(args: RunArgs, env: &Env, settings: &Settings) -> Result<Local> {
    let cwd = std::env::current_dir().context("getting managed run working directory")?;
    let repository = inspect_repository(&cwd)?;
    let home = env.home.clone();
    let automatic = args.harness.is_none();
    let requested = args.harness;
    let folder_flags: Vec<(PathBuf, bool)> =
        args.jail_map.iter().map(|p| (p.clone(), false)).chain(args.jail_rw_map.iter().map(|p| (p.clone(), true))).collect();
    let mut executable = args.executable.clone().map(PathBuf::into_os_string);
    let mut native_args = args.native_args.clone();
    let (yolo, true_yolo_typed) = take_wrapper_yolo(args.yolo, args.true_yolo, &mut native_args);
    let force_fresh = args.fresh | remove_wrapper_fresh(&mut native_args);
    let force_unlock = args.force_unlock | remove_wrapper_force_unlock(&mut native_args);
    let no_autowire = args.no_autowire | remove_wrapper_no_autowire(&mut native_args);
    remove_wrapper_no_exit_prompt(&mut native_args);
    let trailing_jail = remove_wrapper_jail(&mut native_args);
    let request = jail_request(args.jail.clone(), args.no_jail, trailing_jail)?;
    let chosen_profile = args.profile.as_deref().map(|name| profile(settings, name)).transpose()?;
    let run_env = resolve_run_env(chosen_profile, args.env_file.as_deref(), &args.env)
        .context("resolving --profile/--env-file/--env for the managed run")?;
    let child_env = EffectiveChildEnv::with_overrides(&run_env);
    if automatic && !native_args.is_empty() {
        return Err(anyhow!("native harness arguments require an explicit harness; try `ai-memory run codex ...`"));
    }
    if automatic && executable.is_some() {
        return Err(anyhow!("--executable requires an explicit harness; try `ai-memory run --executable <path> codex`"));
    }
    default_claude_wrapper(&mut executable, requested, args.claude_wrapper.as_deref(), child_env.executable_search());
    let opencode = resolve_opencode_for_launch(requested, executable.as_deref(), &child_env)?;
    if matches!(requested, Some(RunHarnessChoice::OpenCode)) && let Some(resolved) = &opencode {
        executable = Some(resolved.executable.clone().into_os_string());
    }
    let auto_candidates = if automatic {
        let found = list_auto_sessions(&home, &repository.cwd, &child_env, opencode.as_ref().map(ResolvedOpenCode::harness)).await?;
        usable_auto_sessions(found, opencode.as_ref(), &child_env)?
    } else {
        Vec::new()
    };
    let provisional = match requested {
        Some(RunHarnessChoice::OpenCode) => opencode.as_ref().map(ResolvedOpenCode::harness).context("OpenCode dialect was not resolved")?,
        Some(choice) => managed_harness_for_args(choice, &native_args),
        None => auto_candidates.first().map(|candidate| candidate.harness).ok_or_else(no_auto_session_error)?,
    };
    if automatic && matches!(provisional, ManagedHarness::OpenCode | ManagedHarness::OpenCode2) && let Some(resolved) = &opencode {
        executable = Some(resolved.executable.clone().into_os_string());
    }
    ensure_executable_available(provisional, executable.as_deref().map(OsStr::new), child_env.executable_search())?;
    let (workspace, project) = scope(&args, env, &repository);
    let interactive = io::stdin().is_terminal() && io::stderr().is_terminal();
    let jailed = inside_ai_jail_here();
    if interactive && !jailed {
        for note in yolo_deprecation_notes(true_yolo_typed, settings.claude_true_yolo) {
            eprintln!("{note}");
        }
    }
    let ai_jail = if jailed { None } else { usable_ai_jail_here() };
    let jail_facts = JailHostFacts::here(&repository);
    let jail_plan = jail_decision(&request, jailed, yolo, interactive, ai_jail.is_some(), jail_facts.project_config)?;
    let next_run = NextRun {
        yolo,
        no_autowire,
        workspace: args.workspace.clone(),
        project: args.project.clone(),
        profile: args.profile.clone(),
        env_file: args.env_file.clone(),
        had_env: !args.env.is_empty(),
        harness: requested.map(|choice| choice.name().to_owned()),
    };
    let flag_folders =
        if jailed { Vec::new() } else { validate_flag_folders(&env.data_dir, &repository.cwd, &home, &folder_flags)? };
    let jail_inputs = JailInputs {
        checkout_key: repository.worktree_fingerprint.clone(),
        checkout_root: repository.cwd.clone(),
        home: home.clone(),
        flag_folders,
        next_run,
    };
    let project_id = args.project_id.as_deref().map(|id| ProjectId::from_str(id).map_err(|e| anyhow!("--project-id: {e}"))).transpose()?;
    Ok(Local {
        may_adopt: args.new_workstream.is_none() && !force_fresh,
        repository,
        home,
        automatic,
        requested,
        provisional,
        executable,
        native_args,
        yolo,
        force_fresh,
        force_unlock,
        child_env,
        workspace,
        project,
        project_id,
        interactive,
        jailed,
        ai_jail,
        jail_facts,
        jail_plan,
        jail_inputs,
        auto_candidates,
        opencode,
        workstream: args.workstream,
        new_workstream: args.new_workstream,
        claude_kit_args: args.claude_kit_args,
        codex_kit_args: args.codex_kit_args,
    })
}
