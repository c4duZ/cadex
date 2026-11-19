//! After a clean interactive session, the menu that continues the same
//! workstream in another installed harness, runs this one again, or quits
//! (the default); off with `--no-exit-prompt` or `run.exit_prompt = false`.
//!
//! Copied from ai-memory v3.4.7 (fa0ec25; compared at v3.5.0, 411d90d, on 2026-11-19: its new `--or-new` not brought, `cadex continue` does not use it), crates/ai-memory-cli/src/commands/
//! run.rs: `AfterRunAction`, `run_with_exit_prompt`,
//! `run_with_exit_prompt_loop`, `should_offer_after_run`,
//! `available_switch_harnesses`, `choose_after_run` and
//! `apply_after_run_action`. Changed for Cadex (2026-11-16): no i18n; no
//! project-split repair around each launch (mod.rs explains why).

use std::ffi::OsString;
use std::io::{self, IsTerminal as _};

use ai_memory_workstream::{LaunchMode, ManagedHarness};
use anyhow::Result;

use super::args::{Env, RunArgs};
use super::child_env::{EffectiveChildEnv, harness_available};
use super::choice::{RunHarnessChoice, managed_harness, run_harness_choice};
use super::flow::{RunOutcome, run_once};
use super::profiles::Settings;
use super::wrapper::preserve_trailing_run_options;
use super::yolo::Paint;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum AfterRunAction {
    Switch(RunHarnessChoice),
    Rerun,
    Quit,
}

pub(crate) async fn run_with_exit_prompt(args: RunArgs, env: &Env, settings: &Settings) -> Result<i32> {
    let result = run_with_exit_prompt_loop(args, env, settings).await;
    super::jail::print_next_run_hint();
    result
}

async fn run_with_exit_prompt_loop(args: RunArgs, env: &Env, settings: &Settings) -> Result<i32> {
    let interactive_terminal = io::stdin().is_terminal() && io::stdout().is_terminal() && io::stderr().is_terminal();
    let mut next_args = args;
    preserve_trailing_run_options(&mut next_args);
    loop {
        let outcome = run_once(next_args.clone(), env, settings).await?;
        if !should_offer_after_run(settings, &next_args, &outcome, interactive_terminal) {
            return Ok(outcome.exit_code);
        }
        let available = available_switch_harnesses(outcome.harness, &EffectiveChildEnv::with_overrides(&[]));
        let action = choose_after_run(Paint::for_stderr(), outcome.harness, &outcome.workstream_name, &available,
            &mut io::stdin().lock(), &mut io::stderr().lock());
        let action = match action {
            Ok(action) => action,
            Err(error) => {
                eprintln!("ai-memory: could not read the post-run choice ({error}); exiting");
                return Ok(outcome.exit_code);
            }
        };
        if !apply_after_run_action(&mut next_args, &outcome, action) {
            return Ok(outcome.exit_code);
        }
    }
}

pub(crate) fn should_offer_after_run(settings: &Settings, args: &RunArgs, outcome: &RunOutcome, interactive_terminal: bool) -> bool {
    settings.run.exit_prompt
        && !args.no_exit_prompt
        && outcome.exit_code == 0
        && outcome.mode == LaunchMode::Session
        && outcome.interactive_session
        && !outcome.degraded
        && interactive_terminal
        && args.executable.is_none()
}

fn available_switch_harnesses(current: ManagedHarness, env: &EffectiveChildEnv) -> Vec<RunHarnessChoice> {
    let search = env.executable_search();
    RunHarnessChoice::all()
        .filter(|choice| managed_harness(*choice).agent_kind() != current.agent_kind() && harness_available(*choice, search))
        .collect()
}

pub(crate) fn choose_after_run(paint: Paint, current: ManagedHarness, workstream_name: &str, available: &[RunHarnessChoice],
    input: &mut impl io::BufRead, output: &mut impl io::Write) -> io::Result<AfterRunAction> {
    let name = super::terminal_text(workstream_name);
    writeln!(output, "{} {}", paint.green("✓"),
        paint.bold(&format!("ai-memory: {} exited successfully in workstream '{name}'.", current.as_str())))?;
    writeln!(output, "  {}", paint.dim("A switch keeps this workstream, its options and the same jail."))?;
    for (index, choice) in available.iter().enumerate() {
        writeln!(output, "  {}) switch to {}", index + 1, managed_harness(*choice).as_str())?;
    }
    writeln!(output, "  r) run {} again", current.as_str())?;
    writeln!(output, "  q) quit (default)")?;
    loop {
        write!(output, "Select [q]: ")?;
        output.flush()?;
        let mut line = String::new();
        if input.read_line(&mut line)? == 0 {
            return Ok(AfterRunAction::Quit);
        }
        let choice = line.trim();
        if choice.is_empty() || choice.eq_ignore_ascii_case("q") || choice == "0" {
            return Ok(AfterRunAction::Quit);
        }
        if choice.eq_ignore_ascii_case("r") {
            return Ok(AfterRunAction::Rerun);
        }
        if let Ok(index) = choice.parse::<usize>() && let Some(harness) = index.checked_sub(1).and_then(|i| available.get(i)) {
            return Ok(AfterRunAction::Switch(*harness));
        }
        writeln!(output, "Choose a listed number, r, or q.")?;
    }
}

/// The next launch for `action`: same workstream, no native argv; `false` quits.
pub(crate) fn apply_after_run_action(args: &mut RunArgs, outcome: &RunOutcome, action: AfterRunAction) -> bool {
    let choice = match action {
        AfterRunAction::Quit => return false,
        AfterRunAction::Switch(choice) => choice,
        AfterRunAction::Rerun => run_harness_choice(outcome.harness),
    };
    args.harness = Some(choice);
    if action != AfterRunAction::Rerun {
        args.claude_wrapper = None;
    }
    args.native_args = if action == AfterRunAction::Rerun && outcome.harness == ManagedHarness::KiroV3 {
        vec![OsString::from("--v3")]
    } else {
        Vec::new()
    };
    args.workstream = Some(outcome.workstream_name.clone());
    args.new_workstream = None;
    args.fresh = false;
    args.yolo |= std::mem::take(&mut args.true_yolo);
    true
}

#[cfg(test)]
mod tests {
    use super::*;

    fn outcome() -> RunOutcome {
        RunOutcome { exit_code: 0, harness: ManagedHarness::KiroV3, interactive_session: true, mode: LaunchMode::Session,
            workstream_name: "main".into(), degraded: false }
    }

    #[test]
    fn the_menu_defaults_to_quit_and_a_switch_keeps_the_workstream() {
        let mut output = Vec::new();
        let available = [RunHarnessChoice::Codex];
        let pick = |input: &str, output: &mut Vec<u8>| {
            choose_after_run(Paint::PLAIN, ManagedHarness::Claude, "main", &available, &mut input.as_bytes(), output).unwrap()
        };
        assert_eq!(pick("\n", &mut output), AfterRunAction::Quit);
        let text = String::from_utf8(output.clone()).unwrap();
        assert!(text.contains("1) switch to codex") && text.contains("r) run claude again"), "{text}");
        assert_eq!(pick("x\n1\n", &mut output), AfterRunAction::Switch(RunHarnessChoice::Codex));
        assert_eq!(pick("R\n", &mut output), AfterRunAction::Rerun);
        let mut args = RunArgs { native_args: vec!["--prompt".into()], new_workstream: Some("n".into()), true_yolo: true,
            claude_wrapper: Some("claude-corp".into()), ..RunArgs::default() };
        assert!(apply_after_run_action(&mut args, &outcome(), AfterRunAction::Rerun));
        assert_eq!((args.harness, args.native_args.clone()), (Some(RunHarnessChoice::Kiro), vec![OsString::from("--v3")]));
        assert_eq!(args.workstream.as_deref(), Some("main"));
        assert!(args.yolo && !args.true_yolo && args.new_workstream.is_none() && args.claude_wrapper.is_some());
        assert!(!apply_after_run_action(&mut args, &outcome(), AfterRunAction::Quit));
        let settings = Settings::default();
        assert!(should_offer_after_run(&settings, &RunArgs::default(), &outcome(), true));
        assert!(!should_offer_after_run(&settings, &RunArgs::default(), &outcome(), false));
        assert!(!should_offer_after_run(&settings, &RunArgs { no_exit_prompt: true, ..RunArgs::default() }, &outcome(), true));
    }
}
