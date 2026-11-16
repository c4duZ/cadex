//! Re-running this same `cadex-memory run` inside ai-jail: by ai-jail's
//! wrapper contract (3.0.1+: `--harness`, `status --json`) or by flags, with
//! the original argv and what the jailed launcher needs to reach the engine.
//!
//! Copied from ai-memory v3.4.7 (fa0ec25), crates/ai-memory-cli/src/commands/
//! run.rs: `ContractTarget`, `jail_contract_for`, `JailLaunch`,
//! `ContractExec`, `exec_under_ai_jail_contract`, `jail_refusal_error`,
//! `jail_status`, `exec_under_ai_jail`, `jail_forwarded_args`,
//! `jail_forwarded_names`, `reexec_under_ai_jail` (Unix), and
//! `render_shared::shell_quote`. Changed for Cadex (2026-11-16):
//! - upstream forwards its server URL/base path (`jail_resolved_env`); Cadex
//!   has no URL, so the jailed launcher gets the session token, the absolute
//!   memory.sock path, the memory folder and the account's workspace
//!   (`CADEX_*`, set on the ai-jail process and named with `--env`);
//! - ai-jail's private home hides Application Support, so the socket file
//!   and `<data-dir>/run` (the launcher's records) are mounted read-write
//!   with `--rw-map` (not shown in the summary or the repeat line); with an
//!   ai-jail that cannot map folders the jailed run cannot reach the engine
//!   and launches degraded (offline.rs);
//! - the server is always reached as `ServerReach::Network` (`--network`):
//!   ai-jail has no Unix-socket grant, and its filtered network forwards
//!   TCP ports only (`--forward-port`), so the summary says so;
//! - `ensure_jail_does_not_export_config_token` and
//!   `ensure_jail_does_not_need_a_server_profile` have nothing to check (no
//!   config bearer, no server profiles).

use std::ffi::OsString;
use std::path::{Path, PathBuf};

use ai_memory_workstream::{
    FORWARDED_ENV_NAMES, JailRefusal, JailSupport, JailToggleChoice, ManagedHarness, ServerReach, ai_jail_contract,
    ai_jail_harness_name, build_ai_jail_invocation, contract_flags, contract_invocation, contract_status_invocation,
    harness_env_names, parse_status, status_refusal,
};
use anyhow::anyhow;

use super::args::Env;
use super::jail::NEXT_RUN_ENV;
use super::jail_checklist::jail_summary;
use super::jail_folders::ExtraFolder;
use super::profiles::Settings;

/// The variables the jailed launcher reads to reach the engine.
const CADEX_FORWARDED: &[&str] =
    &["CADEX_SESSION_TOKEN", "CADEX_MEMORY_SOCKET", "CADEX_MEMORY_DIR", "CADEX_SESSIONS_DIR", "CADEX_MEMORY_WORKSPACE"];

/// What the re-exec reads from this launch.
pub(crate) struct JailContext<'a> {
    pub(crate) env: &'a Env,
    pub(crate) settings: &'a Settings,
}

#[derive(Debug, Clone)]
pub(crate) struct ContractTarget {
    managed: ManagedHarness,
    harness: &'static str,
    version: String,
}

/// The contract target, or `None` to keep the flag-based launch.
pub(crate) fn jail_contract_for(ai_jail: &Path, support: &JailSupport, harness: Option<ManagedHarness>) -> Option<ContractTarget> {
    let managed = harness?;
    let name = ai_jail_harness_name(managed)?;
    let contract = ai_jail_contract(ai_jail, support)?;
    Some(ContractTarget { managed, harness: name, version: contract.version })
}

#[derive(Clone, Copy)]
pub(crate) struct JailLaunch<'a> {
    pub(crate) support: &'a JailSupport,
    pub(crate) contract: Option<&'a ContractTarget>,
}

pub(crate) fn shell_quote(s: &str) -> String {
    if s.chars().all(|c| c.is_ascii_alphanumeric() || matches!(c, '-' | '_' | '.' | '/' | ':' | '@' | '%' | '+' | '=' | ',')) {
        return s.to_string();
    }
    format!("'{}'", s.replace('\'', "'\\''"))
}

/// Cadex's `jail_resolved_env`: the engine's whereabouts and the token.
fn jail_resolved_env(env: &Env) -> Vec<(&'static str, String)> {
    let mut resolved = vec![
        ("CADEX_SESSION_TOKEN", env.token.clone()),
        ("CADEX_MEMORY_SOCKET", env.socket.to_string_lossy().into_owned()),
        ("CADEX_MEMORY_DIR", env.data_dir.to_string_lossy().into_owned()),
    ];
    if let Some(dir) = &env.tokens_dir {
        resolved.push(("CADEX_SESSIONS_DIR", dir.to_string_lossy().into_owned()));
    }
    if let Some(workspace) = &env.workspace {
        resolved.push(("CADEX_MEMORY_WORKSPACE", workspace.clone()));
    }
    resolved
}

/// The names passed with `--env NAME`: upstream's list when set here, and
/// every name set on the ai-jail process.
fn jail_forwarded_names(resolved: &[(&'static str, String)]) -> Vec<&'static str> {
    FORWARDED_ENV_NAMES
        .iter()
        .chain(CADEX_FORWARDED)
        .copied()
        .filter(|name| std::env::var_os(name).is_some() || resolved.iter().any(|(set, _)| set == name))
        .collect()
}

/// The original argv after the program, plus `--no-exit-prompt` when the
/// config turned the menu off (the jail's private home cannot read it).
fn jail_forwarded_args(settings: &Settings, original: impl IntoIterator<Item = OsString>) -> Vec<OsString> {
    let mut args: Vec<_> = original.into_iter().collect();
    if !settings.run.exit_prompt && !args.iter().any(|arg| arg == "--no-exit-prompt") {
        args.push(OsString::from("--no-exit-prompt"));
    }
    args
}

/// The socket file and the launcher's records, read-write in the jail.
fn engine_mounts(env: &Env) -> Vec<(PathBuf, bool)> {
    let run_dir = env.run_dir();
    let _ = std::fs::create_dir_all(&run_dir);
    vec![(env.socket.clone(), true), (run_dir, true)]
}

/// Re-exec under `ai_jail`; returns only on failure.
pub(crate) fn exec_under_ai_jail(ai_jail: &Path, ctx: &JailContext<'_>, launch: JailLaunch<'_>, toggles: &[JailToggleChoice],
    project_config: bool, folders: &[ExtraFolder], next_run: Option<String>) -> anyhow::Error {
    if !folders.is_empty() && !launch.support.mounts_folders() {
        return anyhow!("this ai-jail cannot mount extra folders (--map / --rw-map); update ai-jail or drop --jail-map");
    }
    let exe = match std::env::current_exe() {
        Ok(exe) => exe,
        Err(error) => return anyhow!(error).context("resolving the current executable for the ai-jail re-exec"),
    };
    let forwarded = jail_forwarded_args(ctx.settings, std::env::args_os().skip(1));
    let mut resolved = jail_resolved_env(ctx.env);
    if let Some(command) = next_run {
        resolved.push((NEXT_RUN_ENV, command));
    }
    let present = jail_forwarded_names(&resolved);
    let mut mounts: Vec<(PathBuf, bool)> = folders.iter().map(|f| (f.path.clone(), f.writable)).collect();
    if launch.support.mounts_folders() {
        mounts.extend(engine_mounts(ctx.env));
    } else {
        eprintln!("ai-memory: this ai-jail cannot map memory.sock into the jail (--rw-map); the jailed run will launch without the memory engine");
    }
    let pairs: Vec<(&Path, bool)> = mounts.iter().map(|(path, writable)| (path.as_path(), *writable)).collect();
    if let Some(contract) = launch.contract {
        let env_names = harness_env_names(contract.managed, &present);
        let flags = contract_flags(contract.harness, ServerReach::Network, &env_names, toggles, &pairs);
        if let Some(status) = jail_status(ai_jail, &contract_status_invocation(&flags, &exe, &forwarded), &resolved)
            && let Some(refusal) = status_refusal(&status)
        {
            return jail_refusal_error(ai_jail, contract.harness, refusal);
        }
        eprintln!("{}", jail_summary(toggles, false, folders));
        eprintln!(
            "ai-memory: ai-jail {} reviews the rest of the access for {} (memory engine through its Unix socket, with full network: ai-jail forwards TCP ports only)",
            contract.version, contract.harness
        );
        return reexec_under_ai_jail(ai_jail, &contract_invocation(&flags, &exe, &forwarded), &resolved);
    }
    let jail_args = build_ai_jail_invocation(&exe, &forwarded, &present, true, launch.support.supports("no-save-config"),
        toggles, &pairs);
    eprintln!("{}", jail_summary(toggles, project_config, folders));
    reexec_under_ai_jail(ai_jail, &jail_args, &resolved)
}

fn jail_refusal_error(ai_jail: &Path, harness: &str, refusal: JailRefusal) -> anyhow::Error {
    match refusal {
        JailRefusal::Backend(message) => anyhow!("ai-jail cannot start its sandbox on this machine: {message}"),
        JailRefusal::Drift(message) => {
            let review = format!("{} configure {harness}", shell_quote(&ai_jail.to_string_lossy()));
            anyhow!("ai-jail's saved access for this project no longer matches this machine: {message}. Review it with: {review}")
        }
    }
}

fn jail_status(ai_jail: &Path, args: &[OsString], env: &[(&'static str, String)]) -> Option<ai_memory_workstream::JailStatus> {
    let output = std::process::Command::new(ai_jail)
        .args(args)
        .envs(env.iter().map(|(name, value)| (name, value)))
        .stdin(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .output()
        .ok()?;
    parse_status(&String::from_utf8_lossy(&output.stdout))
}

/// Replace this process with `<ai_jail> <jail_args>`; never returns on success.
fn reexec_under_ai_jail(ai_jail: &Path, jail_args: &[OsString], env: &[(&'static str, String)]) -> anyhow::Error {
    use std::os::unix::process::CommandExt as _;
    let error = std::process::Command::new(ai_jail).args(jail_args).envs(env.iter().map(|(n, v)| (n, v))).exec();
    anyhow!(error).context(format!("re-executing under {}", ai_jail.display()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_jail_gets_the_engine_and_the_exit_prompt_opt_out() {
        let env = Env {
            socket: "/s/memory.sock".into(),
            data_dir: "/d".into(),
            tokens_dir: None,
            token: "t".into(),
            workspace: Some("acct".into()),
            home: "/h".into(),
        };
        let resolved = jail_resolved_env(&env);
        assert!(resolved.contains(&("CADEX_MEMORY_SOCKET", "/s/memory.sock".into())));
        let names = jail_forwarded_names(&resolved);
        assert!(names.contains(&"CADEX_SESSION_TOKEN") && names.contains(&"CADEX_MEMORY_WORKSPACE"));
        let mut settings = Settings::default();
        settings.run.exit_prompt = false;
        assert_eq!(jail_forwarded_args(&settings, [OsString::from("run")]), [OsString::from("run"), "--no-exit-prompt".into()]);
        assert_eq!(shell_quote("a b"), "'a b'");
    }
}
