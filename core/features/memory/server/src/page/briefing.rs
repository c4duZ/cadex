//! `GET /cadex/memory/briefing?cwd=<dir>[&workspace=]`: what the next
//! SessionStart in that folder would get as context, as plain text, without
//! claiming the pending handoff (the spec's "What the Agent Will See", plan
//! 22 phase H, 2026-11-16). The backfill marker line stays in; the client
//! drops it as the hook does (`briefingText`, hook_client.zig).
//!
//! The hook's request is upstream's `/handoff` with `briefing=1`
//! (events.zig `handoffTarget`), through the inner router so the marker's
//! pairs apply (marker_query.rs). A real start claims the handoff; asked
//! with upstream's own `claim=0` (#2148, the external-capture run's switch)
//! the route renders everything else the same and puts a one-line notice
//! where the handoff's text goes. So:
//! 1. ask with `claim=0`; no notice means no pending handoff, and then the
//!    answer is the same as a claiming start's;
//! 2. with a notice, ask again with `recovery=0` as well: a delivered
//!    handoff drops the unfinished-session packet upstream (only when it was
//!    claimed), and swap the notice for the handoff's text (handoff_text.rs,
//!    upstream's renderer copied);
//! 3. upstream admits the brief, last, only while the whole stays under
//!    Claude Code's 9,800 characters: when the swap goes over, the answer is
//!    the one asked with `briefing=0`.
//!
//! Upstream's side effects of the ask are a start's: the active-project
//! pointer and the marker's `[profile]` flags, and the project row for a
//! folder the store did not know.

use std::str::FromStr;
use std::sync::Arc;

use ai_memory_core::HandoffId;
use axum::Router;
use axum::body::Body;
use axum::extract::State;
use axum::http::{Request, StatusCode, header};
use axum::response::{IntoResponse, Response};
use tower::ServiceExt;

use super::handoff_text::{CLAUDE_ADDITIONAL_CONTEXT_CHARS, CLAUDE_HANDOFF_CHARS, render};
use super::{Ctx, Params, cwd_of, error};

/// The first words of upstream's `render_handoff_notice`.
const NOTICE: &str = "📬 ai-memory: a pending handoff `";

type Pairs = Vec<(String, String)>;

fn set(pairs: &mut Pairs, key: &str, value: &str) {
    pairs.retain(|(k, _)| k != key);
    pairs.push((key.to_owned(), value.to_owned()));
}

/// The hook's `/handoff` query (events.zig `handoffTarget`), with no session.
fn base(cwd: &str, workspace: Option<&str>) -> Pairs {
    let mut pairs: Pairs = vec![("agent".into(), "claude-code".into()), ("cwd".into(), cwd.into())];
    if let Some(ws) = workspace {
        pairs.push(("workspace".into(), ws.into()));
    }
    pairs.push(("project_strategy".into(), "repo-root".into()));
    pairs.push(("briefing".into(), "1".into()));
    set(&mut pairs, "claim", "0");
    pairs
}

/// One `/handoff` through the inner router: the text, or the error to send.
async fn ask(inner: &Router, pairs: &Pairs) -> Result<String, Response> {
    let query = serde_urlencoded::to_string(pairs).map_err(|e| error(StatusCode::BAD_REQUEST, &e.to_string()))?;
    let request = Request::get(format!("/handoff?{query}"))
        .header(header::HOST, "localhost")
        .body(Body::empty())
        .map_err(|e| error(StatusCode::INTERNAL_SERVER_ERROR, &e.to_string()))?;
    let response = inner.clone().oneshot(request).await.unwrap_or_else(|never| match never {});
    let status = response.status();
    let bytes = axum::body::to_bytes(response.into_body(), 4 << 20)
        .await
        .map_err(|e| error(StatusCode::INTERNAL_SERVER_ERROR, &e.to_string()))?;
    let text = String::from_utf8_lossy(&bytes).into_owned();
    if !status.is_success() {
        return Err(error(status, text.trim()));
    }
    Ok(text)
}

/// Where the notice is in `text`, and the handoff it names.
fn notice_in(text: &str) -> Option<(std::ops::Range<usize>, HandoffId)> {
    let start = text.find(NOTICE)?;
    let rest = &text[start + NOTICE.len()..];
    let id_text = &rest[..rest.find('`')?];
    let id = HandoffId::from_str(id_text).ok()?;
    let tail = format!("with handoff_id `{id_text}`.");
    let end = start + text[start..].find(&tail)? + tail.len();
    Some((start..end, id))
}

/// `text` with its notice replaced by the handoff's text.
fn swap(text: &str, rendered: &str) -> Option<String> {
    let (range, _) = notice_in(text)?;
    Some(format!("{}{rendered}{}", &text[..range.start], &text[range.end..]))
}

pub(crate) async fn preview(ctx: &Ctx, cwd: &str, workspace: Option<&str>) -> Result<String, Response> {
    let inner = ctx.inner()?;
    let mut pairs = base(cwd, workspace);
    let first = ask(&inner, &pairs).await?;
    let Some((_, id)) = notice_in(&first) else { return Ok(first) };
    let Ok(Some(handoff)) = ctx.reader.handoff_by_id(id).await else { return Ok(first) };
    let rendered = render(&handoff, Some(CLAUDE_HANDOFF_CHARS));
    set(&mut pairs, "recovery", "0");
    let with_brief = ask(&inner, &pairs).await?;
    let Some(full) = swap(&with_brief, &rendered) else { return Ok(first) };
    if full.chars().count() <= CLAUDE_ADDITIONAL_CONTEXT_CHARS {
        return Ok(full);
    }
    set(&mut pairs, "briefing", "0");
    let without_brief = ask(&inner, &pairs).await?;
    Ok(swap(&without_brief, &rendered).unwrap_or(full))
}

pub(crate) async fn handle(State(ctx): State<Arc<Ctx>>, axum::extract::Query(q): Params) -> Response {
    let cwd = match cwd_of(&q) {
        Ok(cwd) => cwd,
        Err(response) => return response,
    };
    let workspace = q.get("workspace").map(String::as_str).filter(|w| !w.is_empty());
    match preview(&ctx, &cwd, workspace).await {
        Ok(text) => ([(header::CONTENT_TYPE, "text/plain; charset=utf-8")], text).into_response(),
        Err(response) => response,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_notice_is_found_by_its_id_and_swapped_whole() {
        let id = "0198c3a0-1b2c-7d3e-8f40-123456789abc";
        let text = format!(
            "profile\n📬 ai-memory: a pending handoff `{id}` from `claude-code`, left 2 minutes ago. \
             To pick it up, call `memory_handoff_accept` with handoff_id `{id}`.\nbrief"
        );
        let (range, found) = notice_in(&text).unwrap();
        assert_eq!(found.to_string(), id);
        assert!(text[range].ends_with(&format!("`{id}`.")));
        assert_eq!(swap(&text, "HANDOFF\n").unwrap(), "profile\nHANDOFF\n\nbrief");
        assert!(notice_in("no notice here").is_none());
    }

    #[test]
    fn the_query_is_the_hooks_without_a_claim() {
        let pairs = base("/r", Some("acct"));
        let query = serde_urlencoded::to_string(&pairs).unwrap();
        assert_eq!(query, "agent=claude-code&cwd=%2Fr&workspace=acct&project_strategy=repo-root&briefing=1&claim=0");
    }
}
