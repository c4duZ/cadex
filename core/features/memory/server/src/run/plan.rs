//! The native launch plan and, after the agent exits, which native session
//! the run was: the harness logic stays in ai-memory-workstream; this is the
//! launcher's glue around it.
//!
//! Copied from ai-memory v3.4.7 (fa0ec25; compared at v3.5.0, 411d90d, on 2026-11-19: unchanged), crates/ai-memory-cli/src/commands/
//! run.rs: `build_preflighted_launch_plan`, `own_native_session`,
//! `follow_claude_continued_session`, `claude_left_behind_session_ids`,
//! `resolve_native_session_after_run`, `auto_session_dir` and
//! `display_session_id`. Changed for Cadex (2026-11-16): no i18n; the
//! store record and mismatch check are store_record.rs's.

use std::ffi::{OsStr, OsString};
use std::path::{Path, PathBuf};
use std::time::SystemTime;

use ai_memory_core::{ManagedRunStatus, NativeSessionIdentity, Sanitizer};
use ai_memory_workstream::{
    AmbiguousNativeSession, ClaudeContinuation, LaunchMode, LaunchPlan, LaunchRoots, ManagedHarness,
    build_launch_plan_with_env_lookup, claude_continued_session, claude_continued_sessions, discover_native_session,
    has_native_session_selector, native_session_exists, native_session_in_checkout,
};
use anyhow::{Result, anyhow};

use super::child_env::EffectiveChildEnv;

pub(crate) fn display_session_id(value: &str) -> String {
    const MAX_CHARS: usize = 64;
    let mut output: String = value.chars().take(MAX_CHARS).collect();
    if value.chars().count() > MAX_CHARS {
        output.push_str("...");
    }
    super::terminal_text(&output)
}

/// The plan under the launch environment (`--env` over the process's).
pub(crate) fn plan_for(harness: ManagedHarness, executable: Option<OsString>, args: Vec<OsString>, linked: Option<&str>,
    home: &Path, cwd: &Path, env: &EffectiveChildEnv) -> Result<LaunchPlan> {
    build_launch_plan_with_env_lookup(harness, executable, args, linked, |name| env.lookup(name), Some(LaunchRoots { home, cwd }))
}

/// The store a harness reads in this environment (`CLAUDE_CONFIG_DIR`,
/// `CODEX_HOME`), `None` for the default under `home`.
pub(crate) fn auto_session_dir(harness: ManagedHarness, home: &Path, cwd: &Path, env: &EffectiveChildEnv)
    -> Result<Option<PathBuf>> {
    Ok(plan_for(harness, None, Vec::new(), None, home, cwd, env)?.session_dir)
}

/// The plan, and the linked session it could not resume because the native
/// store no longer has it (then the plan starts fresh).
// Upstream's own signature (plus nothing): kept for a line-by-line compare.
#[allow(clippy::too_many_arguments)]
pub(crate) fn build_preflighted_launch_plan(harness: ManagedHarness, executable: Option<OsString>,
    native_args: Vec<OsString>, linked_session_id: Option<&str>, force_fresh: bool, home: &Path, cwd: &Path,
    env: &EffectiveChildEnv) -> Result<(LaunchPlan, Option<String>)> {
    if let Some(id) = linked_session_id {
        NativeSessionIdentity::parse(id, &Sanitizer::builtin())?;
    }
    let explicit_selector = has_native_session_selector(harness, &native_args);
    if force_fresh && explicit_selector {
        return Err(anyhow!("--fresh cannot be combined with a native session, resume, continue, or fork selector"));
    }
    let linked = if force_fresh { None } else { linked_session_id };
    let plan = plan_for(harness, executable.clone(), native_args.clone(), linked, home, cwd, env)?;
    let Some(linked) = linked else { return Ok((plan, None)) };
    if explicit_selector || plan.mode != LaunchMode::Session {
        return Ok((plan, None));
    }
    match native_session_exists(harness, home, cwd, plan.session_dir.as_deref(), linked) {
        Ok(true) => Ok((plan, None)),
        Ok(false) => Ok((plan_for(harness, executable, native_args, None, home, cwd, env)?, Some(linked.to_owned()))),
        Err(error) => {
            eprintln!(
                "ai-memory: could not verify linked {} session {} ({error}); preserving native resume. Use --fresh to bypass it",
                harness.as_str(),
                display_session_id(linked)
            );
            Ok((plan, None))
        }
    }
}

pub(crate) fn own_native_session(plan: &LaunchPlan, harness: ManagedHarness, home: &Path, cwd: &Path,
    status: Option<&ManagedRunStatus>, sanitizer: &Sanitizer) -> Result<Option<String>> {
    if plan.mode == LaunchMode::Passthrough {
        return Ok(None);
    }
    if let Some(id) = &plan.expected_session_id {
        return Ok(Some(NativeSessionIdentity::parse(id, sanitizer)?.into_string()));
    }
    let Some(linked) = status.filter(|s| s.native_session_linked).and_then(|s| s.native_session_id.as_deref()) else {
        return Ok(None);
    };
    let linked = NativeSessionIdentity::parse(linked, sanitizer)?;
    let linked = linked.as_str();
    let in_checkout = native_session_in_checkout(harness, home, cwd, plan.session_dir.as_deref(), linked)
        .map_err(|e| anyhow!("reading native session {linked}: {e}"))?;
    Ok(in_checkout.then(|| linked.to_owned()))
}

/// A Claude session `/clear`ed or moved to a background session went on in
/// another transcript; the workstream follows it.
fn follow_claude_continued_session(plan: &LaunchPlan, harness: ManagedHarness, home: &Path, cwd: &Path, own: String,
    started_at: SystemTime) -> String {
    if harness != ManagedHarness::Claude {
        return own;
    }
    match claude_continued_session(home, cwd, plan.session_dir.as_deref(), &own, started_at) {
        Ok(Some(continuation)) => {
            let how = match &continuation {
                ClaudeContinuation::Background(_) => "continued in background session",
                ClaudeContinuation::Cleared(_) => "was cleared into session",
            };
            eprintln!(
                "ai-memory: Claude session {} {how} {}; the workstream now follows it",
                display_session_id(&own),
                display_session_id(continuation.session_id())
            );
            continuation.session_id().to_owned()
        }
        Ok(None) => own,
        Err(error) => {
            eprintln!(
                "ai-memory: could not check whether Claude session {} moved to another session ({error}); keeping it",
                display_session_id(&own)
            );
            own
        }
    }
}

/// The Claude sessions a continuation left behind on its way to `followed`.
pub(crate) fn claude_left_behind_session_ids(harness: ManagedHarness, home: &Path, cwd: &Path,
    session_dir: Option<&Path>, own: &str, followed: &str, started_at: SystemTime) -> Result<Vec<String>> {
    if harness != ManagedHarness::Claude || own == followed {
        return Ok(Vec::new());
    }
    let mut sessions = vec![own.to_owned()];
    for continuation in claude_continued_sessions(home, cwd, session_dir, own, started_at)? {
        let id = continuation.session_id();
        if id == followed {
            return Ok(sessions);
        }
        if !sessions.iter().any(|known| known == id) {
            sessions.push(id.to_owned());
        }
    }
    Err(anyhow!("followed Claude session {} was absent from its continuation chain", display_session_id(followed)))
}

/// The run's native session: the planned or linked one, else the one the
/// store shows started by this launch.
pub(crate) async fn resolve_native_session_after_run(plan: &LaunchPlan, harness: ManagedHarness, home: &Path,
    cwd: &Path, started_at: SystemTime, status: Option<&ManagedRunStatus>, sanitizer: &Sanitizer) -> Result<Option<String>> {
    if plan.mode == LaunchMode::Passthrough {
        return Ok(None);
    }
    if let Some(id) = status.and_then(|s| s.native_session_id.as_deref()) {
        NativeSessionIdentity::parse(id, sanitizer)?;
    }
    if let Ok(Some(own)) = own_native_session(plan, harness, home, cwd, status, sanitizer) {
        return Ok(Some(follow_claude_continued_session(plan, harness, home, cwd, own, started_at)));
    }
    let linked = status.filter(|s| s.native_session_linked).and_then(|s| s.native_session_id.as_deref());
    let fresh = !has_native_session_selector(harness, &plan.args);
    let discovered = match discover_native_session(harness, home, cwd, plan.session_dir.as_deref(), started_at, fresh).await {
        Ok(discovered) => discovered,
        Err(error) if error.is::<AmbiguousNativeSession>() => {
            eprintln!(
                "ai-memory: {error}, so its transcript was not imported; resume the session with its native selector to link it"
            );
            return Ok(None);
        }
        Err(error) => return Err(error),
    };
    let resolved = discovered.or_else(|| {
        status.and_then(|s| s.native_session_id.clone()).filter(|reported| Some(reported.as_str()) != linked)
    });
    Ok(resolved
        .as_deref()
        .map(|id| NativeSessionIdentity::parse(id, sanitizer).map(NativeSessionIdentity::into_string))
        .transpose()?)
}

/// The session kit's flags for the resolved harness, after the plan (see
/// args.rs); other harnesses get none.
pub(crate) fn append_kit_args(plan: &mut LaunchPlan, harness: ManagedHarness, claude: &[OsString], codex: &[OsString]) {
    let kit = match harness {
        ManagedHarness::Claude => claude,
        ManagedHarness::Codex => codex,
        _ => &[],
    };
    plan.args.extend(kit.iter().map(|a| OsStr::new(a).to_os_string()));
}
