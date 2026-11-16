//! The environment the agent runs with (the launcher's own, then the
//! `--profile`/`--env-file`/`--env` overrides) and the executables found
//! through its `PATH`.
//!
//! Copied from ai-memory v3.4.7 (fa0ec25), crates/ai-memory-cli/src/commands/
//! run.rs: `EffectiveChildEnv` (Unix only: case-sensitive keys),
//! `ExecutableSearch`, `resolve_program`, `resolve_candidate` (Unix branch),
//! `executable_file`, `executable_available`, `harness_available`,
//! `ensure_executable_available`, `default_claude_wrapper`,
//! `claude_wrapper_executable` and `blank_home_overrides`. Changed for Cadex
//! (2026-11-16): the missing-executable error drops upstream's Docker
//! wrapper hint (`docker_host_client_hint`), which names `ai-memory upgrade`.

use std::ffi::{OsStr, OsString};
use std::path::{Path, PathBuf};

use ai_memory_workstream::{ManagedHarness, store_override_vars};
use anyhow::{Result, anyhow};

use super::choice::{RunHarnessChoice, managed_harness};

#[derive(Clone, Default, Debug)]
pub(crate) struct EffectiveChildEnv {
    entries: Vec<(OsString, OsString)>,
}

impl EffectiveChildEnv {
    /// This process's environment with `overrides` over it.
    pub(crate) fn with_overrides(overrides: &[(String, String)]) -> Self {
        let mut effective = Self { entries: std::env::vars_os().collect() };
        for (key, value) in overrides {
            effective.upsert(OsString::from(key), OsString::from(value));
        }
        effective
    }

    fn upsert(&mut self, key: OsString, value: OsString) {
        self.entries.retain(|(existing, _)| *existing != key);
        self.entries.push((key, value));
    }

    pub(crate) fn get(&self, name: &str) -> Option<&OsStr> {
        self.entries.iter().rev().find(|(key, _)| key == name).map(|(_, value)| value.as_os_str())
    }

    pub(crate) fn lookup(&self, name: &str) -> Option<OsString> {
        self.get(name).map(OsStr::to_os_string)
    }

    pub(crate) fn executable_search(&self) -> ExecutableSearch<'_> {
        ExecutableSearch { path: self.get("PATH") }
    }

    pub(crate) fn apply_to_std(&self, command: &mut std::process::Command) {
        command.env_clear().envs(self.entries.iter().map(|(k, v)| (k, v)));
    }

    pub(crate) fn apply_to_tokio(&self, command: &mut tokio::process::Command) {
        command.env_clear().envs(self.entries.iter().map(|(k, v)| (k, v)));
    }
}

#[derive(Clone, Copy)]
pub(crate) struct ExecutableSearch<'a> {
    path: Option<&'a OsStr>,
}

/// `program` resolved to a file the OS can start, or `None`.
pub(crate) fn resolve_program(program: &OsStr, search: ExecutableSearch<'_>) -> Option<PathBuf> {
    let path = Path::new(program);
    if path.components().count() > 1 {
        return executable_file(path).then(|| path.to_path_buf());
    }
    search.path.and_then(|value| {
        std::env::split_paths(value).map(|dir| dir.join(path)).find(|candidate| executable_file(candidate))
    })
}

fn executable_file(path: &Path) -> bool {
    use std::os::unix::fs::PermissionsExt as _;
    path.metadata().is_ok_and(|m| m.is_file() && m.permissions().mode() & 0o111 != 0)
}

pub(crate) fn executable_available(program: &OsStr, search: ExecutableSearch<'_>) -> bool {
    resolve_program(program, search).is_some()
}

/// Whether this harness's default executable resolves through `PATH`.
pub(crate) fn harness_available(choice: RunHarnessChoice, search: ExecutableSearch<'_>) -> bool {
    executable_available(OsStr::new(managed_harness(choice).executable()), search)
}

pub(crate) fn ensure_executable_available(harness: ManagedHarness, executable: Option<&OsStr>,
    search: ExecutableSearch<'_>) -> Result<()> {
    let program = executable.unwrap_or_else(|| OsStr::new(harness.executable()));
    if executable_available(program, search) {
        return Ok(());
    }
    Err(anyhow!(
        "managed {} executable `{}` was not found in the host PATH; install it or pass `--executable`.",
        harness.as_str(),
        program.to_string_lossy(),
    ))
}

/// Points an unset `--executable` at the typed `claude*` wrapper, warning
/// when none is installed.
pub(crate) fn default_claude_wrapper(executable: &mut Option<OsString>, requested: Option<RunHarnessChoice>,
    spelling: Option<&str>, search: ExecutableSearch<'_>) {
    if executable.is_some() || requested != Some(RunHarnessChoice::Claude) {
        return;
    }
    let Some(spelling) = spelling else { return };
    match claude_wrapper_executable(spelling, search) {
        Ok(wrapper) => *executable = Some(wrapper),
        Err(warning) => eprintln!("{}", super::terminal_text(&warning)),
    }
}

fn claude_wrapper_executable(spelling: &str, search: ExecutableSearch<'_>) -> Result<OsString, String> {
    let bare_name = !spelling.contains(['/', '\\']);
    if bare_name && executable_available(OsStr::new(spelling), search) {
        return Ok(OsString::from(spelling));
    }
    Err(format!(
        "ai-memory: no `{spelling}` executable found on PATH; running plain `claude`. \
         To use a wrapper, put it on PATH or pass `--executable <path>`"
    ))
}

/// The harness's home variables that are set but blank: dropped from the
/// child, as from session import and the Crush context config.
pub(crate) fn blank_home_overrides(harness: ManagedHarness, get: &dyn Fn(&str) -> Option<OsString>) -> Vec<&'static str> {
    let crush_config: &[&'static str] = match harness {
        ManagedHarness::Crush => &["CRUSH_GLOBAL_CONFIG", "XDG_CONFIG_HOME"],
        _ => &[],
    };
    store_override_vars(harness)
        .iter()
        .chain(crush_config)
        .copied()
        .filter(|name| {
            let value = get(name);
            value.is_some() && ai_memory_workstream::env_dir_override(value).is_none()
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_claude_spelling_picks_its_wrapper_only_when_it_is_installed() {
        let dir = tempfile::tempdir().unwrap();
        let wrapper = dir.path().join("claude-corp");
        std::fs::write(&wrapper, "#!/bin/sh\n").unwrap();
        use std::os::unix::fs::PermissionsExt as _;
        std::fs::set_permissions(&wrapper, std::fs::Permissions::from_mode(0o755)).unwrap();
        let path = dir.path().as_os_str().to_owned();
        let search = ExecutableSearch { path: Some(&path) };
        let mut executable = None;
        default_claude_wrapper(&mut executable, Some(RunHarnessChoice::Claude), Some("claude-corp"), search);
        assert_eq!(executable, Some(OsString::from("claude-corp")));
        assert!(claude_wrapper_executable("claude-home", search).unwrap_err().contains("running plain `claude`"));
        let blank = |name: &str| (name == "CLAUDE_CONFIG_DIR").then(|| OsString::from(" "));
        assert_eq!(blank_home_overrides(ManagedHarness::Claude, &blank), ["CLAUDE_CONFIG_DIR"]);
    }
}
