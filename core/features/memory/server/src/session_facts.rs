//! What a session left in the store, as facts for its handoff (plan 22,
//! phase C: "o nosso lista os prompts, os arquivos editados e o último
//! estado, só com o que foi capturado"). Upstream's rule-based handoff kept
//! the first and last prompt and said "Single-prompt session" after a
//! session with 10 edits (proof of concept, 2026-11-15). This reads the
//! session's observations: the prompts, the tools by name (`[ingest]
//! record_tool_names`, engine.rs), the files the edit tools named (the
//! `file_path` column, `[ingest] index_file_paths` with file_claim.rs), and
//! the last assistant message when one was captured. The rendering states
//! facts only; nothing in it tells the next agent what to do.

use std::collections::BTreeMap;

use ai_memory_core::{ProjectId, SessionId, WorkspaceId};
use ai_memory_store::{ReaderPool, StoreResult};

/// Claude Code's tools that change a file.
const EDIT_TOOLS: [&str; 4] = ["Edit", "Write", "MultiEdit", "NotebookEdit"];
/// Prompt and message text kept per line, in characters.
const LINE_CHARS: usize = 160;
const LAST_CHARS: usize = 600;
/// Prompts listed: the first ones and the last ones of a longer session.
const PROMPTS_HEAD: usize = 8;
const PROMPTS_TAIL: usize = 4;
/// Files listed in the handoff.
pub(crate) const MAX_FILES: usize = 40;

/// The facts of one session.
#[derive(Debug, Default, PartialEq)]
pub(crate) struct Facts {
    /// Each prompt's text (bodies cut at 2,000 characters by the query).
    pub(crate) prompts: Vec<String>,
    /// Edited files, first edit first, each once.
    pub(crate) edited: Vec<String>,
    /// Completed tool calls by tool name.
    pub(crate) tools: BTreeMap<String, usize>,
    pub(crate) last_assistant: Option<String>,
}

/// The tool a PostToolUse title names: `tool file: Edit` -> `Edit`; a bare
/// family (`tool non-file`) names none.
fn tool_name(title: &str) -> Option<&str> {
    let rest = title.strip_prefix("tool ")?;
    rest.split_once(": ").map(|(_, name)| name.trim()).filter(|n| !n.is_empty())
}

/// A harness block delivered as a prompt (`<task-notification>`, a
/// teammate's message) is not the person's words.
fn is_person_prompt(text: &str) -> bool {
    let t = text.trim();
    !t.is_empty() && !t.starts_with('<')
}

impl Facts {
    /// One observation, in capture order.
    pub(crate) fn add(&mut self, kind: &str, title: &str, body: &str, file_path: Option<String>) {
        match kind {
            "user-prompt" => {
                let text = if body.is_empty() { title } else { body };
                if is_person_prompt(text) {
                    self.prompts.push(text.trim().to_string());
                }
            }
            "post-tool-use" => {
                let name = tool_name(title);
                *self.tools.entry(name.unwrap_or("(unnamed)").to_string()).or_default() += 1;
                if let (Some(name), Some(path)) = (name, file_path)
                    && EDIT_TOOLS.contains(&name)
                    && !self.edited.contains(&path)
                {
                    self.edited.push(path);
                }
            }
            "stop" if !body.trim().is_empty() => self.last_assistant = Some(body.trim().to_string()),
            _ => {}
        }
    }

    /// Read a session's observations in one scope.
    pub(crate) async fn load(reader: &ReaderPool, ws: WorkspaceId, proj: ProjectId, session: SessionId) -> StoreResult<Self> {
        reader
            .with_conn(move |conn| {
                let mut stmt = conn.prepare(
                    "SELECT kind, title, CASE WHEN kind IN ('user-prompt', 'stop') THEN substr(body, 1, 2000) ELSE '' END, \
                            file_path \
                     FROM observations WHERE session_id = ?1 AND workspace_id = ?2 AND project_id = ?3 \
                     ORDER BY created_at, rowid",
                )?;
                let mut facts = Facts::default();
                let mut rows = stmt.query(rusqlite::params![session.as_bytes(), ws.as_bytes(), proj.as_bytes()])?;
                while let Some(row) = rows.next()? {
                    let (kind, title, body): (String, String, String) = (row.get(0)?, row.get(1)?, row.get(2)?);
                    facts.add(&kind, &title, &body, row.get(3)?);
                }
                Ok(facts)
            })
            .await
    }
}

fn first_line(text: &str, max: usize) -> String {
    let line = text.lines().find(|l| !l.trim().is_empty()).unwrap_or("").trim();
    cut(line, max)
}

fn cut(text: &str, max: usize) -> String {
    if text.chars().count() <= max {
        return text.to_string();
    }
    let kept: String = text.chars().take(max).collect();
    format!("{kept}…")
}

/// Text on one line, for the last prompt and message.
fn flat(text: &str) -> String {
    text.split_whitespace().collect::<Vec<_>>().join(" ")
}

fn plural(n: usize, one: &str, many: &str) -> String {
    format!("{n} {}", if n == 1 { one } else { many })
}

/// The handoff's summary and its files. `failed`: upstream's "last failed
/// tool call" fact, kept when it found one.
pub(crate) fn render(facts: &Facts, failed: Option<&str>) -> (String, Vec<String>) {
    let calls: usize = facts.tools.values().sum();
    let mut out = format!(
        "Session with {}, {} and {}.",
        plural(facts.prompts.len(), "prompt", "prompts"),
        plural(calls, "tool call", "tool calls"),
        plural(facts.edited.len(), "file edited", "files edited"),
    );
    let n = facts.prompts.len();
    if n > 0 {
        out.push_str("\n\nPrompts:\n");
        let shown: Vec<usize> = if n <= PROMPTS_HEAD + PROMPTS_TAIL {
            (0..n).collect()
        } else {
            (0..PROMPTS_HEAD).chain(n - PROMPTS_TAIL..n).collect()
        };
        for (k, &i) in shown.iter().enumerate() {
            if k == PROMPTS_HEAD && n > PROMPTS_HEAD + PROMPTS_TAIL {
                out.push_str(&format!("   ({} more prompts)\n", n - PROMPTS_HEAD - PROMPTS_TAIL));
            }
            out.push_str(&format!("{}. {}\n", i + 1, first_line(&facts.prompts[i], LINE_CHARS)));
        }
    }
    if !facts.tools.is_empty() {
        let mut tools: Vec<(&String, &usize)> = facts.tools.iter().collect();
        tools.sort_by(|a, b| b.1.cmp(a.1).then_with(|| a.0.cmp(b.0)));
        let list: Vec<String> = tools.iter().map(|(name, count)| format!("{name} ×{count}")).collect();
        out.push_str(&format!("\nTools used: {}.\n", list.join(", ")));
    }
    if facts.edited.len() > MAX_FILES {
        out.push_str(&format!("Files edited: the first {MAX_FILES} of {} are listed.\n", facts.edited.len()));
    }
    if let Some(last) = facts.prompts.last().filter(|_| n > 1) {
        out.push_str(&format!("\nLast prompt: {}\n", cut(&flat(last), LAST_CHARS)));
    }
    if let Some(message) = &facts.last_assistant {
        out.push_str(&format!("\nLast assistant message: {}\n", cut(&flat(message), LAST_CHARS)));
    }
    if let Some(failed) = failed {
        out.push_str(&format!("\nLast failed tool call: {failed}\n"));
    }
    let files = facts.edited.iter().take(MAX_FILES).cloned().collect();
    (out.trim_end().to_string(), files)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_session_with_ten_edits_lists_the_ten_files_and_only_facts() {
        let mut facts = Facts::default();
        facts.add("user-prompt", "rename the parser", "rename the parser\nacross the crate", None);
        facts.add("user-prompt", "", "<task-notification>done</task-notification>", None);
        for i in 0..10 {
            facts.add("post-tool-use", "tool file: Read", "", Some(format!("src/r{i}.rs")));
            facts.add("post-tool-use", "tool file: Edit", "", Some(format!("src/f{i}.rs")));
        }
        facts.add("post-tool-use", "tool file: Edit", "", Some("src/f0.rs".into()));
        facts.add("post-tool-use", "tool non-file: Bash", "", None);
        facts.add("user-prompt", "now run the tests", "now run the tests", None);
        let (summary, files) = render(&facts, None);
        assert_eq!(files, (0..10).map(|i| format!("src/f{i}.rs")).collect::<Vec<_>>(), "edited files once each; reads are not edits");
        assert!(summary.starts_with("Session with 2 prompts, 22 tool calls and 10 files edited."), "{summary}");
        assert!(summary.contains("1. rename the parser\n2. now run the tests"), "{summary}");
        assert!(summary.contains("Tools used: Edit ×11, Read ×10, Bash ×1."), "{summary}");
        assert!(summary.contains("Last prompt: now run the tests"), "{summary}");
        for imperative in ["Continue", "Check ", "Run ", "should"] {
            assert!(!summary.contains(imperative), "{imperative} in {summary}");
        }
    }

    #[test]
    fn long_sessions_are_capped() {
        let mut facts = Facts::default();
        for i in 0..30 {
            facts.add("user-prompt", "", &format!("prompt {i} {}", "x".repeat(300)), None);
        }
        for i in 0..50 {
            facts.add("post-tool-use", "tool file: Write", "", Some(format!("f{i}")));
        }
        facts.add("stop", "", "All 30 done.", None);
        let (summary, files) = render(&facts, Some("Bash: Exit code 1"));
        assert_eq!(files.len(), MAX_FILES);
        assert!(summary.contains("(18 more prompts)") && summary.contains("30. prompt 29"), "{summary}");
        assert!(!summary.contains("9. prompt 8"), "{summary}");
        assert!(summary.contains("Files edited: the first 40 of 50 are listed."));
        assert!(summary.contains("Last assistant message: All 30 done.") && summary.contains("Last failed tool call: Bash: Exit code 1"));
    }
}
