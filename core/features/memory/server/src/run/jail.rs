//! When a launch goes into ai-jail (docs/design-yolo-safety-ai-jail.md of
//! upstream): the decision table for `--jail`/`--no-jail`/`--yolo`, the
//! folder flags, the `--yolo` gate with its offer and checklist, and the
//! line that repeats the choices next time.
//!
//! Copied from ai-memory v3.4.7 (fa0ec25), crates/ai-memory-cli/src/commands/
//! run.rs: `JailMode`, `JailPlan`, `jail_decision`, `NextRun`, `JailInputs`,
//! `NEXT_RUN_ENV`, `folder_rules`, `folders_need_a_jail`,
//! `validate_flag_folders`, `next_run_command`, `print_next_run_hint`,
//! `next_run_hint`, `recall_jail_answers`, `JailOffer` and
//! `confirm_yolo_and_maybe_reexec`. Changed for Cadex (2026-11-16): no
//! i18n; answers live in `<data-dir>/run/`; the repeat line names
//! `cadex-memory run`; `f` in the checklist names the folder flags (no
//! picker, jail_folders.rs).

use std::io::{self, IsTerminal as _};
use std::path::{Path, PathBuf};

use ai_memory_workstream::{
    JailChecklistItem, JailHostFacts, JailToggleChoice, ManagedHarness, ai_jail_support, checklist_reason, inside_ai_jail_here,
    jail_checklist, jail_spec, marked_choices,
};
use anyhow::{Context, Result, anyhow};
use tokio_util::sync::CancellationToken;

use super::jail_checklist::{ChecklistView, read_jail_checklist};
use super::jail_choices::{self, Applied};
use super::jail_exec::{JailContext, JailLaunch, exec_under_ai_jail, jail_contract_for, shell_quote};
use super::jail_folders::{ExtraFolder, FolderRules, upsert, validate_extra_folder};
use super::wrapper::JailRequest;
use super::yolo::{Paint, read_yolo_confirmation};

pub(crate) const NEXT_RUN_ENV: &str = "AI_MEMORY_JAIL_NEXT_RUN";

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum JailMode {
    Stay,
    Offer { checklist: bool },
    Explicit(String),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct JailPlan {
    pub(crate) warn: bool,
    pub(crate) mode: JailMode,
}

/// The pure decision table: nothing applies inside ai-jail; the warning
/// shows for an interactive `--yolo`; an explicit `--jail` re-execs even
/// non-interactively and fails rather than run unjailed.
pub(crate) fn jail_decision(request: &JailRequest, jailed: bool, yolo: bool, interactive: bool, usable: bool,
    project_config: bool) -> Result<JailPlan> {
    if jailed {
        return Ok(JailPlan { warn: false, mode: JailMode::Stay });
    }
    let warn = yolo && interactive;
    let mode = match request {
        JailRequest::Never => JailMode::Stay,
        JailRequest::Explicit(_) if !usable => {
            return Err(anyhow!(
                "--jail: ai-jail is not usable on this host (it needs `ai-jail` plus its sandbox \
                 backend, bwrap on Linux or sandbox-exec on macOS, and does not run on Windows); \
                 refusing to run unjailed — drop --jail to run without it"
            ));
        }
        JailRequest::Explicit(list) => JailMode::Explicit(list.clone()),
        JailRequest::Unspecified if warn && usable => JailMode::Offer { checklist: !project_config },
        JailRequest::Unspecified => JailMode::Stay,
    };
    Ok(JailPlan { warn, mode })
}

/// The launch's own options, kept to print the command that repeats it.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub(crate) struct NextRun {
    pub(crate) yolo: bool,
    pub(crate) no_autowire: bool,
    pub(crate) workspace: Option<String>,
    pub(crate) project: Option<String>,
    pub(crate) profile: Option<String>,
    pub(crate) env_file: Option<PathBuf>,
    pub(crate) had_env: bool,
    pub(crate) harness: Option<String>,
}

#[derive(Debug, Clone)]
pub(crate) struct JailInputs {
    pub(crate) checkout_key: String,
    pub(crate) checkout_root: PathBuf,
    pub(crate) home: PathBuf,
    pub(crate) flag_folders: Vec<ExtraFolder>,
    pub(crate) next_run: NextRun,
}

fn folder_rules<'a>(data_dir: &'a Path, home: &'a Path, checkout_root: &'a Path) -> FolderRules<'a> {
    FolderRules { home: Some(home), data_dir, checkout_root }
}

/// Folder flags on a run that is not going into ai-jail would be ignored.
pub(crate) fn folders_need_a_jail(inputs: &JailInputs) -> Result<()> {
    if inputs.flag_folders.is_empty() {
        Ok(())
    } else {
        Err(anyhow!("--jail-map and --jail-rw-map need a jailed run: add --jail, or --yolo and accept the ai-jail offer"))
    }
}

pub(crate) fn validate_flag_folders(data_dir: &Path, cwd: &Path, home: &Path, flags: &[(PathBuf, bool)]) -> Result<Vec<ExtraFolder>> {
    let rules = folder_rules(data_dir, home, cwd);
    let mut folders = Vec::new();
    for (raw, writable) in flags {
        let path = validate_extra_folder(raw, cwd, &rules).map_err(|refusal| anyhow!("cannot mount {} in the jail: {refusal}", raw.display()))?;
        upsert(&mut folders, ExtraFolder { path, writable: *writable });
    }
    Ok(folders)
}

/// The line that repeats this launch's jail choices, without one-off parts.
pub(crate) fn next_run_command(next: &NextRun, choices: Option<&[JailToggleChoice]>, folders: &[ExtraFolder]) -> String {
    let mut words = vec!["cadex-memory".to_owned(), "run".to_owned()];
    if next.yolo {
        words.push("--yolo".to_owned());
    }
    if next.no_autowire {
        words.push("--no-autowire".to_owned());
    }
    let env_file = next.env_file.as_ref().map(|path| path.to_string_lossy().into_owned());
    for (flag, value) in [("--workspace", next.workspace.as_ref()), ("--project", next.project.as_ref()),
        ("--profile", next.profile.as_ref()), ("--env-file", env_file.as_ref())] {
        if let Some(value) = value {
            words.push(flag.to_owned());
            words.push(shell_quote(value));
        }
    }
    words.push(match choices {
        Some(choices) => format!("--jail={}", jail_spec(choices)),
        None => "--jail".to_owned(),
    });
    for folder in folders {
        words.push(if folder.writable { "--jail-rw-map" } else { "--jail-map" }.to_owned());
        words.push(shell_quote(&folder.path.to_string_lossy()));
    }
    if let Some(harness) = &next.harness {
        words.push(harness.clone());
    }
    let mut line = words.join(" ");
    if next.had_env {
        line.push_str("   # add your --env values again");
    }
    line
}

/// Only the jailed run prints the line the outer launcher handed in.
pub(crate) fn print_next_run_hint() {
    if !inside_ai_jail_here() || !io::stderr().is_terminal() {
        return;
    }
    let Some(command) = std::env::var_os(NEXT_RUN_ENV) else { return };
    eprint!("{}", next_run_hint(Paint::for_stderr(), &command.to_string_lossy()));
}

fn next_run_hint(paint: Paint, command: &str) -> String {
    format!("\n{}\n  {}\n", paint.dim("Next time, start with the same jail choices:"), paint.bold(&super::terminal_text(command)))
}

/// This checkout's remembered answers on `items`, folders that still
/// qualify, then the command-line folders.
fn recall_jail_answers(run_dir: &Path, data_dir: &Path, inputs: &JailInputs, items: &mut [JailChecklistItem])
    -> (Option<String>, Applied, Vec<ExtraFolder>) {
    let remembered = jail_choices::load(run_dir, &inputs.checkout_key).unwrap_or_default();
    let mut applied = if remembered == jail_choices::Remembered::default() {
        Applied::default()
    } else {
        jail_choices::apply(items, &remembered)
    };
    let rules = folder_rules(data_dir, &inputs.home, &inputs.checkout_root);
    let mut folders = Vec::new();
    for folder in remembered.folders {
        match validate_extra_folder(&folder.path, &inputs.checkout_root, &rules) {
            Ok(path) => folders.push(ExtraFolder { path, writable: folder.writable }),
            Err(_) => applied.gone.push(format!("📁 {}", folder.path.display())),
        }
    }
    for flag in &inputs.flag_folders {
        upsert(&mut folders, flag.clone());
    }
    (remembered.saved_at.get(..10).map(str::to_owned), applied, folders)
}

#[derive(Clone, Copy)]
pub(crate) struct JailOffer<'a> {
    pub(crate) ai_jail: Option<&'a Path>,
    pub(crate) harness: ManagedHarness,
}

/// The `--yolo` gate. On accepting the offer (and the checklist) it releases
/// `lease` and re-execs under ai-jail, which never returns on success.
pub(crate) async fn confirm_yolo_and_maybe_reexec(ctx: &JailContext<'_>, plan: &JailPlan, offer: JailOffer<'_>,
    facts: &JailHostFacts, inputs: &JailInputs, lease: Option<(&super::uds_http::Client, &str)>,
    interrupted: &CancellationToken) -> Result<()> {
    if !plan.warn {
        return Ok(());
    }
    if interrupted.is_cancelled() {
        return Err(anyhow!("managed run interrupted before the agent started"));
    }
    let (ai_jail, show_checklist) = match plan.mode {
        JailMode::Offer { checklist } => (offer.ai_jail, checklist),
        JailMode::Stay | JailMode::Explicit(_) => (None, false),
    };
    let available = ai_jail.is_some();
    let paint = Paint::for_stderr();
    let confirmation = tokio::task::spawn_blocking(move || {
        read_yolo_confirmation(paint, available, &mut io::stdin().lock(), &mut io::stderr())
    })
    .await
    .context("waiting for the --yolo confirmation")?
    .context("reading the --yolo confirmation from stdin")?;
    if !confirmation.proceed {
        return Err(anyhow!("aborted: --yolo not confirmed"));
    }
    let (true, Some(ai_jail)) = (confirmation.jail, ai_jail) else {
        folders_need_a_jail(inputs)?;
        return Ok(());
    };
    let support = ai_jail_support(ai_jail).with_context(|| format!("reading the toggles {} supports", ai_jail.display()))?;
    let contract = jail_contract_for(ai_jail, &support, Some(offer.harness));
    let mut items = if contract.is_some() { Vec::new() } else { jail_checklist(facts, &support) };
    let show = if contract.is_some() { support.mounts_folders() } else { show_checklist && !items.is_empty() };
    let (toggles, folders, next_run) = if !show {
        (Vec::new(), inputs.flag_folders.clone(), None)
    } else {
        let reasons = items.iter().map(|item| checklist_reason(facts, item.toggle)).collect();
        let recommended = items.iter().map(|item| item.checked).collect();
        let run_dir = ctx.env.run_dir();
        let (last_saved, mut applied, folders) = recall_jail_answers(&run_dir, &ctx.env.data_dir, inputs, &mut items);
        if contract.is_some() {
            applied.gone.retain(|gone| gone.starts_with("📁"));
        }
        let view = ChecklistView { paint, reasons, recommended, last_saved, new: applied.new, gone: applied.gone,
            folders_supported: support.mounts_folders() };
        let outcome = tokio::task::spawn_blocking(move || {
            let mut pick = |_: &[ExtraFolder]| {
                eprintln!("the folder picker is not available here; pass --jail-map DIR or --jail-rw-map DIR instead");
                Ok(None)
            };
            read_jail_checklist(&view, &items, folders, &mut io::stdin().lock(), &mut io::stderr(), &mut pick)
        })
        .await
        .context("waiting for the ai-jail checklist")?
        .context("reading the ai-jail checklist from stdin")?;
        let saved_at = jiff::Timestamp::now().to_string();
        let remembered = if contract.is_some() {
            let mut prior = jail_choices::load(&run_dir, &inputs.checkout_key).unwrap_or_default();
            prior.folders.clone_from(&outcome.folders);
            prior.saved_at = saved_at;
            prior
        } else {
            jail_choices::remember(&outcome.marked, outcome.folders.clone(), saved_at)
        };
        if let Err(error) = jail_choices::save(&run_dir, &inputs.checkout_key, remembered) {
            eprintln!("ai-memory: could not remember the jail choices ({error:#}); they apply to this run only");
        }
        let choices = marked_choices(&outcome.marked);
        let next = next_run_command(&inputs.next_run, contract.is_none().then_some(choices.as_slice()), &outcome.folders);
        (choices, outcome.folders, Some(next))
    };
    if let Some((client, run_path)) = lease {
        super::server::cancel_after_failure(client, run_path).await;
    }
    Err(exec_under_ai_jail(ai_jail, ctx, JailLaunch { support: &support, contract: contract.as_ref() }, &toggles,
        facts.project_config, &folders, next_run))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_decision_table_matches_upstream() {
        let explicit = JailRequest::Explicit(String::new());
        assert_eq!(jail_decision(&explicit, true, true, true, false, false).unwrap(), JailPlan { warn: false, mode: JailMode::Stay });
        assert!(jail_decision(&explicit, false, false, false, false, false).is_err());
        assert_eq!(jail_decision(&explicit, false, false, false, true, false).unwrap().mode, JailMode::Explicit(String::new()));
        let offer = jail_decision(&JailRequest::Unspecified, false, true, true, true, true).unwrap();
        assert_eq!(offer, JailPlan { warn: true, mode: JailMode::Offer { checklist: false } });
        assert_eq!(jail_decision(&JailRequest::Unspecified, false, true, false, true, false).unwrap(),
            JailPlan { warn: false, mode: JailMode::Stay });
        assert_eq!(jail_decision(&JailRequest::Never, false, true, true, true, false).unwrap().mode, JailMode::Stay);
    }

    #[test]
    fn the_next_run_line_repeats_choices_but_not_secrets() {
        let next = NextRun { yolo: true, profile: Some("work".into()), had_env: true, harness: Some("claude".into()),
            ..NextRun::default() };
        let folders = [ExtraFolder { path: "/src/my lib".into(), writable: true }];
        assert_eq!(next_run_command(&next, None, &folders),
            "cadex-memory run --yolo --profile work --jail --jail-rw-map '/src/my lib' claude   # add your --env values again");
        assert_eq!(next_run_hint(Paint::PLAIN, "x\x1b"), "\nNext time, start with the same jail choices:\n  x\u{FFFD}\n");
    }
}
