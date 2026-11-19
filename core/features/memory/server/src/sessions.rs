//! The `claude` processes the engine serves, and the engine's exit when the
//! last one ends (plan 22, phase C): each SessionStart names its `claude` pid
//! (`pid=` in the query or `X-Cadex-Pid`), a kqueue says when that process
//! exits, and with no live session left the engine lingers 3 s and leaves.
//! If no session registers within 10 s of the start, it leaves too. Same
//! numbers as the terminal daemon (core/features/terminal/daemon.zig, idle()).
//! No timer runs while sessions are alive.
//!
//! A `cadex-memory run` launcher counts as a session too: its prepare
//! (`POST /workstream/runs?pid=<launcher pid>`) registers the launcher, so
//! the engine outlives the agent it started until the transcript import and
//! the finish are done (plan 22 phase E, 2026-11-16).
//!
//! A memory agent job (agent/queue.rs) has no process of its own to watch,
//! so it holds the engine with a counted guard instead (`hold`): queued or
//! running, it counts as a live session (plan 22 phase G, 2026-11-16).
//!
//! A SessionStart also names its session (`session_id=`): the registry keeps
//! which sessions are live, so the Memory page's preview does not show a
//! running session as an interrupted one (plan 35 H, page/briefing.rs). A
//! restart hands them over with the pids (`--sessions 12:<id>,34`).

use std::collections::{HashMap, HashSet};
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use axum::extract::{Request, State};
use axum::middleware::Next;
use axum::response::Response;
use tokio::sync::Notify;
use tokio_util::sync::CancellationToken;

use crate::sys::ProcWatch;

/// After the last session ends: a `/clear` ends a session and starts the
/// next one in the same `claude`, and a new tab may be a moment away.
pub(crate) const LINGER: Duration = Duration::from_secs(3);
/// Started by a hook whose session never registered (it failed, or it was
/// the app's warm-up run).
pub(crate) const STARTUP_GRACE: Duration = Duration::from_secs(10);

/// A live `claude` (or launcher) and the session it last started, if named.
pub(crate) type Live = (i32, Option<String>);

pub(crate) struct Sessions {
    live: Mutex<HashMap<i32, Option<String>>>,
    /// Agent jobs holding the engine (`hold`).
    holds: AtomicUsize,
    ever: AtomicBool,
    changed: Notify,
    watch: Option<ProcWatch>,
}

impl Sessions {
    /// The registry, with a thread blocked on the kqueue for exits.
    pub(crate) fn start() -> Arc<Self> {
        let watch = ProcWatch::new()
            .map_err(|error| tracing::warn!(%error, "no kqueue: sessions are not tracked"))
            .ok();
        let sessions = Arc::new(Self {
            live: Mutex::new(HashMap::new()),
            holds: AtomicUsize::new(0),
            ever: AtomicBool::new(false),
            changed: Notify::new(),
            watch,
        });
        if sessions.watch.is_some() {
            let waiter = sessions.clone();
            std::thread::Builder::new()
                .name("cadex-memory-sessions".into())
                .spawn(move || {
                    let Some(watch) = waiter.watch.as_ref() else { return };
                    while let Ok(pid) = watch.wait() {
                        waiter.ended(pid);
                    }
                })
                .expect("sessions thread");
        }
        sessions
    }

    fn live(&self) -> std::sync::MutexGuard<'_, HashMap<i32, Option<String>>> {
        self.live.lock().unwrap_or_else(|e| e.into_inner())
    }

    /// A session's `claude` is `pid`, running `session` when named (a
    /// `/clear` starts the next session in the same `claude`: the newer name
    /// wins). A pid already gone counts as a session that ended (it starts
    /// the linger). Pid 1 is launchd: the hook's parent died and the hook
    /// was adopted.
    pub(crate) fn register(&self, pid: i32, session: Option<&str>) {
        if pid <= 1 {
            return;
        }
        self.ever.store(true, Ordering::SeqCst);
        let alive = match &self.watch {
            Some(watch) => watch.watch(pid).unwrap_or(false),
            None => false,
        };
        if alive {
            let mut live = self.live();
            let named = live.entry(pid).or_default();
            if let Some(session) = session {
                *named = Some(session.to_owned());
            }
        }
        self.changed.notify_one();
    }

    /// `pid` exited, or its session sent SessionEnd.
    pub(crate) fn ended(&self, pid: i32) {
        self.live().remove(&pid);
        self.changed.notify_one();
    }

    /// The pids still alive.
    pub(crate) fn pids(&self) -> Vec<i32> {
        let mut pids: Vec<i32> = self.live().keys().copied().collect();
        pids.sort_unstable();
        pids
    }

    /// The pids still alive with their sessions, for a restart.
    pub(crate) fn handover(&self) -> Vec<Live> {
        let mut live: Vec<Live> = self.live().iter().map(|(pid, id)| (*pid, id.clone())).collect();
        live.sort_unstable();
        live
    }

    /// The sessions whose `claude` is still running, as their SessionStart
    /// named them.
    pub(crate) fn live_sessions(&self) -> HashSet<String> {
        self.live().values().flatten().cloned().collect()
    }

    fn is_empty(&self) -> bool {
        self.live().is_empty() && self.holds.load(Ordering::SeqCst) == 0
    }

    /// Keep the engine up until the guard drops, as a live session would.
    pub(crate) fn hold(self: &Arc<Self>) -> SessionsHold {
        self.ever.store(true, Ordering::SeqCst);
        self.holds.fetch_add(1, Ordering::SeqCst);
        self.changed.notify_one();
        SessionsHold(self.clone())
    }

    /// Cancel `stop` once no session is left (see the module comment).
    pub(crate) async fn exit_when_idle(self: Arc<Self>, started: Instant, stop: CancellationToken) {
        loop {
            if !self.is_empty() {
                tokio::select! {
                    () = self.changed.notified() => continue,
                    () = stop.cancelled() => return,
                }
            }
            let wait = if self.ever.load(Ordering::SeqCst) {
                LINGER
            } else {
                STARTUP_GRACE.saturating_sub(started.elapsed())
            };
            tokio::select! {
                () = tokio::time::sleep(wait) => {
                    if self.is_empty() {
                        tracing::info!("no agent session left; cadex-memory exits");
                        stop.cancel();
                        return;
                    }
                }
                () = self.changed.notified() => {}
                () = stop.cancelled() => return,
            }
        }
    }
}

/// See `Sessions::hold`.
pub(crate) struct SessionsHold(Arc<Sessions>);

impl Drop for SessionsHold {
    fn drop(&mut self) {
        self.0.holds.fetch_sub(1, Ordering::SeqCst);
        self.0.changed.notify_one();
    }
}

/// What a `/hook` request says about sessions: (event, pid, session). The
/// session only when it fits a file name (audit.rs's rule: Claude Code's are
/// UUIDs, so nothing to decode).
fn hook_session(query: &str, header_pid: Option<i32>) -> Option<(&str, i32, Option<&str>)> {
    let mut event = None;
    let mut pid = header_pid;
    let mut session = None;
    for pair in query.split('&') {
        match pair.split_once('=') {
            Some(("event", value)) => event = Some(value),
            Some(("pid", value)) => pid = value.parse().ok().or(pid),
            Some(("session_id", value)) => {
                session = Some(value).filter(|v| crate::agent::audit::session_file_name(v).is_some());
            }
            _ => {}
        }
    }
    Some((event?, pid?, session))
}

/// The `pid=` of a query, if any.
fn query_pid(query: &str) -> Option<i32> {
    query.split('&').find_map(|pair| match pair.split_once('=') {
        Some(("pid", value)) => value.parse().ok(),
        _ => None,
    })
}

/// Middleware: SessionStart registers its `claude`, SessionEnd removes it,
/// and a managed run's prepare registers its launcher (the kqueue removes it
/// when the launcher exits). On the inner router, so a SessionStart replayed
/// from the spool counts too.
pub(crate) async fn track(State(sessions): State<Arc<Sessions>>, req: Request, next: Next) -> Response {
    if req.uri().path() == "/workstream/runs" && req.method() == axum::http::Method::POST {
        if let Some(pid) = query_pid(req.uri().query().unwrap_or("")) {
            sessions.register(pid, None);
        }
    } else if req.uri().path() == "/hook" {
        let header_pid = req
            .headers()
            .get("x-cadex-pid")
            .and_then(|v| v.to_str().ok())
            .and_then(|v| v.trim().parse().ok());
        if let Some((event, pid, session)) = hook_session(req.uri().query().unwrap_or(""), header_pid) {
            match event {
                "session-start" | "session_start" | "SessionStart" => sessions.register(pid, session),
                "session-end" | "session_end" | "SessionEnd" => sessions.ended(pid),
                _ => {}
            }
        }
    }
    next.run(req).await
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_query_or_the_header_names_the_pid() {
        assert_eq!(hook_session("event=session-start&agent=claude-code&pid=42", None), Some(("session-start", 42, None)));
        assert_eq!(hook_session("event=session-end", Some(7)), Some(("session-end", 7, None)));
        assert_eq!(hook_session("event=session-start&session_id=s-1&pid=9", None), Some(("session-start", 9, Some("s-1"))));
        assert_eq!(hook_session("event=session-start&session_id=..%2Fx&pid=9", None), Some(("session-start", 9, None)));
        assert_eq!(hook_session("event=stop&pid=x", None), None);
        assert_eq!(hook_session("pid=3", None), None);
        assert_eq!(query_pid("pid=31"), Some(31));
        assert_eq!(query_pid("x=1&pid=y"), None);
    }

    #[tokio::test]
    async fn the_last_session_ending_stops_the_engine_after_the_linger() {
        let sessions = Sessions::start();
        let mut child = std::process::Command::new("/bin/sleep").arg("30").spawn().unwrap();
        let pid = child.id() as i32;
        sessions.register(pid, Some("s-1"));
        sessions.register(pid, None);
        sessions.register(1, Some("s-2"));
        assert_eq!(sessions.pids(), vec![pid]);
        assert_eq!(sessions.handover(), vec![(pid, Some("s-1".to_owned()))], "a start with no name keeps the session");
        assert_eq!(sessions.live_sessions(), HashSet::from(["s-1".to_owned()]));
        let stop = CancellationToken::new();
        let started = Instant::now();
        let watcher = tokio::spawn(sessions.clone().exit_when_idle(started, stop.clone()));
        tokio::time::sleep(Duration::from_millis(200)).await;
        assert!(!stop.is_cancelled());
        let killed = Instant::now();
        child.kill().unwrap();
        child.wait().unwrap();
        tokio::time::timeout(LINGER + Duration::from_secs(2), watcher).await.unwrap().unwrap();
        assert!(stop.is_cancelled() && killed.elapsed() >= LINGER - Duration::from_millis(100));
        assert!(sessions.pids().is_empty() && sessions.live_sessions().is_empty());
    }
}
