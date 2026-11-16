//! Give memory back after the embedding model unloads (plan 22, phase D
//! measurement, 2026-11-15): with the model dropped the footprint stayed at
//! 68 MB, because the allocator keeps what the model used; a fresh process
//! is ~12 MB. So once the lazy embedder drops the model and no request is in
//! flight, the engine finishes, closes the store and execs itself again
//! (~70 ms), handing over the live sessions (`--sessions`), the data
//! folder's lock and the listening socket, so no hook finds the socket gone
//! and no second engine starts in between.

use std::os::fd::{AsRawFd, OwnedFd};
use std::os::unix::process::CommandExt;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};

use axum::extract::{Request, State};
use axum::middleware::Next;
use axum::response::Response;
use tokio::sync::Notify;
use tokio_util::sync::CancellationToken;

/// What the lazy embedder tells the engine about its model.
#[derive(Default)]
pub(crate) struct ModelEvents {
    pub(crate) loaded: AtomicBool,
    pub(crate) unloaded: Notify,
    /// A download of the model is running: the Memory page's "downloading"
    /// (plan 22 phase H, page/overview.rs).
    pub(crate) fetching: AtomicBool,
}

/// Requests being served right now, on the inner router (spool replays count).
#[derive(Default)]
pub(crate) struct InFlight {
    count: AtomicUsize,
    zero: Notify,
}

pub(crate) struct InFlightGuard(Arc<InFlight>);

impl Drop for InFlightGuard {
    fn drop(&mut self) {
        if self.0.count.fetch_sub(1, Ordering::SeqCst) == 1 {
            self.0.zero.notify_waiters();
        }
    }
}

impl InFlight {
    /// Count work that is not a request (an import, import.rs) as in flight
    /// until the guard drops, so the restart waits for it.
    pub(crate) fn hold(self: &Arc<Self>) -> InFlightGuard {
        self.count.fetch_add(1, Ordering::SeqCst);
        InFlightGuard(self.clone())
    }

    async fn idle(&self) {
        loop {
            let zero = self.zero.notified();
            if self.count.load(Ordering::SeqCst) == 0 {
                return;
            }
            zero.await;
        }
    }
}

/// Middleware: count the request while it is served.
pub(crate) async fn count(State(in_flight): State<Arc<InFlight>>, req: Request, next: Next) -> Response {
    in_flight.count.fetch_add(1, Ordering::SeqCst);
    let _guard = InFlightGuard(in_flight);
    next.run(req).await
}

/// Set `restart` and cancel `stop` after the model unloads with nothing in
/// flight. Event-driven: it sleeps on the unload notice.
pub(crate) async fn when_model_unloads(
    model: Arc<ModelEvents>,
    in_flight: Arc<InFlight>,
    restart: Arc<AtomicBool>,
    stop: CancellationToken,
) {
    loop {
        tokio::select! {
            () = model.unloaded.notified() => {}
            () = stop.cancelled() => return,
        }
        in_flight.idle().await;
        // A request between the unload and now may have loaded it again.
        if model.loaded.load(Ordering::SeqCst) {
            continue;
        }
        tracing::info!("model unloaded and nothing in flight; restarting to give memory back");
        restart.store(true, Ordering::SeqCst);
        stop.cancel();
        return;
    }
}

/// Replace this process with a fresh copy of itself. Only returns on error.
pub(crate) fn exec(sessions: &[i32], lock: &OwnedFd, listener: &OwnedFd) -> anyhow::Error {
    let argv: Vec<String> = std::env::args().skip(1).collect();
    let next = crate::args::restart_argv(&argv, sessions, lock.as_raw_fd(), listener.as_raw_fd());
    for fd in [lock.as_raw_fd(), listener.as_raw_fd()] {
        if let Err(error) = crate::sys::inherit_on_exec(fd) {
            return error.into();
        }
    }
    let exe = match std::env::current_exe() {
        Ok(exe) => exe,
        Err(error) => return error.into(),
    };
    std::process::Command::new(exe).args(next).exec().into()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn an_unload_restarts_only_once_nothing_is_in_flight() {
        let model = Arc::new(ModelEvents::default());
        let in_flight = Arc::new(InFlight::default());
        let restart = Arc::new(AtomicBool::new(false));
        let stop = CancellationToken::new();
        in_flight.count.fetch_add(1, Ordering::SeqCst);
        let guard = InFlightGuard(in_flight.clone());
        let task = tokio::spawn(when_model_unloads(model.clone(), in_flight, restart.clone(), stop.clone()));
        tokio::task::yield_now().await;
        model.unloaded.notify_one();
        tokio::time::sleep(std::time::Duration::from_millis(50)).await;
        assert!(!stop.is_cancelled(), "a request was still in flight");
        drop(guard);
        task.await.unwrap();
        assert!(stop.is_cancelled() && restart.load(Ordering::SeqCst));
    }
}
