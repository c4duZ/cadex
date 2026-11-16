//! The wrapper flags typed after the harness name: they still belong to the
//! launcher, so they are taken out of the native argv before the harness
//! sees it.
//!
//! Copied from ai-memory v3.4.7 (fa0ec25), crates/ai-memory-cli/src/commands/
//! run.rs: `remove_wrapper_yolo`, `remove_wrapper_true_yolo`,
//! `take_wrapper_yolo`, `yolo_deprecation_notes`, `remove_wrapper_fresh`,
//! `remove_wrapper_force_unlock`, `remove_wrapper_no_autowire`,
//! `remove_wrapper_no_exit_prompt`, `TrailingJail`, `remove_wrapper_jail`,
//! `JailRequest`, `jail_request` and `preserve_trailing_run_options`
//! (2026-11-16).

use std::ffi::{OsStr, OsString};

use anyhow::{Result, anyhow};

use super::args::RunArgs;

fn remove_flag(args: &mut Vec<OsString>, flag: &str) -> bool {
    let before = args.len();
    args.retain(|arg| arg != OsStr::new(flag));
    args.len() != before
}

pub(crate) fn remove_wrapper_yolo(args: &mut Vec<OsString>) -> bool {
    remove_flag(args, "--yolo")
}

pub(crate) fn remove_wrapper_true_yolo(args: &mut Vec<OsString>) -> bool {
    remove_flag(args, "--true-yolo")
}

pub(crate) fn remove_wrapper_fresh(args: &mut Vec<OsString>) -> bool {
    remove_flag(args, "--fresh")
}

pub(crate) fn remove_wrapper_force_unlock(args: &mut Vec<OsString>) -> bool {
    remove_flag(args, "--force-unlock")
}

pub(crate) fn remove_wrapper_no_autowire(args: &mut Vec<OsString>) -> bool {
    remove_flag(args, "--no-autowire")
}

pub(crate) fn remove_wrapper_no_exit_prompt(args: &mut Vec<OsString>) -> bool {
    remove_flag(args, "--no-exit-prompt")
}

/// Whether the launch asked for yolo, and whether it used the retired
/// `--true-yolo` spelling (a hidden alias of `--yolo`).
pub(crate) fn take_wrapper_yolo(yolo_flag: bool, true_yolo_flag: bool, native_args: &mut Vec<OsString>) -> (bool, bool) {
    let trailing_yolo = remove_wrapper_yolo(native_args);
    let true_yolo = true_yolo_flag | remove_wrapper_true_yolo(native_args);
    (yolo_flag || trailing_yolo || true_yolo, true_yolo)
}

/// Terminal notes for the retired true-yolo spellings.
pub(crate) fn yolo_deprecation_notes(true_yolo_flag: bool, config_true_yolo: bool) -> Vec<&'static str> {
    let mut notes = Vec::new();
    if true_yolo_flag {
        notes.push("ai-memory: --true-yolo is now the same as --yolo; use --yolo");
    }
    if config_true_yolo {
        notes.push(
            "ai-memory: claude_true_yolo is deprecated and ignored: --yolo on Claude always forces bypassPermissions now; remove it from config.toml",
        );
    }
    notes
}

/// What the invocation asked for about ai-jail.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum JailRequest {
    /// Neither flag: the interactive `--yolo` offer.
    Unspecified,
    /// `--no-jail`.
    Never,
    /// `--jail` (empty list: smart defaults) or `--jail=LIST`.
    Explicit(String),
}

/// `--jail`/`--no-jail` found among the native arguments.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub(crate) struct TrailingJail {
    pub(crate) jail: Option<String>,
    pub(crate) no_jail: bool,
}

/// Strip `--jail`, `--jail=LIST` and `--no-jail` from the native arguments;
/// the last `--jail` wins.
pub(crate) fn remove_wrapper_jail(args: &mut Vec<OsString>) -> TrailingJail {
    let mut found = TrailingJail::default();
    args.retain(|arg| {
        let Some(arg) = arg.to_str() else { return true };
        if arg == "--no-jail" {
            found.no_jail = true;
            return false;
        }
        if arg == "--jail" {
            found.jail = Some(String::new());
            return false;
        }
        if let Some(list) = arg.strip_prefix("--jail=") {
            found.jail = Some(list.to_owned());
            return false;
        }
        true
    });
    found
}

/// The leading flags merged with the trailing ones (later in argv, so they win).
pub(crate) fn jail_request(jail: Option<String>, no_jail: bool, trailing: TrailingJail) -> Result<JailRequest> {
    let jail = trailing.jail.or(jail);
    let no_jail = no_jail || trailing.no_jail;
    match (jail, no_jail) {
        (Some(_), true) => Err(anyhow!("--jail and --no-jail cannot be used together")),
        (Some(list), false) => Ok(JailRequest::Explicit(list)),
        (None, true) => Ok(JailRequest::Never),
        (None, false) => Ok(JailRequest::Unspecified),
    }
}

/// Before the post-run menu replaces the native argv, keep the wrapper
/// options that were typed after the harness.
pub(crate) fn preserve_trailing_run_options(args: &mut RunArgs) {
    args.yolo |= remove_wrapper_yolo(&mut args.native_args);
    args.true_yolo |= remove_wrapper_true_yolo(&mut args.native_args);
    args.no_autowire |= remove_wrapper_no_autowire(&mut args.native_args);
    args.no_exit_prompt |= remove_wrapper_no_exit_prompt(&mut args.native_args);
    let trailing_jail = remove_wrapper_jail(&mut args.native_args);
    if trailing_jail.jail.is_some() {
        args.jail = trailing_jail.jail;
    }
    args.no_jail |= trailing_jail.no_jail;
}

#[cfg(test)]
mod tests {
    use super::*;

    fn os(args: &[&str]) -> Vec<OsString> {
        args.iter().map(OsString::from).collect()
    }

    #[test]
    fn trailing_wrapper_flags_leave_the_native_argv() {
        let mut native = os(&["--model", "x", "--true-yolo", "--jail=github", "--fresh", "--no-exit-prompt"]);
        assert_eq!(take_wrapper_yolo(false, false, &mut native), (true, true));
        assert!(remove_wrapper_fresh(&mut native) && remove_wrapper_no_exit_prompt(&mut native));
        let trailing = remove_wrapper_jail(&mut native);
        assert_eq!(native, os(&["--model", "x"]));
        assert_eq!(jail_request(Some(String::new()), false, trailing).unwrap(), JailRequest::Explicit("github".into()));
        assert!(jail_request(None, true, TrailingJail { jail: Some(String::new()), no_jail: false }).is_err());
        assert_eq!(jail_request(None, false, TrailingJail::default()).unwrap(), JailRequest::Unspecified);
        assert_eq!(yolo_deprecation_notes(true, false).len(), 1);
    }
}
