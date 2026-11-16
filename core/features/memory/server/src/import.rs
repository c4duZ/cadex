//! Past and outside sessions learned from their transcripts (plan 22, phase C):
//! - a project's history, once, when a SessionStart finds its memory with no
//!   other session (upstream's rule: a project with captured sessions is never
//!   back-filled, backfill.rs `project_is_empty`) — import_jobs.rs `backfill`;
//! - at every engine start (not the restart that gives memory back), the
//!   sessions of known projects that ran outside Cadex — `outside`.
//!
//! One task runs the jobs one after another, in the background: a job waits
//! `--import-delay-ms` first, past the 1 s the hook gives the SessionStart and
//! its briefing (core/features/memory/hook_client.zig), and holds the restart
//! (restart.rs) while it posts. Each session goes through upstream's own
//! transcript reader and `/hook/batch` (replay.rs), as upstream's backfill does.

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::{Duration, Instant};

use ai_memory_core::SessionId;
use ai_memory_store::ReaderPool;
use ai_memory_workstream::{ExportedTranscript, ManagedHarness, export_transcript};
use anyhow::Result;
use axum::Router;
use axum::extract::{Query, Request, State};
use axum::middleware::Next;
use axum::response::Response;
use tokio::sync::mpsc;
use tokio_util::sync::CancellationToken;

use crate::import_jobs;
use crate::replay::{self, Target};
use crate::restart::InFlight;
use crate::transcripts::Transcript;

/// Upstream's caps for a project's history (backfill.rs): the newest 200
/// sessions per harness, and no session started past 50,000 events.
pub(crate) const BACKFILL_SESSIONS: usize = 200;
pub(crate) const BACKFILL_EVENTS: usize = 50_000;

/// A SessionStart the importer should look at.
#[derive(Debug)]
pub(crate) struct SessionStarted {
    pub(crate) session_id: String,
    pub(crate) cwd: Option<String>,
    pub(crate) at: Instant,
}

pub(crate) type Sender = mpsc::UnboundedSender<SessionStarted>;
pub(crate) type Receiver = mpsc::UnboundedReceiver<SessionStarted>;

pub(crate) fn channel() -> (Sender, Receiver) {
    mpsc::unbounded_channel()
}

/// Middleware on the inner router (spool replays count): a SessionStart the
/// engine took is handed to the importer, after the answer is made.
pub(crate) async fn watch(State(tx): State<Sender>, req: Request, next: Next) -> Response {
    let started = (req.uri().path() == "/hook")
        .then(|| Query::<HashMap<String, String>>::try_from_uri(req.uri()).ok())
        .flatten()
        .filter(|q| matches!(q.get("event").map(String::as_str), Some("session-start" | "session_start")));
    let response = next.run(req).await;
    if let Some(Query(q)) = started
        && response.status().is_success()
        && let Some(session_id) = q.get("session_id").filter(|s| !s.is_empty())
    {
        let _ = tx.send(SessionStarted { session_id: session_id.clone(), cwd: q.get("cwd").cloned(), at: Instant::now() });
    }
    response
}

/// What a job needs from the engine.
pub(crate) struct Context {
    pub(crate) router: Router,
    pub(crate) reader: ReaderPool,
    pub(crate) data_dir: PathBuf,
    pub(crate) home: PathBuf,
    /// `--claude-dirs`, in place of the app's account folders.
    pub(crate) claude_dirs: Option<Vec<PathBuf>>,
    pub(crate) delay: Duration,
    pub(crate) in_flight: Arc<InFlight>,
    /// Shared with maintenance.rs: one background writer at a time.
    pub(crate) lane: crate::maintenance::Lane,
    pub(crate) stop: CancellationToken,
}

impl Context {
    pub(crate) fn accounts(&self) -> Vec<PathBuf> {
        crate::accounts::find(&self.home, self.claude_dirs.as_deref())
    }

    /// Whether the store already holds this session (in any project).
    pub(crate) async fn has_session(&self, id: &str) -> bool {
        matches!(self.reader.find_session_scope(SessionId::from_native(id)).await, Ok(Some(_)))
    }
}

/// How much one job may still import.
pub(crate) struct Budget {
    pub(crate) sessions: usize,
    pub(crate) events: usize,
}

/// What one job did, for the log.
#[derive(Debug, Default)]
pub(crate) struct Report {
    pub(crate) imported: usize,
    pub(crate) events: usize,
    pub(crate) present: usize,
    pub(crate) skipped: usize,
    pub(crate) failed: usize,
}

impl Report {
    pub(crate) fn log(&self, what: &str, started: Instant) {
        tracing::info!(
            imported = self.imported, events = self.events, already_present = self.present,
            skipped_over_cap = self.skipped, failed = self.failed,
            ms = started.elapsed().as_millis() as u64, "{what}"
        );
    }
}

/// Run the jobs until the engine stops: first the outside sessions (unless
/// this image is a restart), then each SessionStart as it comes.
pub(crate) async fn run(ctx: Context, mut rx: Receiver, outside_at_start: bool) {
    if outside_at_start {
        // Taken before the wait, so the start's maintenance, which takes it
        // after the same wait, runs after this import (maintenance.rs).
        let _lane = ctx.lane.lock().await;
        tokio::select! {
            () = tokio::time::sleep(ctx.delay) => {}
            () = ctx.stop.cancelled() => return,
        }
        let _hold = ctx.in_flight.hold();
        import_jobs::outside(&ctx).await;
    }
    loop {
        let job = tokio::select! {
            job = rx.recv() => match job { Some(job) => job, None => return },
            () = ctx.stop.cancelled() => return,
        };
        let wait = (job.at + ctx.delay).saturating_duration_since(Instant::now());
        tokio::select! {
            () = tokio::time::sleep(wait) => {}
            () = ctx.stop.cancelled() => return,
        }
        let _lane = ctx.lane.lock().await;
        let _hold = ctx.in_flight.hold();
        import_jobs::backfill(&ctx, &job).await;
    }
}

/// One session to import and where its events go.
pub(crate) struct Planned<'a> {
    pub(crate) transcript: &'a Transcript,
    pub(crate) target: &'a Target,
}

/// Import `sessions` (newest first) within `budget`. A session the store
/// has is passed over; the newest ones are chosen until the budget is spent
/// (counting each transcript's events, as upstream's cap does), and the
/// rest are skipped. The chosen ones are then posted oldest first, so the
/// pages are written in the order the sessions ran: imported newest first,
/// the briefing's "recently updated pages" listed the oldest session on
/// top (end-to-end run, 2026-11-16). Returns, per session, whether it was
/// handled (imported, present or unreadable) rather than skipped.
pub(crate) async fn import_all(ctx: &Context, sessions: &[Planned<'_>], budget: &mut Budget, report: &mut Report) -> Vec<bool> {
    let mut handled = vec![true; sessions.len()];
    let mut chosen = Vec::new();
    for (i, s) in sessions.iter().enumerate() {
        if ctx.stop.is_cancelled() {
            handled[i..].iter_mut().for_each(|h| *h = false);
            break;
        }
        if ctx.has_session(&s.transcript.id).await {
            report.present += 1;
        } else if budget.sessions == 0 || budget.events == 0 {
            report.skipped += 1;
            handled[i] = false;
        } else {
            match export(ctx, s.transcript).await {
                Ok(transcript) => {
                    let (_, events) = replay::items(s.target, &s.transcript.id, &transcript);
                    budget.sessions -= 1;
                    budget.events = budget.events.saturating_sub(events);
                    chosen.push(i);
                }
                Err(error) => failed(report, s.transcript, &error),
            }
        }
    }
    for i in chosen.into_iter().rev() {
        if ctx.stop.is_cancelled() {
            handled[i] = false;
            continue;
        }
        match import_one(ctx, &sessions[i]).await {
            Ok(events) => {
                report.imported += 1;
                report.events += events;
            }
            Err(error) => failed(report, sessions[i].transcript, &error),
        }
    }
    handled
}

/// A transcript that cannot be read or stored now (its cwd is gone, it is
/// malformed) will not be later either: counted and logged, not retried.
fn failed(report: &mut Report, t: &Transcript, error: &anyhow::Error) {
    tracing::warn!(session = %t.id, account = %t.account.display(), error = %format!("{error:#}"), "session not imported");
    report.failed += 1;
}

/// Upstream's reader; it checks the recorded cwd against the one given, so
/// the session's folder must still exist.
async fn export(ctx: &Context, t: &Transcript) -> Result<ExportedTranscript> {
    export_transcript(ManagedHarness::Claude, &ctx.home, &t.cwd, Some(&t.store()), &t.id, None).await
}

/// One session read again (it may have grown since it was chosen) and
/// replayed through `/hook/batch`.
async fn import_one(ctx: &Context, s: &Planned<'_>) -> Result<usize> {
    let transcript = export(ctx, s.transcript).await?;
    let (items, content) = replay::items(s.target, &s.transcript.id, &transcript);
    replay::post(&ctx.router, &items).await?;
    Ok(content)
}
