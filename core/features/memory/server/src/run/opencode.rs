//! Which OpenCode major an `opencode` executable is (V1 or V2 contracts),
//! asked with `opencode --version` under the launch environment.
//!
//! Copied from ai-memory v3.4.7 (fa0ec25): `ResolvedOpenCode`,
//! `resolve_generic`, `resolve_generic_with_timeout`, `spawn_retrying_busy`,
//! `timeout_error` and `read_bounded` (crates/ai-memory-cli/src/commands/
//! opencode_dialect.rs) and `resolve_opencode_for_launch` (commands/run.rs).
//! Changed for Cadex (2026-11-16): no i18n; the installer resolvers
//! (`resolve_agent`, `resolve_client`) are autowire's and stay out.

use std::ffi::OsStr;
use std::io::Read;
use std::process::{Command, Stdio};
use std::sync::mpsc;
use std::thread;
use std::time::{Duration, Instant};

use ai_memory_workstream::{ManagedHarness, OpenCodeDialect};
use anyhow::{Context as _, Result, anyhow, bail};

use super::child_env::{EffectiveChildEnv, executable_available, resolve_program};
use super::choice::RunHarnessChoice;

const PROBE_TIMEOUT: Duration = Duration::from_secs(10);
const MAX_VERSION_OUTPUT: u64 = 64 * 1024;

#[derive(Debug)]
pub(crate) struct ResolvedOpenCode {
    pub(crate) dialect: OpenCodeDialect,
    pub(crate) executable: std::path::PathBuf,
}

impl ResolvedOpenCode {
    pub(crate) fn harness(&self) -> ManagedHarness {
        self.dialect.harness()
    }
}

/// The dialect of an explicit `opencode`, or of one on `PATH` for an
/// automatic launch (whose probe failure only skips OpenCode).
pub(crate) fn resolve_opencode_for_launch(requested: Option<RunHarnessChoice>, executable: Option<&OsStr>,
    env: &EffectiveChildEnv) -> Result<Option<ResolvedOpenCode>> {
    let automatic = requested.is_none();
    if !(matches!(requested, Some(RunHarnessChoice::OpenCode))
        || automatic && executable_available(OsStr::new("opencode"), env.executable_search()))
    {
        return Ok(None);
    }
    match resolve_generic_with_timeout(executable, env, PROBE_TIMEOUT) {
        Ok(resolved) => Ok(Some(resolved)),
        Err(error) if automatic => {
            eprintln!("ai-memory: automatic OpenCode scan skipped: {error:#}");
            Ok(None)
        }
        Err(error) => Err(error),
    }
}

fn resolve_generic_with_timeout(executable: Option<&OsStr>, env: &EffectiveChildEnv, timeout: Duration)
    -> Result<ResolvedOpenCode> {
    let program = executable.unwrap_or_else(|| OsStr::new("opencode"));
    let resolved = resolve_program(program, env.executable_search()).ok_or_else(|| {
        anyhow!(
            "OpenCode executable `{}` was not found; install it or select an explicit opencode2 compatibility alias",
            program.to_string_lossy()
        )
    })?;
    let mut command = Command::new(&resolved);
    env.apply_to_std(&mut command);
    command.arg("--version").stdin(Stdio::null()).stdout(Stdio::piped()).stderr(Stdio::piped());
    let mut child = spawn_retrying_busy(&mut command)
        .with_context(|| format!("probing OpenCode executable {}", resolved.display()))?;
    let stdout = read_bounded(child.stdout.take());
    let stderr = read_bounded(child.stderr.take());
    let started = Instant::now();
    let status = loop {
        if let Some(status) = child.try_wait().with_context(|| format!("waiting for OpenCode version probe {}", resolved.display()))? {
            break status;
        }
        if started.elapsed() >= timeout {
            let _ = child.kill();
            let _ = child.wait();
            return Err(timeout_error(&resolved, timeout));
        }
        thread::sleep(Duration::from_millis(10));
    };
    let remaining = timeout.saturating_sub(started.elapsed());
    let stdout = stdout.recv_timeout(remaining).map_err(|_| timeout_error(&resolved, timeout))??;
    let remaining = timeout.saturating_sub(started.elapsed());
    let stderr = stderr.recv_timeout(remaining).map_err(|_| timeout_error(&resolved, timeout))??;
    if stdout.len() > MAX_VERSION_OUTPUT as usize || stderr.len() > MAX_VERSION_OUTPUT as usize {
        bail!("OpenCode version probe returned more than {MAX_VERSION_OUTPUT} bytes");
    }
    if !status.success() {
        bail!("OpenCode version probe `{}` --version failed with {status}: {}", resolved.display(),
            String::from_utf8_lossy(&stderr).trim());
    }
    let stdout = std::str::from_utf8(&stdout).context("OpenCode version output was not UTF-8")?;
    let stderr = std::str::from_utf8(&stderr).context("OpenCode version error output was not UTF-8")?;
    let output = match (stdout.trim(), stderr.trim()) {
        ("", "") => bail!("OpenCode version probe returned no output"),
        (stdout, "") => stdout.to_string(),
        ("", stderr) => stderr.to_string(),
        (stdout, stderr) => format!("{stdout}\n{stderr}"),
    };
    let dialect = OpenCodeDialect::parse_version_output(&output).with_context(|| {
        format!(
            "could not determine the OpenCode major from `{}` --version output {:?}; expected a semantic version with major 1 or 2",
            resolved.display(),
            output.trim()
        )
    })?;
    Ok(ResolvedOpenCode { dialect, executable: resolved })
}

fn spawn_retrying_busy(command: &mut Command) -> std::io::Result<std::process::Child> {
    const ATTEMPTS: u32 = 5;
    let mut attempt = 1;
    loop {
        match command.spawn() {
            Err(error) if error.kind() == std::io::ErrorKind::ExecutableFileBusy && attempt < ATTEMPTS => {
                attempt += 1;
                thread::sleep(Duration::from_millis(20));
            }
            result => return result,
        }
    }
}

fn timeout_error(program: &std::path::Path, timeout: Duration) -> anyhow::Error {
    anyhow!(
        "OpenCode version probe timed out after {} seconds for {}; run `{} --version` and verify it exits promptly",
        timeout.as_secs_f64(),
        program.display(),
        program.display()
    )
}

fn read_bounded(pipe: Option<impl Read + Send + 'static>) -> mpsc::Receiver<std::io::Result<Vec<u8>>> {
    let (sender, receiver) = mpsc::channel();
    thread::spawn(move || {
        let result = (|| {
            let mut bytes = Vec::new();
            if let Some(pipe) = pipe {
                pipe.take(MAX_VERSION_OUTPUT + 1).read_to_end(&mut bytes)?;
            }
            Ok(bytes)
        })();
        let _ = sender.send(result);
    });
    receiver
}
