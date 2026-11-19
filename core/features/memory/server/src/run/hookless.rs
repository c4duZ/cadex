//! Ending the run's own session for a harness with no native session-end
//! hook (Command Code, Kiro, Antigravity), so it does not stay open.
//!
//! Follows `finalize_hookless_session` and its report in ai-memory v3.4.7
//! (fa0ec25; compared at v3.5.0, 411d90d, on 2026-11-19: unchanged), crates/ai-memory-cli/src/commands/run.rs, with the synthetic
//! end of `finalize_session::post_session_end_batch` and
//! `session_end_hook_url` (commands/finalize_session.rs). Changed for Cadex
//! (2026-11-16): upstream first lists the scope's open sessions with
//! `GET /admin/open-sessions` (the admin router of ai-memory-mcp), which
//! the Cadex engine does not mount (engine.rs serves hooks, workstreams and
//! MCP only); so the session-end goes to `/hook/batch` for the run's own
//! session id directly, and an `ignored_end` answer (no such open session)
//! counts as "nothing to finalize". Antigravity's prompt replay from
//! `history.jsonl` (`replay_prompts`) is not ported.

use std::time::Duration;

use ai_memory_core::SessionId;
use anyhow::{Result, anyhow, bail};
use serde::Deserialize;

use super::launch::Run;
use super::plan::display_session_id;

const FINALIZE_TIMEOUT: Duration = Duration::from_secs(30);

#[derive(Deserialize)]
struct Ack {
    accepted: usize,
    #[serde(default)]
    results: Vec<AckResult>,
}

#[derive(Deserialize)]
struct AckResult {
    outcome: String,
}

/// The synthetic session-end; the ids it ended (empty when none was open).
async fn finalize(run: &Run<'_>, session: &SessionId) -> Result<Vec<String>> {
    let cwd = run.repository.cwd.to_string_lossy().into_owned();
    let agent = run.harness.agent_kind();
    let pairs = [("event", "session-end"), ("agent", agent.as_str()), ("cwd", cwd.as_str()),
        ("workspace", run.workspace.as_str()), ("project", run.project.as_str())];
    let url = format!("http://localhost/hook?{}", serde_urlencoded::to_string(pairs)?);
    let items = serde_json::json!([{ "url": url, "body": { "session_id": session.to_string(), "cwd": cwd } }]);
    let ack: Ack = run.prep.client.post_json("/hook/batch", &items).await?;
    match ack.results.first().map(|r| r.outcome.as_str()) {
        Some("ignored_end") => Ok(Vec::new()),
        _ if ack.accepted == 1 => Ok(vec![session.to_string()]),
        _ => bail!("server accepted {} of 1 synthetic session-end events", ack.accepted),
    }
}

/// Finalize the own session of a hookless harness and say what happened.
pub(crate) async fn report(run: &Run<'_>, own_session_id: Option<&str>) {
    let Some(native) = own_session_id else { return };
    if !run.harness.lacks_session_end_hook() {
        return;
    }
    let session = SessionId::from_native(native);
    let finalized = tokio::select! {
        finalized = tokio::time::timeout(FINALIZE_TIMEOUT, finalize(run, &session)) => finalized
            .unwrap_or_else(|_| Err(anyhow!("timed out after {}s", FINALIZE_TIMEOUT.as_secs()))),
        Ok(()) = tokio::signal::ctrl_c() => Err(anyhow!("interrupted")),
    };
    let agent = run.harness.agent_kind().as_str();
    let shown = display_session_id(&session.to_string());
    match finalized {
        Ok(ids) if !ids.is_empty() => eprintln!("ai-memory: finalized the {agent} session {shown}"),
        Ok(_) => {}
        Err(error) => eprintln!("ai-memory: could not finalize the {agent} session {shown} ({error:#}); it stays open"),
    }
}
