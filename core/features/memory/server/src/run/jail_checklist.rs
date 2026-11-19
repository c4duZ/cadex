//! The ai-jail toggle checklist (what the jailed agent can reach), read
//! line by line on injected I/O, and the one-line summary of what the
//! jailed re-run enables.
//!
//! Copied from ai-memory v3.4.7 (fa0ec25; compared at v3.5.0, 411d90d, on 2026-11-19: unchanged), crates/ai-memory-cli/src/commands/
//! run.rs: `CHECKLIST_MAX_INVALID`, `ChecklistAnswer`,
//! `apply_checklist_answer`, `ChecklistView`, `FolderPicker`,
//! `ChecklistOutcome`, `folder_names`, `render_checklist`,
//! `read_jail_checklist` and `jail_summary`. Changed for Cadex
//! (2026-11-16): no i18n.

use std::io;

use ai_memory_workstream::{JailChecklistItem, JailRisk, JailToggleChoice, JailToggleKind, jail_toggle};

use super::jail_folders::ExtraFolder;
use super::terminal_text;
use super::yolo::Paint;

const CHECKLIST_MAX_INVALID: usize = 3;

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum ChecklistAnswer {
    Accept,
    Changed,
    Folders,
    Reset,
    Invalid(String),
}

/// One checklist line: empty accepts, `all`/`none` set every mark, `f`
/// asks for folders, `reset` restores the recommendation, numbers flip rows.
/// A line with any bad number changes nothing.
pub(crate) fn apply_checklist_answer(line: &str, checked: &mut [bool]) -> ChecklistAnswer {
    let answer = line.trim().to_ascii_lowercase();
    match answer.as_str() {
        "" => return ChecklistAnswer::Accept,
        "f" | "folders" => return ChecklistAnswer::Folders,
        "reset" => return ChecklistAnswer::Reset,
        "all" | "none" => {
            checked.fill(answer == "all");
            return ChecklistAnswer::Changed;
        }
        _ => {}
    }
    let mut rows = Vec::new();
    for token in answer.split([' ', ',', '\t']).filter(|token| !token.is_empty()) {
        match token.parse::<usize>() {
            Ok(row) if (1..=checked.len()).contains(&row) => rows.push(row - 1),
            _ => {
                return ChecklistAnswer::Invalid(format!(
                    "`{token}` is not a row number between 1 and {}; press Enter to accept, or type numbers, `all`, or `none`",
                    checked.len()
                ));
            }
        }
    }
    for row in rows {
        checked[row] = !checked[row];
    }
    ChecklistAnswer::Changed
}

pub(crate) struct ChecklistView {
    pub(crate) paint: Paint,
    pub(crate) reasons: Vec<Option<&'static str>>,
    pub(crate) recommended: Vec<bool>,
    pub(crate) last_saved: Option<String>,
    pub(crate) new: Vec<&'static str>,
    pub(crate) gone: Vec<String>,
    pub(crate) folders_supported: bool,
}

/// Opens the extra-folder picker on the current folders; `None` keeps them.
pub(crate) type FolderPicker<'a> = dyn FnMut(&[ExtraFolder]) -> io::Result<Option<Vec<ExtraFolder>>> + 'a;

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct ChecklistOutcome {
    pub(crate) marked: Vec<JailChecklistItem>,
    pub(crate) folders: Vec<ExtraFolder>,
}

pub(crate) fn folder_names(folders: &[ExtraFolder]) -> String {
    folders.iter().map(|folder| terminal_text(&folder.label())).collect::<Vec<_>>().join(", ")
}

fn render_checklist(view: &ChecklistView, items: &[JailChecklistItem], checked: &[bool], folders: &[ExtraFolder],
    output: &mut impl io::Write) -> io::Result<()> {
    let paint = view.paint;
    if items.is_empty() {
        writeln!(output, "{} {}", paint.bold("🔒 ai-jail: extra folders for the agent"), paint.dim("(ai-jail reviews the rest next)"))?;
    } else {
        writeln!(output, "{} {}", paint.bold("🔒 ai-jail: what the agent can reach"), paint.dim("(Enter keeps the marks)"))?;
    }
    let mut changes = Vec::new();
    if let Some(saved) = &view.last_saved {
        changes.push(paint.dim(&format!("your choices from {saved}")));
    }
    if !view.new.is_empty() {
        changes.push(paint.cyan(&format!("new: {}", view.new.join(", "))));
    }
    if !view.gone.is_empty() {
        changes.push(paint.yellow(&format!("no longer offered: {}", view.gone.join(", "))));
    }
    if !changes.is_empty() {
        writeln!(output, "   {}", changes.join(&paint.dim(" · ")))?;
    }
    let width = items.iter().map(|item| item.toggle.label.chars().count()).max().unwrap_or(0);
    for (index, (item, on)) in items.iter().zip(checked).enumerate() {
        let mark = if *on { paint.green("[x]") } else { paint.dim("[ ]") };
        let note = match item.toggle.risk() {
            JailRisk::HostRoot => paint.red(item.toggle.note),
            JailRisk::Secret => format!("🔑 {}", paint.dim(item.toggle.note)),
            JailRisk::Normal => paint.dim(item.toggle.note),
        };
        let mut extra = String::new();
        if let Some(reason) = view.reasons.get(index).copied().flatten() {
            extra.push_str(&paint.green(&format!(" · {reason}")));
        }
        if view.new.contains(&item.toggle.stem) {
            extra.push_str(&paint.cyan(" new"));
        }
        writeln!(output, "  {mark} {}) {:<width$}   {note}{extra}", index + 1, item.toggle.label)?;
    }
    if view.folders_supported {
        let listed = if folders.is_empty() { paint.dim("none") } else { paint.yellow(&folder_names(folders)) };
        writeln!(output, "  📁 Extra folders: {listed}")?;
        let keys = if items.is_empty() { "f folders · reset · Enter go" } else { "numbers flip · f folders · all · none · reset · Enter go" };
        writeln!(output, "  {}", paint.dim(keys))?;
    } else {
        writeln!(output, "  {}", paint.dim("numbers flip · all · none · reset · Enter go"))?;
    }
    write!(output, "> ")?;
    output.flush()
}

/// The interactive checklist. Enter or EOF accepts the marks; the result
/// marks every row as the user saw it.
pub(crate) fn read_jail_checklist(view: &ChecklistView, items: &[JailChecklistItem], folders: Vec<ExtraFolder>,
    input: &mut impl io::BufRead, output: &mut impl io::Write, pick_folders: &mut FolderPicker<'_>)
    -> io::Result<ChecklistOutcome> {
    let mut checked: Vec<bool> = items.iter().map(|item| item.checked).collect();
    let mut folders = folders;
    let mut invalid = 0;
    loop {
        render_checklist(view, items, &checked, &folders, output)?;
        let mut line = String::new();
        if input.read_line(&mut line)? == 0 {
            writeln!(output)?;
            break;
        }
        match apply_checklist_answer(&line, &mut checked) {
            ChecklistAnswer::Accept => break,
            ChecklistAnswer::Changed => {}
            ChecklistAnswer::Folders if view.folders_supported => {
                if let Some(picked) = pick_folders(&folders)? {
                    folders = picked;
                }
            }
            ChecklistAnswer::Reset => {
                checked.clone_from(&view.recommended);
                folders.clear();
            }
            ChecklistAnswer::Folders => writeln!(output, "this ai-jail cannot mount extra folders; update it to use `f`")?,
            ChecklistAnswer::Invalid(message) => {
                invalid += 1;
                writeln!(output, "{message}")?;
                if invalid >= CHECKLIST_MAX_INVALID {
                    return Err(io::Error::other("too many unrecognized answers to the ai-jail checklist"));
                }
            }
        }
    }
    let marked = items.iter().zip(checked).map(|(item, checked)| JailChecklistItem { toggle: item.toggle, checked }).collect();
    Ok(ChecklistOutcome { marked, folders })
}

/// What the jailed re-run enables, grouped by risk, in one line.
pub(crate) fn jail_summary(toggles: &[JailToggleChoice], project_config: bool, folders: &[ExtraFolder]) -> String {
    let labels = |kind: JailToggleKind| -> Vec<&'static str> {
        toggles
            .iter()
            .filter(|choice| choice.enable)
            .filter_map(|choice| jail_toggle(choice.stem))
            .filter(|toggle| toggle.kind == kind)
            .map(|toggle| toggle.label)
            .collect()
    };
    let mut parts = Vec::new();
    for (heading, kind) in [("credentials", JailToggleKind::Credential), ("capabilities", JailToggleKind::Capability)] {
        let names = labels(kind);
        if !names.is_empty() {
            parts.push(format!("{heading}: {}", names.join(", ")));
        }
    }
    let off: Vec<String> = toggles.iter().filter(|c| !c.enable && !c.implied).map(JailToggleChoice::flag).collect();
    if !off.is_empty() {
        parts.push(format!("forced off: {}", off.join(" ")));
    }
    if toggles.iter().any(|choice| choice.implied) {
        parts.push("everything else in the checklist off".to_owned());
    }
    if !folders.is_empty() {
        parts.push(format!("folders: {}", folder_names(folders)));
    }
    if project_config {
        parts.push("plus the project .ai-jail".to_owned());
    }
    if parts.is_empty() {
        "ai-memory: re-running inside ai-jail with no extra mounts".to_owned()
    } else {
        format!("ai-memory: re-running inside ai-jail ({})", parts.join("; "))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use ai_memory_workstream::JAIL_TOGGLES;

    fn items() -> Vec<JailChecklistItem> {
        JAIL_TOGGLES.iter().take(3).map(|toggle| JailChecklistItem { toggle, checked: false }).collect()
    }

    fn view() -> ChecklistView {
        ChecklistView { paint: Paint::PLAIN, reasons: vec![None; 3], recommended: vec![true, false, false], last_saved: None,
            new: Vec::new(), gone: Vec::new(), folders_supported: true }
    }

    fn run(input: &str) -> (io::Result<ChecklistOutcome>, String) {
        let mut output = Vec::new();
        let mut picked = |_: &[ExtraFolder]| Ok(Some(vec![ExtraFolder { path: "/x/lib".into(), writable: false }]));
        let outcome = read_jail_checklist(&view(), &items(), Vec::new(), &mut input.as_bytes(), &mut output, &mut picked);
        (outcome, String::from_utf8(output).unwrap())
    }

    #[test]
    fn numbers_flip_all_none_reset_and_too_many_bad_answers_abort() {
        let mut checked = vec![false, true, false];
        assert_eq!(apply_checklist_answer("1, 2", &mut checked), ChecklistAnswer::Changed);
        assert_eq!(checked, [true, false, false]);
        assert!(matches!(apply_checklist_answer("1 9", &mut checked), ChecklistAnswer::Invalid(_)));
        assert_eq!(checked, [true, false, false]);
        assert_eq!(apply_checklist_answer("ALL", &mut checked), ChecklistAnswer::Changed);
        assert_eq!(checked, [true, true, true]);
        assert_eq!(apply_checklist_answer(" f ", &mut checked), ChecklistAnswer::Folders);
        let (outcome, text) = run("2\nf\n\n");
        let outcome = outcome.unwrap();
        assert_eq!(outcome.marked.iter().map(|i| i.checked).collect::<Vec<_>>(), [false, true, false]);
        assert_eq!(outcome.folders.len(), 1);
        assert!(text.contains("Extra folders: lib (ro)"), "{text}");
        let (outcome, _) = run("all\nreset\n");
        assert_eq!(outcome.unwrap().marked.iter().map(|i| i.checked).collect::<Vec<_>>(), [true, false, false]);
        assert!(run("x\ny\nz\n").0.is_err());
        assert_eq!(jail_summary(&[], false, &[]), "ai-memory: re-running inside ai-jail with no extra mounts");
    }
}
