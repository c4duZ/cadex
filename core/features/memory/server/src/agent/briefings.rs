//! The briefing each session started with (plan 35 phase D, 2026-11-19):
//! the answer to the SessionStart's `GET /handoff` (events.zig
//! `handoffTarget`) kept in `<data-dir>/agent/briefings/<session id>.md`
//! (audit.rs: 0600, the same retention). The hook client only trims it and
//! drops upstream's backfill marker before Claude Code gets it
//! (hook_client.zig `briefingText`), so this is what the session read.
//!
//! Only a real start: a `session_id` and no `claim=0` (upstream's switch,
//! `query_flag_falsy`; the Memory page's preview asks with it and no
//! session, page/briefing.rs). A resumed session asks again and its file
//! holds the newer briefing.
//!
//! The body is read whole (a briefing is cut at ~10 KB) and the file is
//! written on a blocking thread after the answer is made: the SessionStart
//! has 1 s for everything and does not wait for the disk.

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Arc;

use axum::body::Body;
use axum::extract::{Query, Request, State};
use axum::http::StatusCode;
use axum::middleware::Next;
use axum::response::{IntoResponse, Response};

use super::audit;

/// Far above upstream's briefing cut; past it the body is not ours to keep.
const MAX_BODY: usize = 4 << 20;

/// The session of a claiming `/handoff`, if this is one.
fn starting_session(req: &Request) -> Option<String> {
    if req.uri().path() != "/handoff" {
        return None;
    }
    let Query(query) = Query::<HashMap<String, String>>::try_from_uri(req.uri()).ok()?;
    let falsy = |v: &str| matches!(v.trim().to_ascii_lowercase().as_str(), "0" | "false" | "no" | "off");
    if query.get("claim").is_some_and(|v| falsy(v)) {
        return None;
    }
    query.get("session_id").filter(|s| audit::session_file_name(s).is_some()).cloned()
}

/// Middleware on the inner router: keep a real start's briefing.
pub(crate) async fn keep(State(data_dir): State<Arc<PathBuf>>, req: Request, next: Next) -> Response {
    let session = starting_session(&req);
    let response = next.run(req).await;
    let Some(session) = session else { return response };
    if !response.status().is_success() {
        return response;
    }
    let (parts, body) = response.into_parts();
    let bytes = match axum::body::to_bytes(body, MAX_BODY).await {
        Ok(bytes) => bytes,
        Err(error) => return (StatusCode::INTERNAL_SERVER_ERROR, error.to_string()).into_response(),
    };
    let text = String::from_utf8_lossy(&bytes).into_owned();
    tokio::task::spawn_blocking(move || audit::keep_briefing(&data_dir, &session, &text));
    Response::from_parts(parts, Body::from(bytes))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn session_of(uri: &str) -> Option<String> {
        starting_session(&Request::get(uri).body(Body::empty()).unwrap())
    }

    #[test]
    fn only_a_claiming_handoff_with_a_session_is_kept() {
        assert_eq!(session_of("/handoff?agent=claude-code&cwd=%2Fr&session_id=s-1").as_deref(), Some("s-1"));
        assert_eq!(session_of("/handoff?cwd=%2Fr&session_id=s-1&claim=1").as_deref(), Some("s-1"));
        assert_eq!(session_of("/handoff?cwd=%2Fr&session_id=s-1&claim=0"), None, "the Memory page's preview");
        assert_eq!(session_of("/handoff?cwd=%2Fr&session_id=s-1&claim=off"), None);
        assert_eq!(session_of("/handoff?cwd=%2Fr"), None);
        assert_eq!(session_of("/handoff?session_id=..%2Fx"), None);
        assert_eq!(session_of("/brief?session_id=s-1"), None);
    }
}
