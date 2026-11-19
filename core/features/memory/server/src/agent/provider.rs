//! The memory agent's `ai_memory_llm::LlmProvider`: the owner's own Claude
//! Code, one `claude -p` per request (claude_cli.rs), in the project's
//! account (ADR 0029, plan 22 phase G, 2026-11-16). Upstream's jobs
//! (consolidator, auto-improve, experience, dream, profile, bootstrap) take
//! it as they take any provider; none of them knows it is a CLI.
//!
//! Every call is checked against the day's spend first (a job may make
//! several calls, and upstream's own loops do not know the budget) and
//! written to the ledger after, with its cost, whether it worked, and the
//! Claude Code version. Before the ledger line, the call's request and
//! response go to the audit folder (audit.rs, plan 35 D) and the line names
//! that file in `call`.
//!
//! How a request becomes the stdin text: the system prompt goes in
//! `--system-prompt`; a single user message is sent as it is; a request with
//! several messages (upstream's are single-turn today) is sent as a
//! transcript with a `## User` / `## Assistant` heading per message, in
//! order, since `claude -p` takes one prompt. A structured request adds the
//! JSON Schema and the instruction to answer with one JSON value only, the
//! way upstream's Cursor CLI provider does (the CLI has no schema mode); the
//! answer is parsed leniently (a code fence or prose around it is removed)
//! and serde, in upstream's typed wrapper, is the validation. `max_tokens`
//! and `temperature` have no `claude -p` flag: the call budget bounds the
//! output instead.

use std::path::PathBuf;
use std::sync::Mutex;

use ai_memory_llm::{ChatRequest, ChatResponse, LlmError, LlmProvider, LlmResult, Role, Usage};
use async_trait::async_trait;

use super::audit;
use super::claude_cli::{self, Exchange, Invocation};
use super::ledger::{self, Entry};

/// What the ledger says about the calls of one job step.
#[derive(Debug, Clone, Default)]
pub(crate) struct Label {
    pub(crate) kind: &'static str,
    pub(crate) workspace: String,
    pub(crate) project: String,
    pub(crate) session: Option<String>,
    /// The ending session that set the job off, when `session` is another
    /// (the reviewed one: plan 35 G).
    pub(crate) trigger: Option<String>,
}

pub(crate) struct ClaudeProvider {
    inv: Invocation,
    daily_budget_usd: f64,
    data_dir: PathBuf,
    label: Label,
    version: Option<String>,
    /// Calls made and their cost, for the job's summary.
    spent: Mutex<(usize, f64)>,
}

/// Used when a request has no system prompt: without `--system-prompt`
/// Claude Code would send its own, much larger, one.
const PLAIN_SYSTEM: &str = "Answer the request in the message.";

impl ClaudeProvider {
    pub(crate) fn new(inv: Invocation, daily_budget_usd: f64, data_dir: PathBuf, label: Label, version: Option<String>) -> Self {
        Self { inv, daily_budget_usd, data_dir, label, version, spent: Mutex::new((0, 0.0)) }
    }

    /// (calls, cost) so far.
    pub(crate) fn spent(&self) -> (usize, f64) {
        *self.spent.lock().unwrap_or_else(|e| e.into_inner())
    }

    fn record(&self, cost_usd: f64, error: Option<String>, call: Option<String>) {
        {
            let mut spent = self.spent.lock().unwrap_or_else(|e| e.into_inner());
            spent.0 += 1;
            spent.1 += cost_usd;
        }
        ledger::append(&self.data_dir, &Entry {
            at: ledger::now(),
            kind: self.label.kind.into(),
            workspace: self.label.workspace.clone(),
            project: self.label.project.clone(),
            session: self.label.session.clone(),
            trigger: self.label.trigger.clone(),
            cost_usd,
            ok: error.is_none(),
            error,
            claude_version: self.version.clone(),
            model: self.inv.model.clone(),
            call,
        });
    }

    /// The call's audit file: who asked, what was sent, what came back.
    fn audit(&self, system: &str, prompt: &str, seen: &Exchange, error: Option<&str>) -> Option<String> {
        let stdout = serde_json::from_str::<serde_json::Value>(seen.stdout.trim())
            .unwrap_or_else(|_| capped(&seen.stdout).into());
        let record = serde_json::json!({
            "at": ledger::now(),
            "kind": self.label.kind,
            "workspace": self.label.workspace,
            "project": self.label.project,
            "session": self.label.session,
            "trigger": self.label.trigger,
            "model": self.inv.model,
            "claude_version": self.version,
            "request": {"argv": seen.argv, "system": capped(system), "stdin": capped(prompt)},
            "response": {"exit": seen.exit, "millis": seen.millis, "stdout": stdout, "stderr": seen.stderr, "error": error},
        });
        audit::keep_call(&self.data_dir, self.label.kind, &record)
    }

    /// One call: budget check, run, ledger.
    async fn call(&self, request: &ChatRequest, schema: Option<&serde_json::Value>) -> LlmResult<claude_cli::Output> {
        if !ledger::fits(&self.data_dir, self.inv.call_budget_usd, self.daily_budget_usd) {
            return Err(LlmError::NotConfigured("the memory agent's daily budget is reached".into()));
        }
        let system = request.system.as_deref().filter(|s| !s.trim().is_empty()).unwrap_or(PLAIN_SYSTEM);
        let prompt = prompt_text(request, schema);
        let (result, seen) = claude_cli::run(&self.inv, system, &prompt).await;
        match result {
            Ok(output) if output.is_error => {
                let error = claude_cli::error_of(&output);
                let call = self.audit(system, &prompt, &seen, Some(&short(&error)));
                self.record(output.total_cost_usd, Some(short(&error)), call);
                Err(error)
            }
            Ok(output) => {
                let call = self.audit(system, &prompt, &seen, None);
                self.record(output.total_cost_usd, None, call);
                Ok(output)
            }
            Err(error) => {
                let call = self.audit(system, &prompt, &seen, Some(&short(&error)));
                self.record(0.0, Some(short(&error)), call);
                Err(error)
            }
        }
    }
}

/// A text the audit stores whole up to 2 MiB: a prompt near the model's
/// context is under 1 MiB, and 500 files of 8 MiB (the output cap) would be
/// 4 GB of disk.
fn capped(text: &str) -> String {
    const CAP: usize = 2 << 20;
    if text.len() <= CAP {
        return text.to_owned();
    }
    let mut end = CAP;
    while !text.is_char_boundary(end) {
        end -= 1;
    }
    format!("{}\n[cut at {CAP} bytes of {}]", &text[..end], text.len())
}

/// An error for the ledger: its class and a short text.
fn short(error: &LlmError) -> String {
    let text = error.to_string();
    let cut: String = text.chars().take(160).collect();
    format!("{}: {cut}", error.class())
}

/// The stdin text of a request (see the module comment).
pub(crate) fn prompt_text(request: &ChatRequest, schema: Option<&serde_json::Value>) -> String {
    let mut text = match request.messages.as_slice() {
        [only] if only.role == Role::User => only.content.clone(),
        messages => messages
            .iter()
            .map(|m| format!("## {}\n{}", if m.role == Role::User { "User" } else { "Assistant" }, m.content))
            .collect::<Vec<_>>()
            .join("\n\n"),
    };
    if let Some(schema) = schema {
        text.push_str("\n\n## Output\nAnswer with exactly one JSON value that matches this JSON Schema, and nothing before or after it:\n");
        text.push_str(&schema.to_string());
        text.push('\n');
    }
    text
}

/// The JSON value in an answer: the whole text, or inside a code fence, or
/// from the first `{` to the last `}`.
pub(crate) fn json_in(text: &str) -> LlmResult<serde_json::Value> {
    let trimmed = text.trim();
    let unfenced = trimmed
        .strip_prefix("```")
        .map(|rest| rest.trim_start_matches(|c: char| c.is_ascii_alphanumeric()).trim().trim_end_matches('`').trim())
        .unwrap_or(trimmed);
    for candidate in [trimmed, unfenced] {
        if let Ok(value) = serde_json::from_str(candidate) {
            return Ok(value);
        }
    }
    if let (Some(start), Some(end)) = (unfenced.find('{'), unfenced.rfind('}'))
        && end > start
        && let Ok(value) = serde_json::from_str(&unfenced[start..=end])
    {
        return Ok(value);
    }
    Err(LlmError::UnexpectedShape(format!("claude -p did not answer with JSON: {}", claude_cli::excerpt(trimmed))))
}

#[async_trait]
impl LlmProvider for ClaudeProvider {
    fn name(&self) -> &'static str {
        "claude-code"
    }

    fn model(&self) -> &str {
        &self.inv.model
    }

    async fn complete(&self, request: ChatRequest) -> LlmResult<ChatResponse> {
        let output = self.call(&request, None).await?;
        let usage = output.usage.as_ref().map(|u| Usage { input_tokens: u.input_tokens, output_tokens: u.output_tokens });
        let model = output.model_usage.keys().next().cloned().unwrap_or_else(|| self.inv.model.clone());
        Ok(ChatResponse { text: output.result, usage, model })
    }

    async fn complete_structured_raw(&self, request: ChatRequest, schema: serde_json::Value) -> LlmResult<serde_json::Value> {
        let output = self.call(&request, Some(&schema)).await?;
        json_in(&output.result)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use ai_memory_llm::ChatMessage;

    #[test]
    fn messages_and_schema_become_one_prompt() {
        let one = ChatRequest::user_prompt("hello");
        assert_eq!(prompt_text(&one, None), "hello");
        let mut two = one.clone();
        two.messages.push(ChatMessage::assistant("hi"));
        two.messages.push(ChatMessage::user("again"));
        assert_eq!(prompt_text(&two, None), "## User\nhello\n\n## Assistant\nhi\n\n## User\nagain");
        let with = prompt_text(&one, Some(&serde_json::json!({"title": "X"})));
        assert!(with.starts_with("hello\n\n## Output\n") && with.ends_with("{\"title\":\"X\"}\n"));
    }

    #[test]
    fn json_is_found_in_a_fence_or_in_prose() {
        assert_eq!(json_in("{\"a\":1}").unwrap()["a"], 1);
        assert_eq!(json_in("```json\n{\"a\":2}\n```").unwrap()["a"], 2);
        assert_eq!(json_in("Here it is: {\"a\":3} done").unwrap()["a"], 3);
        assert!(json_in("no json").is_err());
    }
}
