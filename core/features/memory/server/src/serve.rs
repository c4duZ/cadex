//! Serving the engine on memory.sock (docs/adr/0028-project-memory.md, plan
//! 22 phase C): one engine per data folder (a lock), the socket 0600 and
//! only for this user with a session token (auth.rs), the end of the
//! process when the last `claude` ends (sessions.rs), the restart after the
//! model unloads (restart.rs) and the replay of the hook queue (spool.rs).

use std::fs::File;
use std::future::IntoFuture;
use std::os::fd::{AsFd, OwnedFd};
use std::os::unix::fs::PermissionsExt;
use std::path::Path;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Duration, Instant};

use anyhow::{Context, Result};
use axum::middleware::from_fn_with_state;
use tokio::net::UnixListener;
use tokio_util::sync::CancellationToken;
use tracing::info;

use crate::args::Args;
use crate::auth::{PeerListener, Tokens, require_session_token};
use crate::restart::{InFlight, when_model_unloads};
use crate::sessions::Sessions;
use crate::{engine, restart, sessions, spool, sys};

/// How the engine ended.
pub(crate) enum Exit {
    Done,
    /// Exec a fresh image with these sessions and descriptors.
    Restart { sessions: Vec<i32>, lock: OwnedFd, listener: OwnedFd },
}

/// How long a new engine waits for an old one that holds the lock to
/// finish leaving (it removes the socket and closes the store first).
const LOCK_WAIT: Duration = Duration::from_secs(2);

/// The data folder's lock: SQLite and the wiki take a single writer, and two
/// hooks starting at once would start two engines (plan 22: "escritor
/// único"). `None` when another engine holds it.
async fn lock_data_dir(args: &Args) -> Result<Option<File>> {
    if let Some(fd) = args.lock_fd {
        return Ok(Some(File::from(sys::adopt(fd)?)));
    }
    let path = args.data_dir.join("engine.lock");
    let file = File::options().create(true).truncate(false).write(true).open(&path)
        .with_context(|| format!("opening {}", path.display()))?;
    let deadline = Instant::now() + LOCK_WAIT;
    loop {
        match file.try_lock() {
            Ok(()) => return Ok(Some(file)),
            Err(std::fs::TryLockError::WouldBlock) if Instant::now() < deadline => {
                tokio::time::sleep(Duration::from_millis(20)).await;
            }
            Err(std::fs::TryLockError::WouldBlock) => return Ok(None),
            Err(std::fs::TryLockError::Error(e)) => return Err(e.into()),
        }
    }
}

/// Bind the socket, replacing a stale file, readable only by the owner; or
/// take back the one the previous image handed over.
fn listen(args: &Args) -> Result<UnixListener> {
    if let Some(fd) = args.listen_fd {
        let listener = std::os::unix::net::UnixListener::from(sys::adopt(fd)?);
        listener.set_nonblocking(true)?;
        return Ok(UnixListener::from_std(listener)?);
    }
    let path = &args.socket;
    if path.exists() {
        std::fs::remove_file(path).with_context(|| format!("removing stale {}", path.display()))?;
    }
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir)?;
    }
    let listener = UnixListener::bind(path).with_context(|| format!("binding {}", path.display()))?;
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o600))?;
    Ok(listener)
}

async fn shutdown_signal(cancel: CancellationToken) {
    use tokio::signal::unix::{SignalKind, signal};
    let mut term = signal(SignalKind::terminate()).expect("SIGTERM handler");
    let mut int = signal(SignalKind::interrupt()).expect("SIGINT handler");
    tokio::select! {
        _ = term.recv() => {}
        _ = int.recv() => {}
        () = cancel.cancelled() => return,
    }
    info!("shutdown signal received");
    cancel.cancel();
}

fn remove_socket(path: &Path) {
    let _ = std::fs::remove_file(path);
}

/// Run the engine until a signal, the last session's end or a restart.
pub(crate) async fn run(args: Args, started: Instant) -> Result<Exit> {
    std::fs::create_dir_all(&args.data_dir)?;
    let Some(lock) = lock_data_dir(&args).await? else {
        info!("another cadex-memory serves this data folder; leaving");
        return Ok(Exit::Done);
    };
    let cancel = CancellationToken::new();
    let built = engine::build(&args, &cancel).await?;
    let sessions = Sessions::start();
    for pid in &args.sessions {
        sessions.register(*pid);
    }
    let in_flight = Arc::new(InFlight::default());
    let inner = built
        .router
        .layer(from_fn_with_state(sessions.clone(), sessions::track))
        .layer(from_fn_with_state(in_flight.clone(), restart::count));
    let outer = inner.clone().layer(from_fn_with_state(
        Tokens::new(args.tokens_dir.clone()),
        require_session_token,
    ));

    let listener = listen(&args)?;
    let kept = listener.as_fd().try_clone_to_owned()?;
    info!(
        socket = %args.socket.display(),
        ready_ms = started.elapsed().as_millis() as u64,
        sessions = args.sessions.len(),
        "cadex-memory ready"
    );
    let restarting = Arc::new(AtomicBool::new(false));
    tokio::spawn(shutdown_signal(cancel.clone()));
    if !args.keep_alive {
        tokio::spawn(sessions.clone().exit_when_idle(started, cancel.clone()));
    }
    if let Some(model) = built.model.clone() {
        tokio::spawn(when_model_unloads(model, in_flight.clone(), restarting.clone(), cancel.clone()));
    }
    tokio::spawn(spool::drain(inner, args.spool_dir.clone()));

    let shutdown = cancel.clone();
    let listener = PeerListener::new(listener, sys::effective_uid());
    let served = axum::serve(listener, outer.into_make_service())
        .with_graceful_shutdown(async move { shutdown.cancelled().await })
        .into_future();
    // Graceful shutdown waits for open connections; a client that keeps one
    // open must not hold the engine forever.
    let result = tokio::select! {
        r = served => r.map_err(anyhow::Error::from),
        () = async { cancel.cancelled().await; tokio::time::sleep(Duration::from_secs(5)).await } => Ok(()),
    };
    let _ = tokio::time::timeout(Duration::from_secs(5), built.store.close()).await;
    result?;
    // With no session left the engine would only linger and leave: leaving
    // now also spares the new image the startup grace (found 2026-11-16).
    let live = sessions.pids();
    if restarting.load(Ordering::SeqCst) && (args.keep_alive || !live.is_empty()) {
        return Ok(Exit::Restart { sessions: live, lock: lock.into(), listener: kept });
    }
    remove_socket(&args.socket);
    Ok(Exit::Done)
}
