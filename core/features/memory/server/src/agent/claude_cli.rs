//! One `claude -p` run, exactly as the proof script ran it (2026-11-16,
//! ADR 0029 "prova antes"):
//!
//! ```text
//! claude -p --model <model> --max-budget-usd <call budget> --no-session-persistence
//!   --tools "" --strict-mcp-config --mcp-config <dir>/mcp.json
//!   --settings <dir>/settings.json --system-prompt <system> --output-format json
//! ```
//!
//! - the prompt on stdin, the working folder an empty temporary folder (no
//!   project files, no CLAUDE.md, nothing to read);
//! - mcp.json is `{"mcpServers":{}}` and settings.json `{"disableAllHooks":true}`:
//!   no tool, no MCP server, no hook (the kit's memory hook would record the
//!   agent's own run as a session);
//! - never `--bare`: it skips the keychain, where the subscription login lives;
//! - the environment inherited minus `CLAUDECODE` and every `CLAUDE_CODE_*`
//!   (the engine was started from inside a session and carries them), and
//!   `CLAUDE_CONFIG_DIR` set to the project's account, or removed for the
//!   default account.
//!
//! No address of any provider appears here: the packaging check refuses
//! one in the binary (core/features/memory/CLAUDE.md).

use std::path::{Path, PathBuf};
use std::process::Stdio;
use std::time::Duration;

use ai_memory_llm::LlmError;
use serde::Deserialize;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::process::Command;

/// What a run needs besides the prompt.
#[derive(Debug, Clone)]
pub(crate) struct Invocation {
    pub(crate) exe: PathBuf,
    pub(crate) model: String,
    pub(crate) call_budget_usd: f64,
    /// `CLAUDE_CONFIG_DIR`; `None` for the default account.
    pub(crate) account: Option<PathBuf>,
    pub(crate) timeout: Duration,
}

/// What `--output-format json` printed that the engine uses.
#[derive(Debug, Default, Deserialize)]
pub(crate) struct Output {
    #[serde(default)]
    pub(crate) result: String,
    #[serde(default)]
    pub(crate) total_cost_usd: f64,
    #[serde(default)]
    pub(crate) is_error: bool,
    #[serde(default)]
    pub(crate) subtype: Option<String>,
    #[serde(default, rename = "modelUsage")]
    pub(crate) model_usage: serde_json::Map<String, serde_json::Value>,
    #[serde(default)]
    pub(crate) usage: Option<Usage>,
}

#[derive(Debug, Default, Deserialize)]
pub(crate) struct Usage {
    #[serde(default)]
    pub(crate) input_tokens: u32,
    #[serde(default)]
    pub(crate) output_tokens: u32,
}

/// Output larger than this is not an answer the engine can use.
const OUTPUT_CAP: usize = 8 * 1024 * 1024;

/// The arguments after the executable.
pub(crate) fn argv(inv: &Invocation, dir: &Path, system: &str) -> Vec<String> {
    let path = |name: &str| dir.join(name).to_string_lossy().into_owned();
    vec![
        "-p".into(),
        "--model".into(),
        inv.model.clone(),
        "--max-budget-usd".into(),
        format!("{:.4}", inv.call_budget_usd),
        "--no-session-persistence".into(),
        "--tools".into(),
        String::new(),
        "--strict-mcp-config".into(),
        "--mcp-config".into(),
        path("mcp.json"),
        "--settings".into(),
        path("settings.json"),
        "--system-prompt".into(),
        system.into(),
        "--output-format".into(),
        "json".into(),
    ]
}

/// The variables of the engine's environment the child must not inherit.
fn scrubbed(name: &str) -> bool {
    name == "CLAUDECODE" || name.starts_with("CLAUDE_CODE_") || name == "CLAUDE_CONFIG_DIR"
}

/// A command with the scrubbed environment and the account.
pub(crate) fn command(exe: &Path, account: Option<&Path>) -> Command {
    let mut cmd = Command::new(exe);
    for (name, _) in std::env::vars_os() {
        if name.to_str().is_some_and(scrubbed) {
            cmd.env_remove(&name);
        }
    }
    if let Some(dir) = account {
        cmd.env("CLAUDE_CONFIG_DIR", dir);
    }
    cmd.kill_on_drop(true);
    cmd
}

/// The private folder of one run: `work/` (empty, the cwd) and the two
/// configuration files next to it, gone when the value drops.
fn scratch() -> Result<tempfile::TempDir, LlmError> {
    let fail = |e: std::io::Error| LlmError::NotConfigured(format!("memory agent scratch folder: {e}"));
    let dir = tempfile::Builder::new().prefix("cadex-agent-").tempdir().map_err(fail)?;
    std::fs::create_dir(dir.path().join("work")).map_err(fail)?;
    std::fs::write(dir.path().join("mcp.json"), r#"{"mcpServers":{}}"#).map_err(fail)?;
    std::fs::write(dir.path().join("settings.json"), r#"{"disableAllHooks":true}"#).map_err(fail)?;
    Ok(dir)
}

async fn read_capped(mut reader: impl tokio::io::AsyncRead + Unpin) -> Vec<u8> {
    let mut out = Vec::new();
    let mut buf = [0u8; 8192];
    while let Ok(n) = reader.read(&mut buf).await {
        if n == 0 || out.len() + n > OUTPUT_CAP {
            break;
        }
        out.extend_from_slice(&buf[..n]);
    }
    out
}

/// A short, scrubbed excerpt of what the child printed, for an error.
pub(crate) fn excerpt(text: &str) -> String {
    let clean = ai_memory_core::Sanitizer::builtin().scrub(text.trim());
    let mut cut: String = clean.chars().take(200).collect();
    if clean.chars().count() > 200 {
        cut.push('…');
    }
    cut
}

/// What went to and came from one run, for the audit (agent/audit.rs):
/// the arguments (the system prompt in its own field), what the child
/// printed and how it ended. No environment: it holds the account's folder
/// and whatever the engine inherited.
#[derive(Debug, Default)]
pub(crate) struct Exchange {
    pub(crate) argv: Vec<String>,
    pub(crate) stdout: String,
    /// Scrubbed and short (excerpt): it is for "why did it fail", and a
    /// child's stderr may echo anything.
    pub(crate) stderr: String,
    pub(crate) exit: Option<i32>,
    pub(crate) millis: u64,
}

/// The argument that carries the system prompt, as the audit stores it.
const SYSTEM_IN_AUDIT: &str = "<system prompt: see request.system>";

/// Run `claude -p` once with `system` and `prompt` (on stdin): the result
/// and what was exchanged, even when it failed.
pub(crate) async fn run(inv: &Invocation, system: &str, prompt: &str) -> (Result<Output, LlmError>, Exchange) {
    let started = std::time::Instant::now();
    let mut exchange = Exchange::default();
    let result = run_inner(inv, system, prompt, &mut exchange).await;
    exchange.millis = started.elapsed().as_millis() as u64;
    (result, exchange)
}

async fn run_inner(inv: &Invocation, system: &str, prompt: &str, seen: &mut Exchange) -> Result<Output, LlmError> {
    let dir = scratch()?;
    let args = argv(inv, dir.path(), system);
    seen.argv = args.clone();
    if let Some(at) = seen.argv.iter().position(|a| a == "--system-prompt")
        && let Some(value) = seen.argv.get_mut(at + 1)
    {
        *value = SYSTEM_IN_AUDIT.to_owned();
    }
    let mut cmd = command(&inv.exe, inv.account.as_deref());
    cmd.args(args)
        .current_dir(dir.path().join("work"))
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    let mut child = cmd
        .spawn()
        .map_err(|e| LlmError::NotConfigured(format!("cannot start {}: {e}", inv.exe.display())))?;
    let mut stdin = child.stdin.take();
    let stdout = child.stdout.take();
    let stderr = child.stderr.take();
    let input = prompt.as_bytes().to_vec();
    let exchange = async move {
        if let Some(stdin) = stdin.as_mut() {
            let _ = stdin.write_all(&input).await;
            let _ = stdin.shutdown().await;
        }
        drop(stdin);
        let out = async { match stdout { Some(s) => read_capped(s).await, None => Vec::new() } };
        let err = async { match stderr { Some(s) => read_capped(s).await, None => Vec::new() } };
        let (out, err) = tokio::join!(out, err);
        let status = child.wait().await;
        (out, err, status)
    };
    // The child is killed when the future drops (kill_on_drop).
    let (out, err, status) = tokio::time::timeout(inv.timeout, exchange)
        .await
        .map_err(|_| LlmError::UnexpectedShape(format!("claude -p timed out after {} s", inv.timeout.as_secs())))?;
    let stdout = String::from_utf8_lossy(&out);
    let code = status.ok().and_then(|s| s.code());
    seen.stdout = stdout.clone().into_owned();
    seen.stderr = excerpt(&String::from_utf8_lossy(&err));
    seen.exit = code;
    match serde_json::from_str::<Output>(stdout.trim()) {
        Ok(output) => Ok(output),
        Err(_) => {
            let code = code.unwrap_or(-1);
            let said = if stdout.trim().is_empty() { String::from_utf8_lossy(&err).into_owned() } else { stdout.into_owned() };
            Err(LlmError::UnexpectedShape(format!("claude -p exited {code} without a JSON result: {}", excerpt(&said))))
        }
    }
}

/// The error a result marked `is_error` stands for. Rate limits and an
/// overloaded service may pass (upstream retries those briefly); a spent
/// call budget, a missing login and anything else would fail again.
pub(crate) fn error_of(output: &Output) -> LlmError {
    let text = output.result.to_ascii_lowercase();
    let subtype = output.subtype.as_deref().unwrap_or("");
    if subtype.contains("budget") {
        return LlmError::UnexpectedShape("claude -p stopped at the call budget (--max-budget-usd)".into());
    }
    if text.contains("/login") || text.contains("not logged in") || text.contains("invalid api key") || text.contains("oauth") {
        return LlmError::Auth("claude -p: the account is not logged in".into());
    }
    let status = if text.contains("overloaded") || text.contains("529") {
        Some(529)
    } else if text.contains("rate limit") || text.contains("429") {
        Some(429)
    } else {
        None
    };
    match status {
        Some(status) => LlmError::Provider { status, body: excerpt(&output.result), retry_after: None },
        None => LlmError::UnexpectedShape(format!("claude -p failed ({subtype}): {}", excerpt(&output.result))),
    }
}

/// `claude --version`, first line, in the same environment as a run.
pub(crate) async fn version(exe: &Path, account: Option<&Path>) -> Option<String> {
    let mut cmd = command(exe, account);
    cmd.arg("--version").stdin(Stdio::null()).stdout(Stdio::piped()).stderr(Stdio::null());
    let out = tokio::time::timeout(Duration::from_secs(20), cmd.output()).await.ok()?.ok()?;
    let text = String::from_utf8_lossy(&out.stdout);
    text.lines().next().map(|l| l.trim().to_string()).filter(|l| !l.is_empty())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_arguments_are_the_proven_ones() {
        let inv = Invocation {
            exe: "/bin/claude".into(),
            model: "haiku".into(),
            call_budget_usd: 0.25,
            account: None,
            timeout: Duration::from_secs(1),
        };
        let args = argv(&inv, Path::new("/t"), "be brief");
        assert_eq!(args.join("|"), "-p|--model|haiku|--max-budget-usd|0.2500|--no-session-persistence|--tools||\
--strict-mcp-config|--mcp-config|/t/mcp.json|--settings|/t/settings.json|--system-prompt|be brief|--output-format|json");
        assert!(!args.iter().any(|a| a == "--bare"));
        assert!(scrubbed("CLAUDECODE") && scrubbed("CLAUDE_CODE_ENTRYPOINT") && !scrubbed("CLAUDE_HOME_X") && !scrubbed("PATH"));
    }

    #[test]
    fn a_budget_stop_and_a_missing_login_are_not_retried() {
        let budget = Output { is_error: true, subtype: Some("error_max_budget_usd".into()), ..Output::default() };
        assert!(!error_of(&budget).is_transient());
        let login = Output { is_error: true, result: "Invalid API key · Please run /login".into(), ..Output::default() };
        assert!(matches!(error_of(&login), LlmError::Auth(_)));
        let busy = Output { is_error: true, result: "API Error: 529 Overloaded".into(), ..Output::default() };
        assert!(error_of(&busy).is_transient());
    }
}
