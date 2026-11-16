//! Adopting a native session the workstream does not link yet: the
//! interactive picker (the newest by default, 0 for a new one) while the
//! lease keeps beating, and the hint naming the selector that resumes the
//! checkout's newest session when the linked one is gone.
//!
//! Copied from ai-memory v3.4.7 (fa0ec25), crates/ai-memory-cli/src/commands/
//! run.rs: `choose_native_session_interactive`,
//! `wait_for_native_session_choice`, `choose_native_session`, `session_age`,
//! `orphan_resume_hint`, `run_harness_name`, `resume_selector` and the
//! constant `ADOPTION_CANDIDATE_LIMIT`; `humanize_age_secs` from
//! commands/mod.rs. Changed for Cadex (2026-11-16): no i18n.

use std::io;
use std::time::SystemTime;

use ai_memory_workstream::{ManagedHarness, NativeSessionCandidate, build_launch_plan};
use anyhow::{Context, Result, anyhow};
use tokio_util::sync::CancellationToken;

use super::plan::display_session_id;
use super::server::{self, HEARTBEAT_INTERVAL, HeartbeatHealth};
use super::uds_http::Client;

pub(crate) const ADOPTION_CANDIDATE_LIMIT: usize = 8;

/// Ask on the terminal which session to continue; the lease is renewed
/// while the user reads, and once more after the answer.
pub(crate) async fn choose_native_session_interactive(harness: ManagedHarness, workstream_name: String,
    candidates: Vec<NativeSessionCandidate>, client: &Client, run_path: &str, interrupted: &CancellationToken)
    -> Result<io::Result<Option<String>>> {
    let chooser = tokio::task::spawn_blocking(move || {
        let stdin = io::stdin();
        choose_native_session(harness, &workstream_name, &candidates, &mut stdin.lock(), &mut io::stderr(), SystemTime::now())
    });
    wait_for_native_session_choice(chooser, client, run_path, interrupted).await
}

async fn wait_for_native_session_choice(mut chooser: tokio::task::JoinHandle<io::Result<Option<String>>>, client: &Client,
    run_path: &str, interrupted: &CancellationToken) -> Result<io::Result<Option<String>>> {
    tokio::select! {
        biased;
        _ = interrupted.cancelled() => {
            chooser.abort();
            Err(anyhow!("managed run interrupted before the agent started"))
        }
        result = async {
            let mut heartbeat = tokio::time::interval(HEARTBEAT_INTERVAL);
            heartbeat.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
            heartbeat.tick().await;
            let mut health = HeartbeatHealth::default();
            let selection = loop {
                tokio::select! {
                    result = &mut chooser => break result.context("waiting for the native session choice")?,
                    _ = heartbeat.tick() => server::send_heartbeat(client, run_path, &mut health).await,
                }
            };
            server::post_heartbeat(client, run_path)
                .await
                .context("renewing the managed workstream after session selection; the agent was not started")?;
            Ok(selection)
        } => result,
    }
}

/// The picker itself, on injected input and output.
pub(crate) fn choose_native_session(harness: ManagedHarness, workstream_name: &str, candidates: &[NativeSessionCandidate],
    input: &mut impl io::BufRead, output: &mut impl io::Write, now: SystemTime) -> io::Result<Option<String>> {
    writeln!(output, "ai-memory: no {} session is linked to workstream '{}'.", harness.as_str(),
        super::terminal_text(workstream_name))?;
    writeln!(output, "Previous sessions for this checkout:")?;
    for (index, candidate) in candidates.iter().enumerate() {
        writeln!(output, "  {}) {} (updated {})", index + 1, display_session_id(&candidate.native_session_id),
            session_age(candidate.updated_at, now))?;
    }
    writeln!(output, "  0) Start a new {} session", harness.as_str())?;
    loop {
        write!(output, "Select [1]: ")?;
        output.flush()?;
        let mut line = String::new();
        if input.read_line(&mut line)? == 0 {
            writeln!(output)?;
            return Ok(None);
        }
        let choice = line.trim();
        if choice.is_empty() {
            return Ok(Some(candidates[0].native_session_id.clone()));
        }
        if matches!(choice.to_ascii_lowercase().as_str(), "0" | "n" | "new") {
            return Ok(None);
        }
        if let Ok(index) = choice.parse::<usize>()
            && let Some(candidate) = index.checked_sub(1).and_then(|i| candidates.get(i))
        {
            return Ok(Some(candidate.native_session_id.clone()));
        }
        writeln!(output, "Enter 0 through {}.", candidates.len())?;
    }
}

pub(crate) fn humanize_age_secs(seconds: i64) -> String {
    let seconds = seconds.max(0);
    if seconds < 60 {
        return "just now".to_owned();
    }
    let (value, unit) = match seconds {
        v if v < 3_600 => (v / 60, "minute"),
        v if v < 86_400 => (v / 3_600, "hour"),
        v if v < 2_592_000 => (v / 86_400, "day"),
        v => (v / 2_592_000, "month"),
    };
    format!("{value} {unit}{} ago", if value == 1 { "" } else { "s" })
}

fn session_age(updated_at: SystemTime, now: SystemTime) -> String {
    let secs = now.duration_since(updated_at).unwrap_or_default().as_secs();
    humanize_age_secs(i64::try_from(secs).unwrap_or(i64::MAX))
}

/// The newest other session of the harness and the selector that resumes it.
pub(crate) fn orphan_resume_hint(harness: ManagedHarness, orphaned_session: &str,
    sessions: Result<Vec<NativeSessionCandidate>>, now: SystemTime) -> Option<String> {
    let sessions = match sessions {
        Ok(sessions) => sessions,
        Err(error) => {
            return Some(format!("ai-memory: could not list this checkout's other {} sessions ({error:#})", harness.as_str()));
        }
    };
    let newest = sessions.into_iter().next().filter(|candidate| candidate.native_session_id != orphaned_session)?;
    let found = format!(
        "ai-memory: this checkout's newest {} session is {} (updated {})",
        harness.as_str(),
        display_session_id(&newest.native_session_id),
        session_age(newest.updated_at, now)
    );
    Some(match resume_selector(harness, &newest.native_session_id) {
        Some(selector) => format!(
            "{found}; to continue it instead, stop this fresh session and run the same command again with `{selector}` right after `{}`",
            run_harness_name(harness)
        ),
        None => format!("{found}; to continue it instead, stop this fresh session and resume that one by its id"),
    })
}

fn run_harness_name(harness: ManagedHarness) -> &'static str {
    match harness {
        ManagedHarness::KiroV3 => ManagedHarness::Kiro.as_str(),
        other => other.as_str(),
    }
}

fn resume_selector(harness: ManagedHarness, id: &str) -> Option<String> {
    if display_session_id(id) != id {
        return None;
    }
    build_launch_plan(harness, None, Vec::new(), Some(id))
        .ok()?
        .args
        .iter()
        .filter(|arg| !(harness == ManagedHarness::KiroV3 && *arg == "--v3"))
        .map(|arg| {
            let arg = arg.to_str()?;
            let shown = match arg.strip_suffix(id) {
                Some(flag) if flag.is_empty() || flag.ends_with('=') => format!("{flag}{}", display_session_id(id)),
                _ => arg.to_owned(),
            };
            shown.chars().all(|c| c.is_ascii_alphanumeric() || "-_.=:/@+,".contains(c)).then_some(shown)
        })
        .collect::<Option<Vec<_>>>()
        .map(|words| words.join(" "))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;

    fn candidates(now: SystemTime) -> Vec<NativeSessionCandidate> {
        ["11111111-1111-4111-8111-111111111111", "22222222-2222-4222-8222-222222222222"]
            .iter()
            .enumerate()
            .map(|(i, id)| NativeSessionCandidate {
                native_session_id: (*id).into(),
                updated_at: now - Duration::from_secs(120 * (i as u64 + 1)),
            })
            .collect()
    }

    fn pick(input: &str) -> (Option<String>, String) {
        let now = SystemTime::now();
        let mut output = Vec::new();
        let chosen = choose_native_session(ManagedHarness::Claude, "main", &candidates(now), &mut input.as_bytes(), &mut output, now)
            .unwrap();
        (chosen, String::from_utf8(output).unwrap())
    }

    #[test]
    fn enter_adopts_the_newest_zero_starts_fresh_and_bad_input_asks_again() {
        let (chosen, text) = pick("\n");
        assert_eq!(chosen.as_deref(), Some("11111111-1111-4111-8111-111111111111"));
        assert!(text.contains("1) 11111111-1111-4111-8111-111111111111 (updated 2 minutes ago)"), "{text}");
        assert_eq!(pick("0\n").0, None);
        let (chosen, text) = pick("9\n2\n");
        assert_eq!(chosen.as_deref(), Some("22222222-2222-4222-8222-222222222222"));
        assert!(text.contains("Enter 0 through 2."));
        assert_eq!(pick("").0, None);
    }

    #[test]
    fn the_orphan_hint_names_the_native_selector() {
        let now = SystemTime::now();
        let hint = orphan_resume_hint(ManagedHarness::Claude, "gone", Ok(candidates(now)), now).unwrap();
        assert!(hint.contains("`--resume 11111111-1111-4111-8111-111111111111` right after `claude`"), "{hint}");
        assert_eq!(humanize_age_secs(86_400 * 40), "1 month ago");
    }
}
