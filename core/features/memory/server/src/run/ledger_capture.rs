//! The checkout's `[capture] ignore_paths` applied to a transcript before it
//! becomes the run's ledger or the next agent's dossier: an excluded tool
//! call and its result never reach the engine or the other vendor
//! (GHSA-h8wj-74hc-vjjp).
//!
//! Copied from ai-memory v3.4.7 (fa0ec25), crates/ai-memory-cli/src/commands/
//! transcript_capture.rs: `EventCapture` (with `MetadataOnly`),
//! `TranscriptCapture::{decide, filter_ledger_events, orphan_result,
//! drops_codex_memory_agent, decide_call}`, `inspect_call`, `record_cwd` and
//! `withheld`; the event helpers are replay_capture.rs's copies. Changed for
//! Cadex (2026-11-16): the policy is capture.rs's (marker.rs finds the
//! marker); Cadex captures every repository (no allowlist gate); an event
//! recorded in another folder is kept only when that folder names the same
//! project (mcp_scope.rs's rule, standing in for upstream's
//! `routes_to_same_project`; there is one engine, so no server-route check)
//! and answers to both folders' policies; upstream's reroute of a call
//! naming another checkout's file (`tool_location_routing_cwd`,
//! `foreign_capture_decision`) is not repeated.

use std::collections::HashMap;
use std::path::Path;

use ai_memory_core::{AgentKind, NewWorkstreamEvent, WorkstreamEventKind};
use ai_memory_hooks::{CaptureDecision, CaptureDisposition, CapturePolicy, PolicyState, ToolFamily, tool_call_payload, valid_call_id};
use ai_memory_workstream::RECORD_CWD_KEY;
use serde_json::Value;

use crate::replay_capture::{call_id, recorded_call, shell_mode_output, skipped_record};
use crate::{capture, marker, mcp_scope};

#[derive(Clone, Debug)]
enum EventCapture {
    Keep,
    Drop,
    Unrecognized,
    MetadataOnly(CaptureDecision),
}

impl EventCapture {
    const fn rank(&self) -> u8 {
        match self {
            Self::Keep => 0,
            Self::Unrecognized => 1,
            Self::MetadataOnly(_) => 2,
            Self::Drop => 3,
        }
    }

    fn stricter(self, other: Self) -> Self {
        if other.rank() > self.rank() { other } else { self }
    }

    fn from_decision(decision: CaptureDecision) -> Self {
        match decision.protocol().disposition() {
            CaptureDisposition::Keep => Self::Keep,
            CaptureDisposition::Drop => Self::Drop,
            CaptureDisposition::MetadataOnly => Self::MetadataOnly(decision),
        }
    }
}

/// The capture policy of the checkout a transcript was recorded in.
pub(crate) struct LedgerCapture {
    policy: CapturePolicy,
    cwd: String,
    inspection_cwd: String,
}

fn lexical(cwd: &str) -> String {
    marker::absolute_normalized(Path::new(cwd)).to_string_lossy().into_owned()
}

fn record_cwd(event: &NewWorkstreamEvent) -> Option<&str> {
    event.metadata.get(RECORD_CWD_KEY).and_then(Value::as_str).filter(|cwd| Path::new(cwd).is_absolute())
}

fn inspect_call(policy: &CapturePolicy, agent: AgentKind, raw: &Value, inspection_cwd: &str, unreadable: bool) -> EventCapture {
    let decision = policy.inspect(agent, raw, inspection_cwd);
    if unreadable && decision.protocol().tool_family() == ToolFamily::NonFile && policy.state() != PolicyState::Inactive {
        return EventCapture::Drop;
    }
    EventCapture::from_decision(decision)
}

/// The event with its content replaced by the tool family.
fn withheld(mut event: NewWorkstreamEvent, family: ToolFamily) -> NewWorkstreamEvent {
    let family = serde_json::to_value(family).ok().and_then(|v| v.as_str().map(str::to_owned)).unwrap_or_else(|| "unknown".into());
    let half = if event.kind == WorkstreamEventKind::ToolCall { "call" } else { "output" };
    event.content = format!("[{family} tool {half} withheld by the capture policy]");
    let mut metadata = serde_json::Map::new();
    for key in ["tool_use_id", "tool_call_id"] {
        if let Some(value) = event.metadata.get(key).filter(|v| v.as_str().is_some_and(valid_call_id)) {
            metadata.insert(key.into(), value.clone());
        }
    }
    event.metadata = Value::Object(metadata);
    event
}

impl LedgerCapture {
    pub(crate) fn for_checkout(cwd: &Path) -> Self {
        let cwd = cwd.to_string_lossy().into_owned();
        Self { policy: capture::policy(&cwd), inspection_cwd: lexical(&cwd), cwd }
    }

    fn orphan_result(&self) -> EventCapture {
        if self.policy.state() == PolicyState::Inactive { EventCapture::Unrecognized } else { EventCapture::Drop }
    }

    fn admits_elsewhere(&self, cwd: &str, seen: &mut HashMap<String, bool>) -> bool {
        *seen.entry(cwd.to_owned()).or_insert_with(|| {
            let here = mcp_scope::scope_of(&self.cwd, None);
            here.is_some() && here == mcp_scope::scope_of(cwd, None)
        })
    }

    fn drops_codex_memory_agent(&self, events: &[NewWorkstreamEvent]) -> bool {
        if ai_memory_core::is_codex_memory_agent_cwd(&self.cwd) {
            return true;
        }
        events.iter().any(|event| {
            event.agent == AgentKind::Codex
                && (record_cwd(event).is_some_and(ai_memory_core::is_codex_memory_agent_cwd)
                    || (event.kind == WorkstreamEventKind::Message
                        && matches!(event.role.as_deref(), Some("user" | "human"))
                        && ai_memory_core::looks_like_codex_memory_agent_prompt(&event.content)))
        })
    }

    fn decide_call(&self, event: &NewWorkstreamEvent, cwd: &str) -> EventCapture {
        let (name, args) = recorded_call(event);
        let unreadable = args.is_none();
        let raw = tool_call_payload(event.agent, name, args.as_ref(), call_id(event));
        let recognized = self.policy.inspect(event.agent, &raw, &self.inspection_cwd).protocol().tool_family() != ToolFamily::Unknown;
        let capture = if cwd == self.cwd {
            inspect_call(&self.policy, event.agent, &raw, &self.inspection_cwd, unreadable)
        } else {
            let there = lexical(cwd);
            inspect_call(&self.policy, event.agent, &raw, &there, unreadable)
                .stricter(inspect_call(&capture::policy(cwd), event.agent, &raw, &there, unreadable))
        };
        if recognized { capture } else { capture.stricter(EventCapture::Unrecognized) }
    }

    fn decide(&self, events: &[NewWorkstreamEvent]) -> Vec<EventCapture> {
        if self.drops_codex_memory_agent(events) {
            return vec![EventCapture::Drop; events.len()];
        }
        let mut elsewhere = HashMap::new();
        let mut by_id: HashMap<&str, EventCapture> = HashMap::new();
        let mut turn: Vec<EventCapture> = Vec::new();
        let mut out = Vec::with_capacity(events.len());
        for event in events {
            let cwd = record_cwd(event).unwrap_or(&self.cwd);
            let admitted = cwd == self.cwd || self.admits_elsewhere(cwd, &mut elsewhere);
            let capture = match event.kind {
                WorkstreamEventKind::ToolCall => {
                    let capture = if admitted { self.decide_call(event, cwd) } else { EventCapture::Drop };
                    if let Some(id) = call_id(event) {
                        by_id.insert(id, capture.clone());
                    }
                    turn.push(capture.clone());
                    capture
                }
                WorkstreamEventKind::ToolResult if !admitted => EventCapture::Drop,
                WorkstreamEventKind::ToolResult => match call_id(event) {
                    Some(id) => by_id.get(id).cloned().unwrap_or_else(|| self.orphan_result()),
                    None => turn.iter().cloned().reduce(EventCapture::stricter).unwrap_or_else(|| self.orphan_result()),
                },
                WorkstreamEventKind::Message => {
                    if matches!(event.role.as_deref(), Some("user" | "human")) {
                        turn.clear();
                    }
                    if admitted && !shell_mode_output(event) { EventCapture::Keep } else { EventCapture::Drop }
                }
                WorkstreamEventKind::Compaction | WorkstreamEventKind::Checkpoint | WorkstreamEventKind::Annotation => {
                    if skipped_record(event) {
                        turn.push(self.orphan_result());
                    }
                    if admitted { EventCapture::Keep } else { EventCapture::Drop }
                }
            };
            out.push(capture);
        }
        out
    }

    /// The events the policy keeps, the metadata-only ones stripped.
    pub(crate) fn filter_ledger_events(&self, events: Vec<NewWorkstreamEvent>) -> Vec<NewWorkstreamEvent> {
        let decisions = self.decide(&events);
        events
            .into_iter()
            .zip(decisions)
            .filter_map(|(event, capture)| match capture {
                EventCapture::Keep => Some(event),
                EventCapture::Drop => None,
                EventCapture::Unrecognized => Some(withheld(event, ToolFamily::Unknown)),
                EventCapture::MetadataOnly(decision) => Some(withheld(event, decision.protocol().tool_family())),
            })
            .map(|mut event| {
                if let Some(metadata) = event.metadata.as_object_mut() {
                    metadata.remove(RECORD_CWD_KEY);
                }
                event
            })
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

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
    fn an_ignored_path_withholds_its_call_and_result() {
        let tmp = tempfile::tempdir().unwrap();
        let repo = tmp.path().join("acme");
        std::fs::create_dir_all(&repo).unwrap();
        assert!(std::process::Command::new("git").args(["init", "-q"]).current_dir(&repo).status().unwrap().success());
        std::fs::write(repo.join(".ai-memory.toml"), "[capture]\nignore_paths = [\"secret/**\"]\n").unwrap();
        let read = |path: &str, id: &str| event(WorkstreamEventKind::ToolCall, None,
            &format!("Read: {}", json!({"file_path": repo.join(path)})), json!({"tool_use_id": id, "tool": "Read"}));
        let events = vec![
            event(WorkstreamEventKind::Message, Some("user"), "look", Value::Null),
            read("secret/key.env", "t1"),
            event(WorkstreamEventKind::ToolResult, None, "TOKEN=abc", json!({"tool_use_id": "t1"})),
            read("src/lib.rs", "t2"),
            event(WorkstreamEventKind::ToolResult, None, "fn main() {}", json!({"tool_use_id": "t2"})),
        ];
        let kept = LedgerCapture::for_checkout(&repo).filter_ledger_events(events);
        let text = serde_json::to_string(&kept).unwrap();
        assert!(!text.contains("TOKEN=abc") && !text.contains("key.env"), "{text}");
        assert!(text.contains("fn main() {}") && text.contains("look"), "{text}");
    }
}
