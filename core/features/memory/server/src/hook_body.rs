//! A live hook event's body, amended once before upstream's route reads it
//! (on the inner router, so spool replays count):
//! - `occurred_at`, the time the event arrived, strictly increasing. The
//!   route answers 202 and stores the event in a task of its own, stamping
//!   it with the time that task ran unless the client sent `occurred_at`
//!   (only a transcript replay does, import.rs). Events sent one after the
//!   other were stored out of order: with the suite running, a session's
//!   two prompts came back swapped and its edits started at the fourth file
//!   (tests/session_end.rs, 3 failures in 12 runs, 2026-11-16), which is
//!   the order upstream's handoff and session_facts.rs read (`created_at`,
//!   then rowid). Upstream bounds the value (no more than 5 min ahead).
//! - on a PostToolUse, the file the call named (file_claim.rs).
//! - on a tool event, the repository's `[capture] ignore_paths`
//!   (capture.rs): dropped (202, nothing stored), metadata only, or kept.
//!
//! Before that, on `/hook`, `/handoff` and `/brief`, the query gets the
//! pairs of the repository's `.ai-memory.toml` (marker_query.rs).
//!
//! An event replayed from the queue gets the time of its replay: still in
//! the order it was queued, since the queue is replayed one at a time.

use std::collections::HashMap;
use std::sync::atomic::{AtomicI64, Ordering};

use axum::body::{Body, Bytes};
use axum::extract::{Query, Request};
use axum::http::{StatusCode, header};
use axum::middleware::Next;
use axum::response::{IntoResponse, Response};

use crate::capture::{self, Capture};
use crate::{file_claim, marker_query};

/// Same cap as engine.rs's body limit.
const MAX_BODY: usize = 10 * 1024 * 1024;
/// The field upstream reads the event's own time from (payload.rs).
const OCCURRED_AT: &str = "occurred_at";

/// The last arrival stamped, in microseconds.
static LAST_ARRIVAL: AtomicI64 = AtomicI64::new(0);

/// Now, or one microsecond past the last stamp when the clock has not moved
/// (or moved back): two events never share a time.
fn arrival() -> Option<String> {
    let now = jiff::Timestamp::now().as_microsecond();
    let previous = LAST_ARRIVAL.fetch_update(Ordering::SeqCst, Ordering::SeqCst, |last| Some(now.max(last + 1))).ok()?;
    jiff::Timestamp::from_microsecond(now.max(previous + 1)).ok().map(|t| t.to_string())
}

/// What the body became.
enum Amended {
    Unchanged,
    Changed(Vec<u8>),
    Dropped,
}

/// The body amended; `None` to send it unchanged (tests).
#[cfg(test)]
fn amend_body(body: &[u8], query: &HashMap<String, String>) -> Option<Vec<u8>> {
    match amend_event(body, query) {
        Amended::Changed(bytes) => Some(bytes),
        _ => None,
    }
}

fn amend_event(body: &[u8], query: &HashMap<String, String>) -> Amended {
    let Ok(mut payload) = serde_json::from_slice::<serde_json::Value>(body) else { return Amended::Unchanged };
    let Some(object) = payload.as_object_mut() else { return Amended::Unchanged };
    if !object.contains_key(OCCURRED_AT)
        && let Some(at) = arrival()
    {
        object.insert(OCCURRED_AT.into(), at.into());
    }
    let event = query.get("event").map_or("", String::as_str);
    let agent = query.get("agent").map_or("claude-code", String::as_str);
    let cwd = query.get("cwd").map(String::as_str);
    if capture::apply(&mut payload, event, agent, cwd) == Capture::Drop {
        return Amended::Dropped;
    }
    match amend_claims(payload, query) {
        Some(bytes) => Amended::Changed(bytes),
        None => Amended::Unchanged,
    }
}

fn amend_claims(mut payload: serde_json::Value, query: &HashMap<String, String>) -> Option<Vec<u8>> {
    if matches!(query.get("event").map(String::as_str), Some("post-tool-use" | "post_tool_use")) {
        file_claim::insert(&mut payload, query.get("cwd").map(String::as_str));
    }
    serde_json::to_vec(&payload).ok()
}

/// Middleware on the inner router.
pub(crate) async fn amend(mut req: Request, next: Next) -> Response {
    if let Some(uri) = marker_uri(req.uri()) {
        *req.uri_mut() = uri;
    }
    let query = (req.uri().path() == "/hook")
        .then(|| Query::<HashMap<String, String>>::try_from_uri(req.uri()).ok())
        .flatten();
    let Some(Query(query)) = query else { return next.run(req).await };
    let (mut parts, body) = req.into_parts();
    let Ok(bytes) = axum::body::to_bytes(body, MAX_BODY).await else {
        return StatusCode::PAYLOAD_TOO_LARGE.into_response();
    };
    let bytes = match amend_event(&bytes, &query) {
        Amended::Changed(changed) => {
            parts.headers.remove(header::CONTENT_LENGTH);
            Bytes::from(changed)
        }
        Amended::Unchanged => bytes,
        Amended::Dropped => return (StatusCode::ACCEPTED, "dropped by capture.ignore_paths").into_response(),
    };
    next.run(Request::from_parts(parts, Body::from(bytes))).await
}

/// The URI with the marker's query pairs, when it has any.
fn marker_uri(uri: &axum::http::Uri) -> Option<axum::http::Uri> {
    let query = marker_query::amend(uri.path(), uri.query()?)?;
    format!("{}?{query}", uri.path()).parse().ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn each_event_gets_a_later_arrival_than_the_one_before() {
        let query: HashMap<String, String> = [("event".to_string(), "user-prompt-submit".to_string())].into();
        let stamps: Vec<jiff::Timestamp> = (0..1000)
            .map(|_| {
                let out: serde_json::Value = serde_json::from_slice(&amend_body(br#"{"prompt":"x"}"#, &query).unwrap()).unwrap();
                out[OCCURRED_AT].as_str().unwrap().parse().unwrap()
            })
            .collect();
        assert!(stamps.windows(2).all(|w| w[0] < w[1]), "strictly increasing");
        let given = amend_body(br#"{"occurred_at":"2026-09-01T10:00:00Z"}"#, &query).unwrap();
        assert_eq!(serde_json::from_slice::<serde_json::Value>(&given).unwrap()[OCCURRED_AT], "2026-09-01T10:00:00Z", "a replay's own time stays");
        assert!(amend_body(b"not json", &query).is_none());
    }
}
