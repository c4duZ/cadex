//! Memory maintenance on events, never by a clock (plan 22 phase F: "a
//! manutenção (forget sweep, lint de regras, decaimento), disparados por
//! evento (fim de sessão, subida do processo), nunca por relógio", 2026-11-16).
//!
//! Upstream's server runs these jobs on timers (serve.rs
//! `start_maintenance_scheduler`: sweep and lint daily, hollow projects
//! daily, embedding backfill at start). Here two events stand in for the
//! timers: the engine's start (not the restart that gives memory back, whose
//! previous image had its start) and each live SessionEnd on `/hook`. An event
//! runs the jobs it finds due (maintenance_state.rs); one that comes too soon
//! is skipped. No task sleeps toward a next run.
//!
//! A run never delays a SessionStart: it waits `--import-delay-ms` after the
//! event (the briefing and, at a SessionEnd, upstream's own end of the
//! session go first), takes the background lane the import also takes (so the
//! start's import of outside sessions runs before it), and holds the restart
//! (restart.rs) while it writes, as the import does.

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::Duration;

use axum::extract::{Query, Request, State};
use axum::middleware::Next;
use axum::response::Response;
use tokio::sync::{Mutex, mpsc};
use tokio_util::sync::CancellationToken;

use crate::maintenance_jobs::{self, Job, Stores};
use crate::maintenance_state;
use crate::restart::InFlight;

/// One background writer at a time: the import (import.rs) and maintenance.
pub(crate) type Lane = Arc<Mutex<()>>;

pub(crate) fn lane() -> Lane {
    Arc::new(Mutex::new(()))
}

/// What set a run off.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum Trigger {
    Start,
    SessionEnd,
}

pub(crate) type Sender = mpsc::UnboundedSender<()>;
pub(crate) type Receiver = mpsc::UnboundedReceiver<()>;

pub(crate) fn channel() -> (Sender, Receiver) {
    mpsc::unbounded_channel()
}

/// Middleware on the inner router (spool replays count): a SessionEnd the
/// router took on `/hook` is an event. The imported sessions' ends go to
/// `/hook/batch` and are not: a backfill of 200 sessions is not 200 events.
pub(crate) async fn watch(State(tx): State<Sender>, req: Request, next: Next) -> Response {
    let ended = req.uri().path() == "/hook"
        && Query::<HashMap<String, String>>::try_from_uri(req.uri())
            .is_ok_and(|Query(q)| matches!(q.get("event").map(String::as_str), Some("session-end" | "session_end")));
    let response = next.run(req).await;
    if ended && response.status().is_success() {
        let _ = tx.send(());
    }
    response
}

/// What a run needs from the engine.
pub(crate) struct Context {
    pub(crate) stores: Stores,
    pub(crate) data_dir: PathBuf,
    /// `--import-delay-ms`: how long after its event a run waits.
    pub(crate) delay: Duration,
    pub(crate) lane: Lane,
    pub(crate) in_flight: Arc<InFlight>,
    pub(crate) stop: CancellationToken,
}

/// Run on the start (unless this image is a restart), then on each SessionEnd,
/// until the engine stops.
pub(crate) async fn run(ctx: Context, mut rx: Receiver, at_start: bool) {
    if at_start {
        if !wait(&ctx, ctx.delay).await {
            return;
        }
        pass(&ctx, Trigger::Start).await;
    }
    loop {
        tokio::select! {
            got = rx.recv() => if got.is_none() { return },
            () = ctx.stop.cancelled() => return,
        }
        if !wait(&ctx, ctx.delay).await {
            return;
        }
        // Ends that came during the wait are the same event.
        while rx.try_recv().is_ok() {}
        pass(&ctx, Trigger::SessionEnd).await;
    }
}

/// Sleep `d` unless the engine stops first (`false`).
async fn wait(ctx: &Context, d: Duration) -> bool {
    tokio::select! {
        () = tokio::time::sleep(d) => true,
        () = ctx.stop.cancelled() => false,
    }
}

/// The jobs `trigger` may run that are due now.
pub(crate) fn due(ctx: &Context, trigger: Trigger) -> Vec<Job> {
    Job::ALL
        .into_iter()
        .filter(|job| trigger == Trigger::Start || job.on_session_end())
        .filter(|job| maintenance_state::due_now(&ctx.data_dir, job.name(), job.min_interval()))
        .collect()
}

/// Run the due jobs, one after another, stamping each success.
async fn pass(ctx: &Context, trigger: Trigger) {
    if due(ctx, trigger).is_empty() {
        tracing::debug!(?trigger, "maintenance: nothing due");
        return;
    }
    let _lane = tokio::select! {
        guard = ctx.lane.lock() => guard,
        () = ctx.stop.cancelled() => return,
    };
    let _hold = ctx.in_flight.hold();
    // Read again under the lane: the import may have taken a while.
    for job in due(ctx, trigger) {
        if ctx.stop.is_cancelled() {
            return;
        }
        let started_at = maintenance_state::now_us();
        match maintenance_jobs::run(job, &ctx.stores, &ctx.stop).await {
            Ok(true) => {
                if let Err(error) = maintenance_state::record(&ctx.data_dir, job.name(), started_at) {
                    tracing::warn!(job = job.name(), error = %format!("{error:#}"), "maintenance stamp not written");
                }
            }
            Ok(false) => {}
            Err(error) => tracing::warn!(job = job.name(), ?trigger, error = %format!("{error:#}"), "maintenance job failed; the next event tries again"),
        }
    }
}
