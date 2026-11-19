//! `--yolo` on a terminal: the warning, its `[Y/n]` confirmation and, when
//! ai-jail is usable, the offer to re-run the session inside it; and the
//! terminal emphasis the jail prompts share.
//!
//! Copied from ai-memory v3.4.7 (fa0ec25; compared at v3.5.0, 411d90d, on 2026-11-19: unchanged), crates/ai-memory-cli/src/commands/
//! run.rs: `yolo_decision`, `YoloConfirmation`, `read_yolo_confirmation` and
//! `Paint` (with `terminal::color_enabled`). Changed for Cadex (2026-11-16):
//! no i18n, and `Paint` writes the SGR codes crossterm's `Stylize` writes
//! (crossterm is not in this crate's tree).

use std::io::{self, IsTerminal as _};

/// Terminal emphasis: plain off a terminal, with `NO_COLOR`, or on a dumb one.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) struct Paint {
    pub(crate) color: bool,
}

impl Paint {
    #[cfg(test)]
    pub(crate) const PLAIN: Self = Self { color: false };

    pub(crate) fn for_stderr() -> Self {
        let tty = io::stderr().is_terminal();
        let no_color = std::env::var_os("NO_COLOR").is_some();
        let dumb = std::env::var_os("TERM").is_some_and(|term| term == "dumb");
        Self { color: tty && !no_color && !dumb }
    }

    fn with(self, text: &str, sgr: &str) -> String {
        if self.color { format!("\x1b[{sgr}m{text}\x1b[0m") } else { text.to_owned() }
    }

    pub(crate) fn bold(self, text: &str) -> String {
        self.with(text, "1")
    }

    pub(crate) fn green(self, text: &str) -> String {
        self.with(text, "38;5;10")
    }

    pub(crate) fn yellow(self, text: &str) -> String {
        self.with(text, "38;5;11")
    }

    pub(crate) fn red(self, text: &str) -> String {
        self.with(text, "38;5;9")
    }

    pub(crate) fn cyan(self, text: &str) -> String {
        self.with(text, "38;5;14")
    }

    pub(crate) fn dim(self, text: &str) -> String {
        self.with(text, "38;5;8")
    }
}

/// `Enter`, `y`, `yes` and anything else proceed; only `n`/`no` decline.
pub(crate) fn yolo_decision(confirmed_line: &str) -> bool {
    !matches!(confirmed_line.trim().to_lowercase().as_str(), "n" | "no" | "não" | "nao")
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) struct YoloConfirmation {
    pub(crate) proceed: bool,
    pub(crate) jail: bool,
}

/// The warning, then the offer when ai-jail is usable, on injected I/O.
pub(crate) fn read_yolo_confirmation(paint: Paint, ai_jail_available: bool, input: &mut impl io::BufRead,
    output: &mut impl io::Write) -> io::Result<YoloConfirmation> {
    writeln!(output, "{}", paint.yellow("⚠  --yolo runs every tool call with no confirmation. An agent can delete"))?;
    writeln!(output, "{}", paint.dim("   files, run any command, and reach the network unsupervised."))?;
    write!(output, "{}", paint.bold("   Proceed? [Y/n] "))?;
    output.flush()?;
    let mut line = String::new();
    input.read_line(&mut line)?;
    if !yolo_decision(&line) {
        return Ok(YoloConfirmation { proceed: false, jail: false });
    }
    if !ai_jail_available {
        return Ok(YoloConfirmation { proceed: true, jail: false });
    }
    write!(output, "🔒 {}", paint.bold("ai-jail is installed. Re-run this session inside it? [Y/n] "))?;
    output.flush()?;
    let mut jail_line = String::new();
    input.read_line(&mut jail_line)?;
    Ok(YoloConfirmation { proceed: true, jail: yolo_decision(&jail_line) })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn confirm(input: &str, available: bool) -> (YoloConfirmation, String) {
        let mut output = Vec::new();
        let answer = read_yolo_confirmation(Paint::PLAIN, available, &mut input.as_bytes(), &mut output).unwrap();
        (answer, String::from_utf8(output).unwrap())
    }

    #[test]
    fn enter_proceeds_no_declines_and_the_jail_offer_reads_its_own_line() {
        let (answer, text) = confirm("\n", false);
        assert_eq!(answer, YoloConfirmation { proceed: true, jail: false });
        assert!(text.contains("Proceed? [Y/n]") && !text.contains("ai-jail"));
        assert_eq!(confirm("no\n", true).0, YoloConfirmation { proceed: false, jail: false });
        assert_eq!(confirm("y\n\n", true).0, YoloConfirmation { proceed: true, jail: true });
        assert_eq!(confirm("y\nn\n", true).0, YoloConfirmation { proceed: true, jail: false });
        assert_eq!(Paint { color: true }.bold("x"), "\x1b[1mx\x1b[0m");
    }
}
