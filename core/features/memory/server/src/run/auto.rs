//! The automatic harness (`cadex-memory run` with no harness name): the
//! newest checkout-local session among the installed harnesses, then the
//! engine's `resolved_agent` precedence; and Kiro's engine (v2 or v3).
//!
//! Copied from ai-memory v3.4.7 (fa0ec25; compared at v3.5.0, 411d90d, on 2026-11-19: unchanged), crates/ai-memory-cli/src/commands/
//! run.rs: `AUTO_HARNESSES`, `AutoSessionCandidate`, `list_auto_sessions`,
//! `unique_auto_agents`, `automatic_harness_flavor`,
//! `filter_usable_auto_sessions`, `no_auto_session_error` and
//! `resolve_kiro_harness`. Changed for Cadex (2026-11-16): no i18n.

use std::ffi::{OsStr, OsString};
use std::path::Path;

use ai_memory_core::AgentKind;
use ai_memory_workstream::{
    ManagedHarness, NativeSessionCandidate, build_launch_plan, kiro_explicit_session_id, kiro_harness_from_source_cursor,
    kiro_selects_non_default_engine, kiro_selects_v2_engine, kiro_selects_v3_engine, list_native_sessions,
    native_session_exists,
};
use anyhow::{Result, anyhow};

use super::child_env::{EffectiveChildEnv, executable_available};
use super::opencode::ResolvedOpenCode;
use super::plan::{auto_session_dir, display_session_id};

const AUTO_HARNESSES: [ManagedHarness; 9] = [
    ManagedHarness::Claude,
    ManagedHarness::Codex,
    ManagedHarness::OpenCode,
    ManagedHarness::Pi,
    ManagedHarness::Crush,
    ManagedHarness::Kimi,
    ManagedHarness::CommandCode,
    ManagedHarness::Kiro,
    ManagedHarness::KiroV3,
];

#[derive(Debug, Clone)]
pub(crate) struct AutoSessionCandidate {
    pub(crate) harness: ManagedHarness,
    pub(crate) session: NativeSessionCandidate,
}

/// The newest session of each automatic harness in this checkout, newest
/// first, each read from the store the launch would resume from.
pub(crate) async fn list_auto_sessions(home: &Path, cwd: &Path, env: &EffectiveChildEnv,
    opencode_harness: Option<ManagedHarness>) -> Result<Vec<AutoSessionCandidate>> {
    let mut found = Vec::new();
    let mut failures = Vec::new();
    for mut harness in AUTO_HARNESSES {
        if harness == ManagedHarness::OpenCode {
            let Some(resolved) = opencode_harness else { continue };
            harness = resolved;
        }
        let session_dir = match auto_session_dir(harness, home, cwd, env) {
            Ok(session_dir) => session_dir,
            Err(error) => {
                failures.push(format!("{}: {error}", harness.as_str()));
                continue;
            }
        };
        match list_native_sessions(harness, home, cwd, session_dir.as_deref(), 1).await {
            Ok(candidates) => found.extend(candidates.into_iter().map(|session| AutoSessionCandidate { harness, session })),
            Err(error) => failures.push(format!("{}: {error}", harness.as_str())),
        }
    }
    if found.is_empty() && !failures.is_empty() {
        return Err(anyhow!("could not inspect checkout-local sessions: {}", failures.join("; ")));
    }
    for failure in failures {
        eprintln!("ai-memory: session scan skipped {failure}");
    }
    found.sort_by(|left, right| {
        right.session.updated_at.cmp(&left.session.updated_at).then_with(|| left.harness.as_str().cmp(right.harness.as_str()))
    });
    Ok(found)
}

/// The candidates whose harness is installed (OpenCode counts when its
/// dialect resolved).
pub(crate) fn usable_auto_sessions(candidates: Vec<AutoSessionCandidate>, opencode: Option<&ResolvedOpenCode>,
    env: &EffectiveChildEnv) -> Result<Vec<AutoSessionCandidate>> {
    let search = env.executable_search();
    filter_usable_auto_sessions(candidates, |harness| {
        matches!(harness, ManagedHarness::OpenCode | ManagedHarness::OpenCode2) && opencode.is_some()
            || executable_available(OsStr::new(harness.executable()), search)
    })
}

pub(crate) fn filter_usable_auto_sessions(candidates: Vec<AutoSessionCandidate>, available: impl Fn(ManagedHarness) -> bool)
    -> Result<Vec<AutoSessionCandidate>> {
    let mut missing = Vec::new();
    let usable = candidates
        .into_iter()
        .filter(|candidate| {
            if available(candidate.harness) {
                true
            } else {
                missing.push(candidate.harness.executable());
                false
            }
        })
        .collect::<Vec<_>>();
    if usable.is_empty() && !missing.is_empty() {
        missing.sort_unstable();
        missing.dedup();
        return Err(anyhow!(
            "checkout-local sessions were found, but their harness executables are not available in the host PATH: {}",
            missing.join(", ")
        ));
    }
    Ok(usable)
}

pub(crate) fn unique_auto_agents(candidates: &[AutoSessionCandidate]) -> Vec<AgentKind> {
    let mut agents = Vec::new();
    for candidate in candidates {
        let agent = candidate.harness.agent_kind();
        if !agents.contains(&agent) {
            agents.push(agent);
        }
    }
    agents
}

pub(crate) fn automatic_harness_flavor(selected: ManagedHarness, provisional: ManagedHarness,
    linked_session_id: Option<&str>, opencode_harness: Option<ManagedHarness>) -> ManagedHarness {
    if selected == ManagedHarness::Kiro && provisional.agent_kind() == AgentKind::KiroCli && linked_session_id.is_none() {
        provisional
    } else if selected == ManagedHarness::OpenCode {
        opencode_harness.unwrap_or(selected)
    } else {
        selected
    }
}

pub(crate) fn no_auto_session_error() -> anyhow::Error {
    anyhow!(
        "no Claude Code, Codex, OpenCode, Pi, Crush, Kimi Code, Command Code, or Kiro CLI session was found for this directory; start one explicitly with `ai-memory run claude`, `ai-memory run codex`, `ai-memory run opencode`, `ai-memory run pi`, `ai-memory run crush`, `ai-memory run kimi`, `ai-memory run command-code`, or `ai-memory run kiro`"
    )
}

/// Kiro's engine: an explicit selector, else the store that holds the
/// session, else the workstream's prior cursor, else `fallback`.
pub(crate) fn resolve_kiro_harness(native_args: &[OsString], linked_session_id: Option<&str>, source_cursor: Option<&str>,
    fallback: ManagedHarness, home: &Path, cwd: &Path) -> Result<ManagedHarness> {
    if kiro_selects_v3_engine(native_args) {
        return Ok(ManagedHarness::KiroV3);
    }
    if kiro_selects_v2_engine(native_args) || kiro_selects_non_default_engine(native_args) {
        return Ok(ManagedHarness::Kiro);
    }
    let explicit_session_id = kiro_explicit_session_id(native_args);
    if let Some(session_id) = explicit_session_id.as_deref().or(linked_session_id) {
        let mut found = Vec::new();
        for harness in [ManagedHarness::Kiro, ManagedHarness::KiroV3] {
            let probe = build_launch_plan(harness, None, Vec::new(), None)?;
            if native_session_exists(harness, home, cwd, probe.session_dir.as_deref(), session_id)? {
                found.push(harness);
            }
        }
        match found.as_slice() {
            [harness] => return Ok(*harness),
            [_, _] => {
                return Err(anyhow!(
                    "Kiro session {} exists in both incompatible engine stores; use --fresh with an explicit --agent-engine v2 or --v3",
                    display_session_id(session_id)
                ));
            }
            _ => {}
        }
    }
    if explicit_session_id.is_some() {
        return Ok(ManagedHarness::Kiro);
    }
    if let Some(harness) = source_cursor.and_then(kiro_harness_from_source_cursor) {
        return Ok(harness);
    }
    Ok(fallback)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{Duration, SystemTime};

    fn candidate(harness: ManagedHarness, age: u64) -> AutoSessionCandidate {
        let updated_at = SystemTime::UNIX_EPOCH + Duration::from_secs(1_000_000 - age);
        AutoSessionCandidate { harness, session: NativeSessionCandidate { native_session_id: "s".into(), updated_at } }
    }

    #[test]
    fn missing_executables_are_skipped_and_named_when_nothing_is_left() {
        let both = vec![candidate(ManagedHarness::Codex, 1), candidate(ManagedHarness::Claude, 5)];
        let usable = filter_usable_auto_sessions(both.clone(), |h| h == ManagedHarness::Claude).unwrap();
        assert_eq!(usable.len(), 1);
        assert_eq!(usable[0].harness, ManagedHarness::Claude);
        let error = filter_usable_auto_sessions(both, |_| false).unwrap_err().to_string();
        assert!(error.ends_with("claude, codex"), "{error}");
        assert_eq!(unique_auto_agents(&usable), [AgentKind::ClaudeCode]);
        assert_eq!(automatic_harness_flavor(ManagedHarness::Kiro, ManagedHarness::KiroV3, None, None), ManagedHarness::KiroV3);
        assert_eq!(automatic_harness_flavor(ManagedHarness::OpenCode, ManagedHarness::Claude, None,
            Some(ManagedHarness::OpenCode2)), ManagedHarness::OpenCode2);
    }

    #[test]
    fn kiro_engine_flags_win_over_the_cursor() {
        let tmp = tempfile::tempdir().unwrap();
        let home = tmp.path();
        assert_eq!(resolve_kiro_harness(&["--v3".into()], None, None, ManagedHarness::Kiro, home, home).unwrap(),
            ManagedHarness::KiroV3);
        assert_eq!(resolve_kiro_harness(&["--agent-engine".into(), "v2".into()], None, None, ManagedHarness::KiroV3, home,
            home).unwrap(), ManagedHarness::Kiro);
        assert_eq!(resolve_kiro_harness(&[], None, None, ManagedHarness::KiroV3, home, home).unwrap(), ManagedHarness::KiroV3);
    }
}
