//! A transcript replayed as hook events through `/hook/batch`, the ingress
//! live capture uses, so a past session becomes a real session with its
//! observations, sanitized and bounded by the server, with no LLM.
//!
//! Copied from ai-memory v3.4.7 (fa0ec25),
//! crates/ai-memory-cli/src/commands/backfill.rs: `import_exported_transcript`,
//! `resolve_occurred_at`, `map_event`, `first_line`, `replay_ingest_key`,
//! `hook_item`, `hook_batch_end`, `post_hook_items` and `acknowledged_items`.
//! Changed for Cadex: the batch goes through the engine's router in process
//! (no HTTP client), the scope is the project's root with
//! `project_strategy=repo-root` (as the live hook sends it) instead of a
//! workspace/project pair, no recovery interval, no metadata-only bodies (no
//! capture policy, replay_capture.rs), and `auto_handoff=0`: a session
//! learned after the fact leaves no baton for the next briefing. On an
//! upstream update, compare these functions (core/features/memory/CLAUDE.md).

use std::time::Duration;

use ai_memory_core::{NewWorkstreamEvent, WorkstreamEventKind};
use ai_memory_hooks::payload::BACKFILL_EXTENSION;
use ai_memory_workstream::ExportedTranscript;
use anyhow::{Result, bail};
use axum::Router;
use axum::body::Body;
use axum::http::{Request, header};
use serde::{Deserialize, Serialize};
use tower::ServiceExt;

use crate::replay_capture::{EventCapture, decide};

/// Items per `/hook/batch` request: the server's `MAX_HOOK_BATCH_ITEMS`.
const HOOK_BATCH_ITEMS: usize = 256;
const HOOK_BATCH_BYTES: usize = 8 * 1024 * 1024;

/// Where the replayed events land: the project's root as the cwd, and the
/// account's workspace when the memory is not shared (`None` = `default`).
pub(crate) struct Target {
    pub(crate) cwd: String,
    pub(crate) workspace: Option<String>,
    /// The hook `agent` (`claude-code` for imports; the harness's for a
    /// recovered `cadex-memory run`, run/recover.rs).
    pub(crate) agent: &'static str,
}

#[derive(Clone, Debug, Serialize)]
pub(crate) struct HookItem {
    url: String,
    body: serde_json::Value,
}

/// The hook items of one session (start, content, end) and how many are content.
pub(crate) fn items(target: &Target, sid: &str, transcript: &ExportedTranscript) -> (Vec<HookItem>, usize) {
    let resolved = resolve_occurred_at(&transcript.events);
    let mut items = Vec::with_capacity(transcript.events.len() + 2);
    let boundary = |event: &str, at: &Option<String>| {
        hook_item(target, event, sid, &replay_ingest_key(sid, event, "boundary"), None,
            serde_json::json!({ "session_id": sid, "occurred_at": at }))
    };
    items.push(boundary("session-start", &resolved.earliest));
    let mut content = 0;
    let captures = decide(&transcript.events);
    for ((event, at), capture) in transcript.events.iter().zip(&resolved.per_event).zip(captures) {
        if let Some(mapped) = map_event(sid, event, at.as_deref(), capture) {
            items.push(hook_item(target, &mapped.event, sid, &mapped.ingest_key, mapped.source_event.as_deref(), mapped.body));
            content += 1;
        }
    }
    items.push(boundary("session-end", &resolved.latest));
    (items, content)
}

struct Resolved {
    per_event: Vec<Option<String>>,
    earliest: Option<String>,
    latest: Option<String>,
}

/// Each event's time: its own if valid RFC 3339, else the nearest earlier
/// valid one (the first valid one for a leading gap); the session's bounds
/// are the earliest and latest valid times, not the first and last records.
fn resolve_occurred_at(events: &[NewWorkstreamEvent]) -> Resolved {
    let valid: Vec<Option<jiff::Timestamp>> =
        events.iter().map(|e| e.occurred_at.as_deref().and_then(|s| s.parse().ok())).collect();
    let mut last = None;
    let mut per_event: Vec<Option<jiff::Timestamp>> = valid.iter().map(|ts| { if ts.is_some() { last = *ts; } last }).collect();
    if let Some(first) = valid.iter().copied().flatten().next() {
        for slot in per_event.iter_mut().take_while(|s| s.is_none()) {
            *slot = Some(first);
        }
    }
    let earliest = valid.iter().copied().flatten().min();
    let latest = valid.iter().copied().flatten().max();
    Resolved {
        per_event: per_event.into_iter().map(|t| t.map(|t| t.to_string())).collect(),
        earliest: earliest.map(|t| t.to_string()),
        latest: latest.map(|t| t.to_string()),
    }
}

struct Mapped {
    event: String,
    source_event: Option<String>,
    ingest_key: String,
    body: serde_json::Value,
}

/// A user message is the canonical `user-prompt`; any other message, call or
/// result a `backfill.*` extension observation; boundary records (compaction,
/// checkpoint, annotation) are not content and map to nothing.
fn map_event(sid: &str, event: &NewWorkstreamEvent, at: Option<&str>, capture: EventCapture) -> Option<Mapped> {
    let content = event.content.trim();
    if content.is_empty() || capture == EventCapture::Drop {
        return None;
    }
    let role = event.role.as_deref().unwrap_or("");
    let ingest_key = replay_ingest_key(sid, event.kind.as_str(), &event.event_id);
    match event.kind {
        WorkstreamEventKind::Message if role == "user" || role == "human" => Some(Mapped {
            event: "user-prompt".into(),
            source_event: None,
            ingest_key,
            body: serde_json::json!({ "session_id": sid, "prompt": event.content, "occurred_at": at }),
        }),
        WorkstreamEventKind::Message | WorkstreamEventKind::ToolCall | WorkstreamEventKind::ToolResult => {
            let source_event = match event.kind {
                WorkstreamEventKind::ToolCall => "tool_call".to_string(),
                WorkstreamEventKind::ToolResult => "tool_result".to_string(),
                _ if role.is_empty() => "message".to_string(),
                _ => format!("{role}-message"),
            };
            let body = if capture == EventCapture::Unrecognized {
                let outcome = if event.kind == WorkstreamEventKind::ToolResult { "\noutcome: unknown" } else { "" };
                serde_json::json!({ "session_id": sid, "title": "tool unknown",
                    "message": format!("tool_family: unknown{outcome}"), "occurred_at": at })
            } else {
                serde_json::json!({ "session_id": sid, "title": first_line(content),
                    "message": event.content, "occurred_at": at })
            };
            Some(Mapped { event: format!("backfill.{source_event}"), source_event: Some(source_event), ingest_key, body })
        }
        WorkstreamEventKind::Compaction | WorkstreamEventKind::Checkpoint | WorkstreamEventKind::Annotation => None,
    }
}

fn first_line(content: &str) -> String {
    let capped: String = content.lines().next().unwrap_or("").trim().chars().take(120).collect();
    if capped.is_empty() { "(backfilled event)".to_string() } else { capped }
}

/// The same key for the same event on every import, so a replay of a session
/// already stored is acknowledged as `replayed`, not stored twice. Upstream's
/// hash with an empty recovery interval.
fn replay_ingest_key(sid: &str, kind: &str, event_id: &str) -> String {
    use sha2::{Digest as _, Sha256};
    let mut hasher = Sha256::new();
    for value in ["", sid, kind, event_id] {
        hasher.update(value.len().to_be_bytes());
        hasher.update(value.as_bytes());
    }
    let digest = format!("{:x}", hasher.finalize());
    format!("recovery_{}", &digest[..55])
}

fn hook_item(target: &Target, event: &str, sid: &str, ingest_key: &str, source_event: Option<&str>, body: serde_json::Value) -> HookItem {
    let mut pairs: Vec<(&str, &str)> = vec![("event", event), ("agent", target.agent), ("cwd", &target.cwd)];
    if let Some(ws) = &target.workspace {
        pairs.push(("workspace", ws));
    }
    pairs.extend([("project_strategy", "repo-root"), ("session_id", sid), ("ingest_key", ingest_key), ("auto_handoff", "0")]);
    if let Some(source) = source_event {
        pairs.extend([("extension", BACKFILL_EXTENSION), ("source_event", source)]);
    }
    let query = serde_urlencoded::to_string(&pairs).unwrap_or_default();
    HookItem { url: format!("http://localhost/hook?{query}"), body }
}

pub(crate) fn hook_batch_end(items: &[HookItem], offset: usize) -> Result<usize> {
    let (mut end, mut bytes) = (offset, 2_usize);
    while end < items.len() && end - offset < HOOK_BATCH_ITEMS {
        let item_bytes = serde_json::to_vec(&items[end])?.len().saturating_add(1);
        if item_bytes > HOOK_BATCH_BYTES {
            bail!("one hook item exceeds the batch byte limit");
        }
        if end > offset && bytes.saturating_add(item_bytes) > HOOK_BATCH_BYTES {
            break;
        }
        bytes = bytes.saturating_add(item_bytes);
        end += 1;
    }
    Ok(end)
}

#[derive(Debug, Deserialize)]
pub(crate) struct HookBatchAck {
    accepted: usize,
    results: Vec<HookBatchResult>,
    #[serde(default)]
    accepted_indices: Option<Vec<usize>>,
    #[serde(default)]
    failed_index: Option<usize>,
}

#[derive(Debug, Deserialize)]
struct HookBatchResult {
    index: usize,
    outcome: String,
}

/// The items the server durably took; an error for any other outcome.
pub(crate) fn acknowledged(ack: &HookBatchAck, items: &[HookItem]) -> Result<Vec<usize>> {
    let indices = ack.accepted_indices.clone().unwrap_or_else(|| (0..ack.accepted).collect());
    if ack.accepted > items.len()
        || indices.iter().any(|i| *i >= items.len())
        || indices.windows(2).any(|p| p[0] >= p[1])
        || ack.results.len() != indices.len()
    {
        bail!("invalid hook acknowledgement");
    }
    for (result, index) in ack.results.iter().zip(&indices) {
        if result.index != *index {
            bail!("hook acknowledgement result indices disagree");
        }
        let is_end = items[*index].url.contains("event=session-end&");
        match result.outcome.as_str() {
            "stored" | "replayed" => {}
            "ignored_end" if is_end => {}
            outcome => bail!("hook item {index} was not stored ({outcome})"),
        }
    }
    if let Some(index) = ack.failed_index {
        bail!("hook processing failed at item {index}");
    }
    Ok(indices)
}

async fn post_batch(router: &Router, batch: &[HookItem]) -> Result<HookBatchAck> {
    let request = Request::post("/hook/batch")
        .header(header::HOST, "localhost")
        .header(header::CONTENT_TYPE, "application/json")
        .body(Body::from(serde_json::to_vec(batch)?))?;
    let response = match router.clone().oneshot(request).await {
        Ok(r) => r,
        Err(never) => match never {},
    };
    let status = response.status();
    let bytes = axum::body::to_bytes(response.into_body(), 1024 * 1024).await?;
    if !status.is_success() && status.as_u16() != 429 {
        bail!("/hook/batch answered {status}");
    }
    Ok(serde_json::from_slice(&bytes)?)
}

/// Post every item in server-sized batches. A batch the server is too busy
/// for (none acknowledged) is retried with a growing pause, five times.
pub(crate) async fn post(router: &Router, items: &[HookItem]) -> Result<()> {
    let mut offset = 0;
    while offset < items.len() {
        let end = hook_batch_end(items, offset)?;
        let chunk = &items[offset..end];
        let mut stalled = 0u32;
        loop {
            let accepted = acknowledged(&post_batch(router, chunk).await?, chunk)?;
            if accepted.len() == chunk.len() {
                break;
            }
            if !accepted.is_empty() {
                bail!("the server took {} of {} items", accepted.len(), chunk.len());
            }
            stalled += 1;
            if stalled >= 5 {
                bail!("the server took none of a batch after {stalled} attempts");
            }
            tokio::time::sleep(Duration::from_millis(200 * u64::from(stalled))).await;
        }
        offset = end;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn times_fill_forward_and_the_bounds_are_the_extremes() {
        let at = |t: Option<&str>| NewWorkstreamEvent {
            event_id: "e".into(), agent: ai_memory_core::AgentKind::ClaudeCode, native_session_id: "s".into(),
            source_record_id: None, kind: WorkstreamEventKind::Message, role: Some("user".into()),
            content: "x".into(), occurred_at: t.map(Into::into), metadata: serde_json::Value::Null,
        };
        let r = resolve_occurred_at(&[at(None), at(Some("2026-09-01T10:00:00Z")), at(Some("bad")), at(Some("2026-08-01T10:00:00Z"))]);
        assert_eq!(r.per_event, vec![
            Some("2026-09-01T10:00:00Z".into()), Some("2026-09-01T10:00:00Z".into()),
            Some("2026-09-01T10:00:00Z".into()), Some("2026-08-01T10:00:00Z".into()),
        ]);
        assert_eq!((r.earliest.as_deref(), r.latest.as_deref()), (Some("2026-08-01T10:00:00Z"), Some("2026-09-01T10:00:00Z")));
        assert_eq!(replay_ingest_key("s", "message", "e"), replay_ingest_key("s", "message", "e"));
        assert_eq!(replay_ingest_key("s", "message", "e").len(), "recovery_".len() + 55);
    }

    #[test]
    fn an_item_names_the_project_root_and_never_leaves_a_baton() {
        let target = Target { cwd: "/r/a b".into(), workspace: Some("-Users-a--claude".into()), agent: "claude-code" };
        let item = hook_item(&target, "user-prompt", "s1", "k", None, serde_json::json!({}));
        assert_eq!(item.url, "http://localhost/hook?event=user-prompt&agent=claude-code&cwd=%2Fr%2Fa+b\
            &workspace=-Users-a--claude&project_strategy=repo-root&session_id=s1&ingest_key=k&auto_handoff=0");
    }
}
