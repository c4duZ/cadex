//! The harness names `cadex-memory run` takes and the managed harness each
//! one launches.
//!
//! Copied from ai-memory v3.4.7 (fa0ec25; compared at v3.5.0, 411d90d, on 2026-11-19: unchanged): `RunHarnessChoice` with its clap
//! names and aliases, `parse_run_harness_choice` and
//! `claude_wrapper_spelling` (crates/ai-memory-cli/src/cli.rs), and
//! `managed_harness`, `run_harness_choice`, `managed_harness_for_args`,
//! `managed_harness_from_agent` and `harness_from_journal_name`
//! (commands/run.rs). Changed for Cadex (2026-11-16): the clap `ValueEnum`
//! is a table here (the binary has no clap).

use std::ffi::OsString;

use ai_memory_core::AgentKind;
use ai_memory_workstream::{ManagedHarness, kiro_selects_v3_engine};

/// Harnesses supported by managed workstreams, in upstream's declaration
/// order (the order of the post-run switch menu).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum RunHarnessChoice {
    Claude,
    Codex,
    OpenCode,
    OpenCode2,
    Pi,
    Crush,
    Omp,
    Kimi,
    CommandCode,
    Kiro,
    Grok,
    Antigravity,
    Copilot,
}

/// Each choice with its name first, then its aliases.
const NAMES: &[(RunHarnessChoice, &[&str])] = &[
    (RunHarnessChoice::Claude, &["claude", "claude-code"]),
    (RunHarnessChoice::Codex, &["codex"]),
    (RunHarnessChoice::OpenCode, &["opencode", "open-code"]),
    (RunHarnessChoice::OpenCode2, &["opencode2", "opencode-v2", "open-code2"]),
    (RunHarnessChoice::Pi, &["pi"]),
    (RunHarnessChoice::Crush, &["crush"]),
    (RunHarnessChoice::Omp, &["omp", "oh-my-pi"]),
    (RunHarnessChoice::Kimi, &["kimi", "kimi-code", "kimi-cli"]),
    (RunHarnessChoice::CommandCode, &["command-code", "commandcode", "cmdc", "cmd"]),
    (RunHarnessChoice::Kiro, &["kiro", "kiro-cli"]),
    (RunHarnessChoice::Grok, &["grok", "grok-build"]),
    (RunHarnessChoice::Antigravity, &["antigravity", "antigravity-cli", "agy"]),
    (RunHarnessChoice::Copilot, &["copilot", "copilot-cli"]),
];

impl RunHarnessChoice {
    /// Every choice, in declaration order (clap's `value_variants`).
    pub(crate) fn all() -> impl Iterator<Item = Self> {
        NAMES.iter().map(|(choice, _)| *choice)
    }

    /// The name clap prints for it (upstream's `show::harness_name`).
    pub(crate) fn name(self) -> &'static str {
        NAMES.iter().find(|(choice, _)| *choice == self).map_or("unknown", |(_, names)| names[0])
    }

    /// clap's `ValueEnum::from_str(value, true)`: a name or alias, any case.
    fn from_name(value: &str) -> Option<Self> {
        NAMES.iter().find(|(_, names)| names.iter().any(|n| n.eq_ignore_ascii_case(value))).map(|(c, _)| *c)
    }
}

/// Upstream's `parse_run_harness_choice`: a known name, else any longer
/// `claude*` spelling is Claude (an account wrapper such as `claude-corp`).
pub(crate) fn parse_run_harness_choice(value: &str) -> Result<RunHarnessChoice, String> {
    if let Some(choice) = RunHarnessChoice::from_name(value) {
        return Ok(choice);
    }
    if value.len() > "claude".len() && value.to_ascii_lowercase().starts_with("claude") {
        return Ok(RunHarnessChoice::Claude);
    }
    let known = NAMES.iter().map(|(_, names)| names[0]).collect::<Vec<_>>().join(", ");
    Err(format!("invalid value '{value}' for harness; expected one of: {known}, or any `claude*` spelling"))
}

/// The wrapper name behind a `claude*` spelling; `None` for the fixed names.
pub(crate) fn claude_wrapper_spelling(value: &str) -> Option<&str> {
    (RunHarnessChoice::from_name(value).is_none() && parse_run_harness_choice(value) == Ok(RunHarnessChoice::Claude))
        .then_some(value)
}

pub(crate) const fn managed_harness(choice: RunHarnessChoice) -> ManagedHarness {
    match choice {
        RunHarnessChoice::Claude => ManagedHarness::Claude,
        RunHarnessChoice::Codex => ManagedHarness::Codex,
        RunHarnessChoice::OpenCode => ManagedHarness::OpenCode,
        RunHarnessChoice::OpenCode2 => ManagedHarness::OpenCode2,
        RunHarnessChoice::Pi => ManagedHarness::Pi,
        RunHarnessChoice::Crush => ManagedHarness::Crush,
        RunHarnessChoice::Omp => ManagedHarness::Omp,
        RunHarnessChoice::Kimi => ManagedHarness::Kimi,
        RunHarnessChoice::CommandCode => ManagedHarness::CommandCode,
        RunHarnessChoice::Kiro => ManagedHarness::Kiro,
        RunHarnessChoice::Grok => ManagedHarness::Grok,
        RunHarnessChoice::Antigravity => ManagedHarness::Antigravity,
        RunHarnessChoice::Copilot => ManagedHarness::Copilot,
    }
}

pub(crate) const fn run_harness_choice(harness: ManagedHarness) -> RunHarnessChoice {
    match harness {
        ManagedHarness::Claude => RunHarnessChoice::Claude,
        ManagedHarness::Codex => RunHarnessChoice::Codex,
        ManagedHarness::OpenCode => RunHarnessChoice::OpenCode,
        ManagedHarness::OpenCode2 => RunHarnessChoice::OpenCode2,
        ManagedHarness::Pi => RunHarnessChoice::Pi,
        ManagedHarness::Crush => RunHarnessChoice::Crush,
        ManagedHarness::Omp => RunHarnessChoice::Omp,
        ManagedHarness::Kimi => RunHarnessChoice::Kimi,
        ManagedHarness::CommandCode => RunHarnessChoice::CommandCode,
        ManagedHarness::Kiro | ManagedHarness::KiroV3 => RunHarnessChoice::Kiro,
        ManagedHarness::Grok => RunHarnessChoice::Grok,
        ManagedHarness::Antigravity => RunHarnessChoice::Antigravity,
        ManagedHarness::Copilot => RunHarnessChoice::Copilot,
    }
}

pub(crate) fn managed_harness_for_args(choice: RunHarnessChoice, native_args: &[OsString]) -> ManagedHarness {
    let harness = managed_harness(choice);
    if harness == ManagedHarness::Kiro && kiro_selects_v3_engine(native_args) { ManagedHarness::KiroV3 } else { harness }
}

pub(crate) const fn managed_harness_from_agent(agent: AgentKind) -> Option<ManagedHarness> {
    match agent {
        AgentKind::ClaudeCode => Some(ManagedHarness::Claude),
        AgentKind::Codex => Some(ManagedHarness::Codex),
        AgentKind::OpenCode => Some(ManagedHarness::OpenCode),
        AgentKind::Pi => Some(ManagedHarness::Pi),
        AgentKind::Crush => Some(ManagedHarness::Crush),
        AgentKind::KimiCode => Some(ManagedHarness::Kimi),
        AgentKind::CommandCode => Some(ManagedHarness::CommandCode),
        AgentKind::KiroCli => Some(ManagedHarness::Kiro),
        AgentKind::Grok => Some(ManagedHarness::Grok),
        AgentKind::AntigravityCli => Some(ManagedHarness::Antigravity),
        AgentKind::CopilotCli => Some(ManagedHarness::Copilot),
        _ => None,
    }
}

/// The exact names the recovery journal writes (`ManagedHarness::as_str`),
/// Kiro's engine flavor included.
pub(crate) fn harness_from_journal_name(name: &str) -> Option<ManagedHarness> {
    [
        ManagedHarness::Claude, ManagedHarness::Codex, ManagedHarness::OpenCode, ManagedHarness::OpenCode2,
        ManagedHarness::Pi, ManagedHarness::Crush, ManagedHarness::Omp, ManagedHarness::Kimi,
        ManagedHarness::CommandCode, ManagedHarness::Kiro, ManagedHarness::KiroV3, ManagedHarness::Grok,
        ManagedHarness::Antigravity, ManagedHarness::Copilot,
    ]
    .into_iter()
    .find(|harness| harness.as_str() == name)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn names_aliases_and_claude_spellings_parse_like_upstream() {
        assert_eq!(parse_run_harness_choice("Claude-Code"), Ok(RunHarnessChoice::Claude));
        assert_eq!(parse_run_harness_choice("cmd"), Ok(RunHarnessChoice::CommandCode));
        assert_eq!(parse_run_harness_choice("agy"), Ok(RunHarnessChoice::Antigravity));
        assert_eq!(parse_run_harness_choice("claude-corp"), Ok(RunHarnessChoice::Claude));
        assert_eq!(claude_wrapper_spelling("claude-corp"), Some("claude-corp"));
        assert_eq!(claude_wrapper_spelling("claude-code"), None);
        assert!(parse_run_harness_choice("vim").unwrap_err().contains("claude, codex, opencode"));
        assert_eq!(managed_harness_for_args(RunHarnessChoice::Kiro, &["--v3".into()]), ManagedHarness::KiroV3);
        for harness in [ManagedHarness::KiroV3, ManagedHarness::OpenCode2, ManagedHarness::CommandCode] {
            assert_eq!(harness_from_journal_name(harness.as_str()), Some(harness));
        }
    }
}
