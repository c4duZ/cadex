//! Who may talk to memory.sock (docs/adr/0028-project-memory.md): the same
//! user, checked on the socket's peer credentials, carrying the token of a
//! session the Cadex kit opened, in `X-Cadex-Token`. The same pair guards the
//! app's socket (apps/macos/features/agent-tools/AgentToolsServer.swift, getpeereid, and
//! AgentSessionTokens.swift). `/healthz` stays open: the packaging smoke test
//! asks it with no session.

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};

use axum::extract::{Request, State};
use axum::http::StatusCode;
use axum::middleware::Next;
use axum::response::{IntoResponse, Response};
use tokio::net::{UnixListener, UnixStream};
use tokio::net::unix::SocketAddr;

/// The header the `cadex memory-hook` client and `cadex mcp` send.
pub(crate) const TOKEN_HEADER: &str = "x-cadex-token";

/// Shorter is not a token the kit wrote (it writes 64 hex characters).
const MIN_TOKEN_LEN: usize = 32;

/// The listening socket, accepting only connections from `uid`.
pub(crate) struct PeerListener {
    inner: UnixListener,
    uid: u32,
}

impl PeerListener {
    pub(crate) fn new(inner: UnixListener, uid: u32) -> Self {
        Self { inner, uid }
    }
}

impl axum::serve::Listener for PeerListener {
    type Io = UnixStream;
    type Addr = SocketAddr;

    async fn accept(&mut self) -> (Self::Io, Self::Addr) {
        loop {
            match self.inner.accept().await {
                Ok((stream, addr)) => match stream.peer_cred() {
                    Ok(cred) if cred.uid() == self.uid => return (stream, addr),
                    // Dropping the stream closes it before a byte is read.
                    Ok(cred) => tracing::warn!(uid = cred.uid(), "closed a connection from another user"),
                    Err(error) => tracing::warn!(%error, "closed a connection without credentials"),
                },
                // Out of descriptors and the like: wait a little, as axum's
                // own listeners do, instead of spinning.
                Err(error) => {
                    tracing::warn!(%error, "accept failed");
                    tokio::time::sleep(std::time::Duration::from_millis(50)).await;
                }
            }
        }
    }

    fn local_addr(&self) -> std::io::Result<Self::Addr> {
        self.inner.local_addr()
    }
}

/// The session tokens on disk: `<tokens dir>/<kitSession>.token`.
pub(crate) struct Tokens {
    dir: PathBuf,
    /// Token -> the kit session it was written for.
    known: Mutex<HashMap<String, String>>,
}

impl Tokens {
    pub(crate) fn new(dir: PathBuf) -> Arc<Self> {
        Arc::new(Self { dir, known: Mutex::new(HashMap::new()) })
    }

    /// The kit session `token` belongs to. A token not seen yet reads the
    /// folder again: the session was opened after the last read.
    pub(crate) fn session_of(&self, token: &str) -> Option<String> {
        if token.len() < MIN_TOKEN_LEN {
            return None;
        }
        let mut known = self.known.lock().unwrap_or_else(|e| e.into_inner());
        if let Some(session) = known.get(token) {
            return Some(session.clone());
        }
        *known = read_tokens(&self.dir);
        known.get(token).cloned()
    }
}

fn read_tokens(dir: &std::path::Path) -> HashMap<String, String> {
    let Ok(entries) = std::fs::read_dir(dir) else { return HashMap::new() };
    entries
        .flatten()
        .filter_map(|entry| {
            let name = entry.file_name().into_string().ok()?;
            let session = name.strip_suffix(".token")?.to_string();
            let token = std::fs::read_to_string(entry.path()).ok()?.trim().to_string();
            Some((token, session))
        })
        .collect()
}

/// Middleware: 401 unless the request carries a known session token.
pub(crate) async fn require_session_token(
    State(tokens): State<Arc<Tokens>>,
    req: Request,
    next: Next,
) -> Response {
    if req.uri().path() == "/healthz" {
        return next.run(req).await;
    }
    let token = req.headers().get(TOKEN_HEADER).and_then(|v| v.to_str().ok()).unwrap_or("");
    if tokens.session_of(token.trim()).is_none() {
        return (StatusCode::UNAUTHORIZED, "a Cadex session token is required\n").into_response();
    }
    next.run(req).await
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_token_written_after_the_first_read_is_found() {
        let dir = tempfile::tempdir().unwrap();
        let tokens = Tokens::new(dir.path().to_path_buf());
        let token = "a".repeat(64);
        assert_eq!(tokens.session_of(&token), None);
        std::fs::write(dir.path().join("kit-1.token"), format!("{token}\n")).unwrap();
        assert_eq!(tokens.session_of(&token).as_deref(), Some("kit-1"));
        assert_eq!(tokens.session_of("short"), None);
        std::fs::write(dir.path().join("kit-2.token"), "short").unwrap();
        assert_eq!(tokens.session_of("short"), None, "too short to be a kit token");
    }
}
