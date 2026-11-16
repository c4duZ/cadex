//! What the import keeps of each transcript event, as the live hook would.
//!
//! Copied, reduced, from ai-memory v3.4.7 (fa0ec25),
//! crates/ai-memory-cli/src/commands/transcript_capture.rs (`TranscriptCapture::
//! decide`, `orphan_result`, `decide_call`, `record_call`, `call_id`,
//! `shell_mode_output`, `skipped_record`). The cli crate is not a library, and
//! this part of it is the trust boundary of the import, so it is kept close
//! to upstream; see the update procedure in core/features/memory/CLAUDE.md.
//!
//! Reduced because Cadex sets no capture policy (no `.ai-memory.toml`
//! `ignore_paths`, no allowlist mode): with upstream's inactive policy every
//! message is kept except a `!` command's output, a tool the policy does not
//! recognize keeps only its family, and a result follows its call. The
//! checks for other checkouts' markers and for Codex's memory agent have
//! nothing to act on here.

use std::collections::HashMap;

use ai_memory_core::{NewWorkstreamEvent, WorkstreamEventKind};
use ai_memory_hooks::{CapturePolicy, CaptureSource, ToolFamily, tool_call_payload};
use ai_memory_workstream::SKIPPED_RECORD_KEY;
use serde_json::Value;

/// What the import does with one event.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum EventCapture {
    Keep,
    /// A tool the policy does not recognize: record that it ran, never its
    /// arguments or output (the live server stores only the family).
    Unrecognized,
    Drop,
}

impl EventCapture {
    const fn rank(self) -> u8 {
        match self {
            Self::Keep => 0,
            Self::Unrecognized => 1,
            Self::Drop => 2,
        }
    }

    fn stricter(self, other: Self) -> Self {
        if other.rank() > self.rank() { other } else { self }
    }
}

/// One decision per event, in transcript order (upstream `decide` with an
/// inactive policy). A result with an id takes its call's decision; without
/// one, the strictest call since the last user message; with no call, it is
/// an orphan and keeps no output.
pub(crate) fn decide(events: &[NewWorkstreamEvent]) -> Vec<EventCapture> {
    let policy = CapturePolicy::resolve(CaptureSource::Absent, "", None);
    let mut by_id: HashMap<&str, EventCapture> = HashMap::new();
    let mut turn: Vec<EventCapture> = Vec::new();
    let mut out = Vec::with_capacity(events.len());
    for event in events {
        let capture = match event.kind {
            WorkstreamEventKind::ToolCall => {
                let capture = decide_call(&policy, event);
                if let Some(id) = call_id(event) {
                    by_id.insert(id, capture);
                }
                turn.push(capture);
                capture
            }
            WorkstreamEventKind::ToolResult => match call_id(event) {
                Some(id) => by_id.get(id).copied().unwrap_or(EventCapture::Unrecognized),
                None => turn.iter().copied().reduce(EventCapture::stricter).unwrap_or(EventCapture::Unrecognized),
            },
            WorkstreamEventKind::Message => {
                if matches!(event.role.as_deref(), Some("user" | "human")) {
                    turn.clear();
                }
                if shell_mode_output(event) { EventCapture::Drop } else { EventCapture::Keep }
            }
            WorkstreamEventKind::Compaction | WorkstreamEventKind::Checkpoint | WorkstreamEventKind::Annotation => {
                if skipped_record(event) {
                    turn.push(EventCapture::Unrecognized);
                }
                EventCapture::Keep
            }
        };
        out.push(capture);
    }
    out
}

/// A call rebuilt in its agent's hook shape and asked of the policy: kept
/// when the policy knows the tool's family.
fn decide_call(policy: &CapturePolicy, event: &NewWorkstreamEvent) -> EventCapture {
    let (name, args) = recorded_call(event);
    let raw = tool_call_payload(event.agent, name, args.as_ref(), call_id(event));
    let family = policy.inspect(event.agent, &raw, "").protocol().tool_family();
    if family == ToolFamily::Unknown { EventCapture::Unrecognized } else { EventCapture::Keep }
}

/// Claude Code records a `!` command's output as a user message opening with
/// one of these blocks; live capture never receives it.
pub(crate) fn shell_mode_output(event: &NewWorkstreamEvent) -> bool {
    const TAGS: [&str; 4] = ["<bash-stdout>", "<bash-stderr>", "<local-command-stdout>", "<local-command-stderr>"];
    event.agent == ai_memory_core::AgentKind::ClaudeCode
        && TAGS.iter().any(|tag| event.content.trim_start().starts_with(tag))
}

/// The exporter's marker for a record it skipped as oversized.
pub(crate) fn skipped_record(event: &NewWorkstreamEvent) -> bool {
    event.kind == WorkstreamEventKind::Annotation
        && event.metadata.get(SKIPPED_RECORD_KEY).and_then(Value::as_bool) == Some(true)
}

/// The native id linking a call and its result.
pub(crate) fn call_id(event: &NewWorkstreamEvent) -> Option<&str> {
    ["tool_use_id", "tool_call_id"]
        .iter()
        .find_map(|key| event.metadata.get(*key).and_then(Value::as_str))
        .filter(|id| !id.is_empty())
}

/// A recorded call's tool name and arguments (`{name}: {json}`); `None`
/// arguments when they cannot be recovered.
pub(crate) fn recorded_call(event: &NewWorkstreamEvent) -> (&str, Option<Value>) {
    let name = event
        .metadata
        .get("tool")
        .and_then(Value::as_str)
        .filter(|name| !name.is_empty())
        .or_else(|| event.content.split_once(": ").map(|(name, _)| name))
        .unwrap_or("");
    let args = event
        .content
        .strip_prefix(name)
        .and_then(|rest| rest.strip_prefix(':'))
        .map(str::trim)
        .and_then(|rest| if rest.is_empty() { Some(Value::Null) } else { serde_json::from_str(rest).ok() });
    (name, args)
}

#[cfg(test)]
mod tests {
    use super::*;
    use ai_memory_core::AgentKind;

    fn event(kind: WorkstreamEventKind, role: Option<&str>, content: &str, metadata: Value) -> NewWorkstreamEvent {
        NewWorkstreamEvent {
            event_id: content.into(),
            agent: AgentKind::ClaudeCode,
            native_session_id: "s".into(),
            source_record_id: None,
            kind,
            role: role.map(Into::into),
            content: content.into(),
            occurred_at: None,
            metadata,
        }
    }

    #[test]
    fn known_tools_are_kept_unknown_ones_keep_only_their_family_and_shell_output_is_dropped() {
        use WorkstreamEventKind::*;
        let events = [
            event(Message, Some("user"), "read it", Value::Null),
            event(ToolCall, None, r#"Read: {"file_path":"/r/a.rs"}"#, serde_json::json!({"tool_use_id": "t1", "tool": "Read"})),
            event(ToolResult, None, "fn main() {}", serde_json::json!({"tool_use_id": "t1"})),
            event(ToolCall, None, "mystery_tool: {}", serde_json::json!({"tool_use_id": "t2", "tool": "mystery_tool"})),
            event(ToolResult, None, "secret", serde_json::json!({"tool_use_id": "t2"})),
            event(ToolResult, None, "orphan", serde_json::json!({"tool_use_id": "t9"})),
            event(Message, Some("user"), "<bash-stdout>ls</bash-stdout>", Value::Null),
        ];
        use EventCapture::*;
        assert_eq!(decide(&events), vec![Keep, Keep, Keep, Unrecognized, Unrecognized, Unrecognized, Drop]);
    }
}
