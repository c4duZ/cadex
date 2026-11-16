//! Cadex's handoff at SessionEnd (plan 22, phase C, "O handoff do crate do
//! Cadex"). Upstream ends the session, writes its page and, when it decides
//! the session is worth a baton, an automatic handoff from the first and last
//! prompt (router.rs `build_auto_handoff`). Here that handoff's text is
//! replaced by the session's facts (session_facts.rs); the sessions upstream
//! leaves without one stay without one.
//!
//! The hook router answers 202 and ends the session in a task of its own, so
//! the replacement waits for upstream's word that a session end is done: the
//! `profile_notify` of its HookState, rung after every SessionEnd (engine.rs;
//! the profile worker it was made for does not run here). The middleware
//! notes each SessionEnd it lets through; at each ring, and when the note
//! arrives, the noted sessions are looked at (for a minute at most).
//!
//! The store has no update for a handoff's text, so the automatic one is
//! cancelled (`cancel_handoff`, which only changes an open row: a session
//! that already claimed it keeps it, and nothing is written) and an
//! equivalent one is inserted (`insert_handoff`: automatic, from the same
//! session, agent, folder and owner), claimed once by the next SessionStart
//! like the first. Between the two writes a starting session finds no baton.

use std::collections::{HashMap, HashSet};
use std::sync::Arc;
use std::time::{Duration, Instant};

use ai_memory_core::{HandoffState, NewHandoff, OwnerFilter, SessionId};
use ai_memory_store::{ReaderPool, WriterHandle};
use anyhow::Result;
use axum::extract::{Query, Request, State};
use axum::middleware::Next;
use axum::response::Response;
use tokio::sync::{Notify, mpsc};
use tokio_util::sync::CancellationToken;

use crate::restart::InFlight;
use crate::session_facts::{Facts, render};

/// How long a noted SessionEnd is looked for.
const PENDING_FOR: Duration = Duration::from_secs(60);
/// Upstream's report of a failed call, which the new text keeps.
const FAILED_PREFIX: &str = "Last failed tool call: ";

pub(crate) type Sender = mpsc::UnboundedSender<String>;

/// Middleware on the inner router (spool replays count): a SessionEnd the
/// router took is noted, after the answer is made.
pub(crate) async fn watch(State(tx): State<Sender>, req: Request, next: Next) -> Response {
    let ended = (req.uri().path() == "/hook")
        .then(|| Query::<HashMap<String, String>>::try_from_uri(req.uri()).ok())
        .flatten()
        .filter(|q| matches!(q.get("event").map(String::as_str), Some("session-end" | "session_end")))
        .and_then(|Query(q)| q.get("session_id").filter(|s| !s.is_empty()).cloned());
    let response = next.run(req).await;
    if let Some(session) = ended
        && response.status().is_success()
    {
        let _ = tx.send(session);
    }
    response
}

/// What the replacement needs from the engine.
pub(crate) struct Context {
    pub(crate) reader: ReaderPool,
    pub(crate) writer: WriterHandle,
    /// Rung by upstream after each SessionEnd (engine.rs).
    pub(crate) ended: Arc<Notify>,
    pub(crate) in_flight: Arc<InFlight>,
    pub(crate) stop: CancellationToken,
}

/// Look at noted sessions until the engine stops.
pub(crate) async fn run(ctx: Context, mut rx: mpsc::UnboundedReceiver<String>) {
    let mut pending: HashMap<String, Instant> = HashMap::new();
    loop {
        let fresh: Option<String> = tokio::select! {
            s = rx.recv() => match s { Some(s) => Some(s), None => return },
            () = ctx.ended.notified() => None,
            () = ctx.stop.cancelled() => return,
        };
        if let Some(s) = fresh {
            pending.insert(s, Instant::now());
        }
        pending.retain(|_, at| at.elapsed() < PENDING_FOR);
        let _hold = ctx.in_flight.hold();
        let mut done = HashSet::new();
        for session in pending.keys() {
            match replace(&ctx, session).await {
                Ok(true) => {
                    done.insert(session.clone());
                }
                Ok(false) => {}
                Err(error) => tracing::warn!(%session, error = %format!("{error:#}"), "handoff not rewritten"),
            }
        }
        pending.retain(|s, _| !done.contains(s));
    }
}

/// Rewrite the session's open automatic handoff. `Ok(true)` when it is
/// settled (rewritten, or already ours); `Ok(false)` when upstream has not
/// ended it yet or left no handoff (looked at again at the next ring).
pub(crate) async fn replace(ctx: &Context, session: &str) -> Result<bool> {
    let id = SessionId::from_native(session);
    let Some((ws, proj, _)) = ctx.reader.find_session_scope(id).await? else { return Ok(false) };
    let open = ctx.reader.list_handoffs(ws, proj, Some(HandoffState::Open), OwnerFilter::Any, 50).await?;
    let Some(auto) = open.into_iter().find(|h| h.origin.from_session_id == Some(id) && !h.origin.is_manual()) else {
        return Ok(false);
    };
    let facts = Facts::load(&ctx.reader, ws, proj, id).await?;
    let failed = auto.content.next_steps.iter().find_map(|s| s.strip_prefix(FAILED_PREFIX));
    let (summary, files) = render(&facts, failed);
    let ours = auto.content.summary == summary
        && auto.content.files_touched == files
        && auto.content.open_questions.is_empty()
        && auto.content.next_steps.is_empty();
    if ours {
        return Ok(true);
    }
    if !ctx.writer.cancel_handoff(auto.scope.id, ws, proj, OwnerFilter::Any).await? {
        // Claimed meanwhile: the session that took it keeps upstream's text.
        return Ok(true);
    }
    let handoff = NewHandoff {
        workspace_id: ws,
        project_id: proj,
        from_session_id: Some(id),
        from_agent: auto.origin.from_agent,
        to_agent: auto.origin.to_agent,
        cwd: auto.origin.cwd.map(Into::into),
        summary,
        open_questions: Vec::new(),
        next_steps: Vec::new(),
        files_touched: files,
        owner_user: auto.origin.owner_user,
    };
    let new = ctx.writer.insert_handoff(handoff).await?;
    tracing::info!(%session, handoff = %new, prompts = facts.prompts.len(), edited = facts.edited.len(), "handoff rewritten from the session's facts");
    Ok(true)
}
