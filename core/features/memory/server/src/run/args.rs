//! `cadex-memory run` options, parsed by hand like args.rs (no `clap`), and
//! the environment the kit gives a session: the engine's socket, folders
//! and the session token, read as the Zig hook client reads them
//! (core/features/memory/hook_client.zig). Plan 22 phase E, 2026-11-16.
//!
//! The command line is upstream's `RunArgs` (crates/ai-memory-cli/src/cli.rs
//! at fa0ec25; at v3.5.0, 411d90d, it adds `--or-new`, not brought: `cadex
//! continue` does not use it): wrapper flags before the harness, the native argv after it,
//! untouched (`delimit_run_native_args` puts a `--` right after the harness).
//! Copied: `parse_env_kv`. Cadex's own: `--socket`, `--data-dir`, and the
//! session kit's words per harness (`--claude-kit-arg`, `--codex-kit-arg`).

use std::ffi::OsString;
use std::path::PathBuf;

use anyhow::{Context, Result, anyhow, bail};

use super::choice::{RunHarnessChoice, claude_wrapper_spelling, parse_run_harness_choice};

pub(crate) const USAGE: &str = "usage: cadex-memory run [--socket P] [--data-dir D] [--claude-kit-arg A]... \
[--codex-kit-arg A]... [--workspace W] [--project P | --project-id ID] [--workstream N | --new N] \
[--executable PATH] [--yolo] [--jail[=TOGGLES] | --no-jail] [--jail-map DIR]... [--jail-rw-map DIR]... \
[--fresh] [--force-unlock] [--no-autowire] [--no-exit-prompt] [--require-server] [--profile NAME] \
[--env KEY=VALUE]... [--env-file PATH] [harness] [native args...]";

/// What the launcher was asked for (upstream's `RunArgs`, plus Cadex's).
#[derive(Debug, Clone, Default)]
pub(crate) struct RunArgs {
    pub(crate) socket: Option<PathBuf>,
    pub(crate) data_dir: Option<PathBuf>,
    /// The session kit's flags per harness (`--settings`, `--plugin-dir`,
    /// `--mcp-config`; Codex's `-c mcp_servers...`), appended after the plan
    /// is built so they never confuse native-argv parsing.
    pub(crate) claude_kit_args: Vec<OsString>,
    pub(crate) codex_kit_args: Vec<OsString>,
    pub(crate) workspace: Option<String>,
    pub(crate) project: Option<String>,
    pub(crate) project_id: Option<String>,
    pub(crate) workstream: Option<String>,
    pub(crate) new_workstream: Option<String>,
    pub(crate) executable: Option<PathBuf>,
    pub(crate) yolo: bool,
    pub(crate) true_yolo: bool,
    pub(crate) jail: Option<String>,
    pub(crate) no_jail: bool,
    pub(crate) jail_map: Vec<PathBuf>,
    pub(crate) jail_rw_map: Vec<PathBuf>,
    pub(crate) fresh: bool,
    pub(crate) force_unlock: bool,
    /// Accepted for upstream compatibility and ignored: Cadex never writes
    /// hooks or MCP into an agent's own config (its session kit wires them).
    pub(crate) no_autowire: bool,
    pub(crate) no_exit_prompt: bool,
    pub(crate) require_server: bool,
    pub(crate) profile: Option<String>,
    pub(crate) env: Vec<(String, String)>,
    pub(crate) env_file: Option<PathBuf>,
    pub(crate) harness: Option<RunHarnessChoice>,
    /// The typed `claude*` spelling when it names a wrapper (`claude-corp`).
    pub(crate) claude_wrapper: Option<String>,
    pub(crate) native_args: Vec<OsString>,
}

/// Upstream's `parse_env_kv` (cli.rs): `KEY=VALUE`, the value literal.
pub(crate) fn parse_env_kv(value: &str) -> Result<(String, String), String> {
    let Some((key, value)) = value.split_once('=') else {
        return Err(format!("invalid value '{value}' for --env; expected KEY=VALUE"));
    };
    if key.is_empty() {
        return Err(format!("invalid value '{key}={value}' for --env; KEY must not be empty"));
    }
    if key.chars().any(char::is_whitespace) {
        return Err(format!("invalid value '{key}={value}' for --env; KEY must not contain whitespace"));
    }
    Ok((key.to_string(), value.to_string()))
}

fn utf8(value: OsString, name: &str) -> Result<String> {
    value.into_string().map_err(|_| anyhow!("{name}: not UTF-8"))
}

/// One wrapper option (`--name` with its value, inline after `=` or next).
fn apply_option(args: &mut RunArgs, name: &str, inline: Option<OsString>, it: &mut impl Iterator<Item = OsString>)
    -> Result<()> {
    let mut value = |inline: Option<OsString>| -> Result<OsString> {
        inline.or_else(|| it.next()).with_context(|| format!("{name} needs a value"))
    };
    match name {
        "--socket" => args.socket = Some(PathBuf::from(value(inline)?)),
        "--data-dir" => args.data_dir = Some(PathBuf::from(value(inline)?)),
        "--claude-kit-arg" => args.claude_kit_args.push(value(inline)?),
        "--codex-kit-arg" => args.codex_kit_args.push(value(inline)?),
        "--workspace" => args.workspace = Some(utf8(value(inline)?, name)?),
        "--project" => args.project = Some(utf8(value(inline)?, name)?),
        "--project-id" => args.project_id = Some(utf8(value(inline)?, name)?),
        "--workstream" => args.workstream = Some(utf8(value(inline)?, name)?),
        "--new" | "--new-workstream" => args.new_workstream = Some(utf8(value(inline)?, name)?),
        "--executable" => args.executable = Some(PathBuf::from(value(inline)?)),
        "--jail-map" => args.jail_map.push(PathBuf::from(value(inline)?)),
        "--jail-rw-map" => args.jail_rw_map.push(PathBuf::from(value(inline)?)),
        "--profile" => args.profile = Some(utf8(value(inline)?, name)?),
        "--env" => args.env.push(parse_env_kv(&utf8(value(inline)?, name)?).map_err(|e| anyhow!(e))?),
        "--env-file" => args.env_file = Some(PathBuf::from(value(inline)?)),
        // `require_equals`: a bare `--jail` is the smart defaults.
        "--jail" => args.jail = Some(inline.map(|v| utf8(v, name)).transpose()?.unwrap_or_default()),
        _ => {
            if inline.is_some() {
                bail!("unexpected value for {name}; {USAGE}");
            }
            let flag = match name {
                "--yolo" => &mut args.yolo,
                "--true-yolo" => &mut args.true_yolo,
                "--no-jail" => &mut args.no_jail,
                "--fresh" => &mut args.fresh,
                "--force-unlock" => &mut args.force_unlock,
                "--no-autowire" => &mut args.no_autowire,
                "--no-exit-prompt" => &mut args.no_exit_prompt,
                "--require-server" => &mut args.require_server,
                _ => bail!("unknown argument {name}; {USAGE}"),
            };
            *flag = true;
        }
    }
    Ok(())
}

/// The pairs clap declares `conflicts_with`.
fn check_conflicts(args: &RunArgs) -> Result<()> {
    if args.project.is_some() && args.project_id.is_some() {
        bail!("the argument '--project <PROJECT>' cannot be used with '--project-id <PROJECT_ID>'");
    }
    if args.workstream.is_some() && args.new_workstream.is_some() {
        bail!("the argument '--workstream <WORKSTREAM>' cannot be used with '--new <NEW_WORKSTREAM>'");
    }
    if args.jail.is_some() && args.no_jail {
        bail!("the argument '--jail[=<TOGGLES>]' cannot be used with '--no-jail'");
    }
    Ok(())
}

/// Parse the arguments after `run`.
pub(crate) fn parse(argv: &[OsString]) -> Result<RunArgs> {
    let mut args = RunArgs::default();
    let mut it = argv.iter().cloned();
    while let Some(arg) = it.next() {
        let text = arg.to_str().map(str::to_owned);
        match text.as_deref() {
            Some("--") => {
                if let Some(next) = it.next() {
                    set_harness(&mut args, &next)?;
                }
                break;
            }
            Some(flag) if flag.starts_with("--") => match flag.split_once('=') {
                Some((name, inline)) => apply_option(&mut args, name, Some(OsString::from(inline)), &mut it)?,
                None => apply_option(&mut args, flag, None, &mut it)?,
            },
            Some(flag) if flag.starts_with('-') && flag.len() > 1 => bail!("unknown argument {flag}; {USAGE}"),
            _ => {
                set_harness(&mut args, &arg)?;
                break;
            }
        }
    }
    args.native_args = it.collect();
    check_conflicts(&args)?;
    Ok(args)
}

fn set_harness(args: &mut RunArgs, raw: &OsString) -> Result<()> {
    let value = raw.to_str().ok_or_else(|| anyhow!("harness: not UTF-8"))?;
    args.harness = Some(parse_run_harness_choice(value).map_err(|e| anyhow!(e))?);
    args.claude_wrapper = claude_wrapper_spelling(value).map(str::to_owned);
    Ok(())
}

/// Where the engine is and who this session is.
#[derive(Debug, Clone)]
pub(crate) struct Env {
    pub(crate) socket: PathBuf,
    pub(crate) data_dir: PathBuf,
    /// Passed to an engine this launcher starts only when the kit names one.
    pub(crate) tokens_dir: Option<PathBuf>,
    pub(crate) token: String,
    /// The account's workspace (memory not shared across accounts).
    pub(crate) workspace: Option<String>,
    pub(crate) home: PathBuf,
}

impl Env {
    /// Cadex's own launcher state (session stores, recovery journal, jail
    /// answers): never upstream's ai-memory folders.
    pub(crate) fn run_dir(&self) -> PathBuf {
        self.data_dir.join("run")
    }
}

fn var(name: &str) -> Option<String> {
    std::env::var(name).ok().filter(|v| !v.trim().is_empty())
}

/// The environment, with the flags over it.
pub(crate) fn env(args: &RunArgs) -> Result<Env> {
    let Some(token) = var("CADEX_SESSION_TOKEN") else {
        bail!("CADEX_SESSION_TOKEN is not set: `cadex-memory run` works only in a session Cadex opened");
    };
    let home = PathBuf::from(var("HOME").context("HOME is not set")?);
    let support = home.join("Library/Application Support/Cadex");
    let socket = args.socket.clone().or_else(|| var("CADEX_MEMORY_SOCKET").map(PathBuf::from))
        .unwrap_or_else(|| support.join("sockets/memory.sock"));
    let data_dir = args.data_dir.clone().or_else(|| var("CADEX_MEMORY_DIR").map(PathBuf::from))
        .unwrap_or_else(|| support.join("memory"));
    let absolute = |path: PathBuf| std::path::absolute(&path).unwrap_or(path);
    Ok(Env {
        socket: absolute(socket),
        data_dir: absolute(data_dir),
        tokens_dir: var("CADEX_SESSIONS_DIR").map(PathBuf::from),
        token,
        workspace: var("CADEX_MEMORY_WORKSPACE"),
        home,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn os(args: &[&str]) -> Vec<OsString> {
        args.iter().map(OsString::from).collect()
    }

    #[test]
    fn wrapper_flags_come_before_the_harness_and_its_arguments_pass_untouched() {
        let parsed = parse(&os(&["--claude-kit-arg", "--settings", "--claude-kit-arg=/k.json", "--codex-kit-arg", "-c",
            "--workstream", "w", "--jail", "--env", "A=b=c", "claude-corp", "--model", "x", "--fresh"])).unwrap();
        assert_eq!(parsed.harness, Some(RunHarnessChoice::Claude));
        assert_eq!(parsed.claude_wrapper.as_deref(), Some("claude-corp"));
        assert_eq!(parsed.claude_kit_args, os(&["--settings", "/k.json"]));
        assert_eq!(parsed.codex_kit_args, os(&["-c"]));
        assert_eq!(parsed.native_args, os(&["--model", "x", "--fresh"]));
        assert_eq!(parsed.jail.as_deref(), Some(""));
        assert_eq!(parsed.env, [("A".to_owned(), "b=c".to_owned())]);
        assert_eq!(parsed.workstream.as_deref(), Some("w"));
        assert_eq!(parse(&os(&["--jail=github,no-ssh", "codex"])).unwrap().jail.as_deref(), Some("github,no-ssh"));
        assert_eq!(parse(&os(&["--new-workstream", "n"])).unwrap().new_workstream.as_deref(), Some("n"));
        assert!(parse(&os(&["--yolo"])).unwrap().harness.is_none());
        assert!(parse(&os(&["vim"])).is_err());
        assert!(parse(&os(&["--workstream", "a", "--new", "b", "codex"])).is_err());
        assert!(parse(&os(&["--jail", "--no-jail", "codex"])).is_err());
        assert!(parse(&os(&["--env", "A B=c", "codex"])).is_err());
    }
}
