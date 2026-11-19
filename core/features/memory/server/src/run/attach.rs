//! A linked Claude session still running in the background: Claude refuses
//! `--resume` on it and points at `claude attach <id>`, so the launcher
//! attaches instead.
//!
//! Copied from ai-memory v3.4.7 (fa0ec25; compared at v3.5.0, 411d90d, on 2026-11-19: unchanged), crates/ai-memory-cli/src/commands/
//! run.rs: `claude_background_attach_id` and `CLAUDE_AGENTS_TIMEOUT`
//! (2026-11-16). The transcript is read first, so a foreground session never
//! costs a `claude agents` call; any failure keeps the native resume.

use std::path::Path;
use std::process::Stdio;
use std::time::Duration;

use ai_memory_workstream::{LaunchPlan, claude_live_background_attach_id, claude_session_ran_in_background};
use tokio::process::Command;

use super::child_env::{EffectiveChildEnv, resolve_program};

/// Bound on `claude agents --json`, which only reads the daemon's list.
const CLAUDE_AGENTS_TIMEOUT: Duration = Duration::from_secs(10);

pub(crate) async fn claude_background_attach_id(plan: &LaunchPlan, home: &Path, cwd: &Path, env: &EffectiveChildEnv,
    native_session_id: &str) -> Option<String> {
    let background =
        claude_session_ran_in_background(home, cwd, plan.session_dir.as_deref(), native_session_id).unwrap_or(false);
    if !background {
        return None;
    }
    let program = resolve_program(&plan.program, env.executable_search()).unwrap_or_else(|| plan.program.clone().into());
    let mut command = Command::new(&program);
    env.apply_to_tokio(&mut command);
    command
        .args(["agents", "--json", "--cwd"])
        .arg(cwd)
        .current_dir(cwd)
        .stdin(Stdio::null())
        .stderr(Stdio::null())
        .kill_on_drop(true);
    let output = tokio::time::timeout(CLAUDE_AGENTS_TIMEOUT, command.output()).await.ok()?.ok()?;
    if !output.status.success() {
        return None;
    }
    claude_live_background_attach_id(&output.stdout, native_session_id, cwd)
}
