//! The memory agent's queue (ADR 0029: "fila no `cadex-memory`, um trabalho
//! por vez"; plan 22 phase G, 2026-11-16): first in, first out, one job at
//! a time, the same job (kind, project, session) never twice in the queue.
//! Pausing (in memory only) keeps jobs queued and starts none.
//!
//! Keeping the engine up: a job has no process the session registry can
//! watch, so while one is queued or running the queue holds a
//! `SessionsHold` (the engine does not leave 3 s after the last session)
//! and an `InFlight` guard (the restart that gives memory back waits, as
//! for the import). The queue lives in memory, so a restart in the middle
//! would lose it. While paused with nothing running the holds are let go:
//! a paused queue must not keep the engine up forever, and what it held is
//! lost when the engine leaves (the next event queues again).

use std::collections::VecDeque;
use std::path::PathBuf;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Duration, Instant};

use serde::Serialize;
use tokio::sync::Notify;

use super::Ctx;
use crate::restart::InFlightGuard;
use crate::sessions::SessionsHold;

/// What a job does.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "kebab-case")]
pub(crate) enum Kind {
    /// A live SessionEnd: consolidate, profile, auto-improve and experience.
    SessionEnd,
    /// After a compaction: consolidate the session so far.
    Compact,
    Dream,
    Bootstrap,
}

impl Kind {
    pub(crate) fn as_str(self) -> &'static str {
        match self {
            Kind::SessionEnd => "session-end",
            Kind::Compact => "compact",
            Kind::Dream => "dream",
            Kind::Bootstrap => "bootstrap",
        }
    }
}

/// The project a job is about.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct Scope {
    pub(crate) workspace: String,
    pub(crate) project: String,
    /// The main repository root, for the project's account.
    pub(crate) root: Option<PathBuf>,
}

#[derive(Debug, Clone)]
pub(crate) struct Job {
    pub(crate) kind: Kind,
    pub(crate) scope: Scope,
    pub(crate) session: Option<String>,
    /// Asked by the owner (a route), not set off by an event: a manual
    /// dream is not stopped when the owner is at the keyboard.
    pub(crate) manual: bool,
    /// An event's job waits `--import-delay-ms`, so upstream's own end of the
    /// session (and the briefing) go first, as maintenance does.
    pub(crate) not_before: Instant,
}

impl Job {
    fn same(&self, other: &Job) -> bool {
        self.kind == other.kind && self.scope == other.scope && self.session == other.session
    }
}

/// One queue row for the status route.
#[derive(Debug, Clone, Serialize)]
pub(crate) struct Row {
    pub(crate) kind: Kind,
    pub(crate) workspace: String,
    pub(crate) project: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub(crate) session: Option<String>,
    pub(crate) state: &'static str,
}

fn row(job: &Job, state: &'static str) -> Row {
    Row {
        kind: job.kind,
        workspace: job.scope.workspace.clone(),
        project: job.scope.project.clone(),
        session: job.session.clone(),
        state,
    }
}

#[derive(Default)]
struct State {
    queue: VecDeque<Job>,
    running: Option<Job>,
    hold: Option<(SessionsHold, InFlightGuard)>,
}

pub(crate) struct Queue {
    state: std::sync::Mutex<State>,
    wake: Notify,
    paused: AtomicBool,
}

impl Queue {
    pub(crate) fn new() -> Self {
        Self { state: std::sync::Mutex::new(State::default()), wake: Notify::new(), paused: AtomicBool::new(false) }
    }

    fn state(&self) -> std::sync::MutexGuard<'_, State> {
        self.state.lock().unwrap_or_else(|e| e.into_inner())
    }

    /// Queue `job` unless the same one is queued; `false` when it was.
    pub(crate) fn push(&self, ctx: &Ctx, job: Job) -> bool {
        let mut st = self.state();
        if st.queue.iter().any(|queued| queued.same(&job)) {
            return false;
        }
        st.queue.push_back(job);
        if st.hold.is_none() {
            st.hold = Some((ctx.sessions.hold(), ctx.in_flight.hold()));
        }
        drop(st);
        self.wake.notify_one();
        true
    }

    pub(crate) fn set_paused(&self, on: bool) {
        self.paused.store(on, Ordering::SeqCst);
        self.wake.notify_one();
    }

    pub(crate) fn paused(&self) -> bool {
        self.paused.load(Ordering::SeqCst)
    }

    /// The running job first, then the queue in order.
    pub(crate) fn rows(&self) -> Vec<Row> {
        let st = self.state();
        st.running.iter().map(|j| row(j, "running")).chain(st.queue.iter().map(|j| row(j, "queued"))).collect()
    }

    /// The next job to run, or how long to wait for one (`None`: until woken).
    fn take(&self) -> Result<Job, Option<Duration>> {
        let mut st = self.state();
        if self.paused() || st.queue.is_empty() {
            if st.running.is_none() {
                st.hold = None;
            }
            return Err(None);
        }
        let now = Instant::now();
        let ready = st.queue.iter().position(|j| j.not_before <= now);
        match ready {
            Some(i) => {
                let job = st.queue.remove(i).expect("index from position");
                st.running = Some(job.clone());
                Ok(job)
            }
            None => Err(st.queue.iter().map(|j| j.not_before - now).min()),
        }
    }

    fn finished(&self) {
        let mut st = self.state();
        st.running = None;
        if st.queue.is_empty() {
            st.hold = None;
        }
    }

    /// The worker: run the jobs one by one until the engine stops.
    pub(crate) async fn work(self: Arc<Self>, ctx: Arc<Ctx>) {
        loop {
            let job = match self.take() {
                Ok(job) => job,
                Err(wait) => {
                    let sleep = async {
                        match wait {
                            Some(d) => tokio::time::sleep(d).await,
                            None => std::future::pending().await,
                        }
                    };
                    tokio::select! {
                        () = self.wake.notified() => {}
                        () = sleep => {}
                        () = ctx.stop.cancelled() => return,
                    }
                    continue;
                }
            };
            tokio::select! {
                () = super::jobs::run(&ctx, &self, &job) => {}
                () = ctx.stop.cancelled() => return,
            }
            self.finished();
        }
    }
}
