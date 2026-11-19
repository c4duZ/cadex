//! The launcher's HTTP client for memory.sock: one HTTP/1.1 request per
//! connection (hyper's client connection over a tokio Unix stream), JSON
//! bodies and the session token in `X-Cadex-Token` (auth.rs). Stands in for
//! upstream's reqwest-based `http_client.rs` (`get_json`, `post_json`,
//! `post_empty`, `post_json_no_content`, `ServerResponseError`, ai-memory
//! fa0ec25, unchanged at v3.5.0 = 411d90d): the engine has no TCP endpoint (ADR 0028). Plan 22 phase E,
//! 2026-11-16.

use std::fmt;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result};
use http_body_util::{BodyExt, Full};
use hyper::body::Bytes;
use hyper::{Method, Request, StatusCode};
use hyper_util::rt::TokioIo;
use serde::Serialize;
use serde::de::DeserializeOwned;
use tokio::net::UnixStream;

/// The engine answered with a status outside 2xx (upstream's
/// `ServerResponseError`): the path, never the token, and the body.
#[derive(Debug)]
pub(crate) struct ServerResponseError {
    method: Method,
    path: String,
    status: StatusCode,
    body: String,
}

impl ServerResponseError {
    pub(crate) const fn status(&self) -> StatusCode {
        self.status
    }

    pub(crate) fn body(&self) -> &str {
        &self.body
    }
}

impl fmt::Display for ServerResponseError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let detail = serde_json::from_str::<serde_json::Value>(&self.body)
            .ok()
            .and_then(|v| v.get("error").and_then(|e| e.as_str()).map(str::to_owned))
            .unwrap_or_else(|| self.body.trim().to_owned());
        write!(f, "{} {} answered {}: {}", self.method, self.path, self.status, super::terminal_text(&detail))
    }
}

impl std::error::Error for ServerResponseError {}

/// The engine could not be reached at all (no socket, refused, cut off):
/// upstream's reqwest transport error, which `is_unreachable_error` tells
/// apart from an answer.
#[derive(Debug)]
pub(crate) struct Unreachable(pub(crate) String);

impl fmt::Display for Unreachable {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "the memory engine is unreachable: {}", self.0)
    }
}

impl std::error::Error for Unreachable {}

/// Upstream's `is_unreachable_error`: no answer from the engine.
pub(crate) fn is_unreachable_error(error: &anyhow::Error) -> bool {
    let answered = error.chain().any(|c| c.downcast_ref::<ServerResponseError>().is_some());
    let transport = error.chain().any(|c| c.downcast_ref::<Unreachable>().is_some());
    !answered && transport
}

/// memory.sock and the session token every request carries.
#[derive(Clone, Debug)]
pub(crate) struct Client {
    socket: PathBuf,
    token: String,
}

impl Client {
    pub(crate) fn new(socket: &Path, token: &str) -> Self {
        Self { socket: socket.to_path_buf(), token: token.to_owned() }
    }

    async fn send(&self, method: Method, path: &str, body: Vec<u8>) -> Result<(StatusCode, Bytes)> {
        let unreachable = |e: &dyn fmt::Display| Unreachable(format!("{}: {e}", self.socket.display()));
        let stream = UnixStream::connect(&self.socket).await.map_err(|e| unreachable(&e))?;
        let (mut sender, conn) =
            hyper::client::conn::http1::handshake(TokioIo::new(stream)).await.map_err(|e| unreachable(&e))?;
        tokio::spawn(async move {
            let _ = conn.await;
        });
        let request = Request::builder()
            .method(method)
            .uri(path)
            .header(hyper::header::HOST, "localhost")
            .header("x-cadex-token", &self.token)
            .header(hyper::header::CONTENT_TYPE, "application/json")
            .header(hyper::header::ACCEPT, "application/json")
            .body(Full::new(Bytes::from(body)))
            .context("building the request")?;
        let response = sender.send_request(request).await.map_err(|e| unreachable(&e))?;
        let status = response.status();
        let bytes = response.into_body().collect().await.map_err(|e| unreachable(&e))?.to_bytes();
        Ok((status, bytes))
    }

    /// The body of a 2xx answer, else a [`ServerResponseError`].
    async fn call(&self, method: Method, path: &str, body: Vec<u8>) -> Result<Bytes> {
        let (status, bytes) = self.send(method.clone(), path, body).await?;
        if status.is_success() {
            return Ok(bytes);
        }
        let route = path.split('?').next().unwrap_or(path).to_owned();
        Err(ServerResponseError { method, path: route, status, body: String::from_utf8_lossy(&bytes).into_owned() }.into())
    }

    /// `GET /healthz` answered 200 (it needs no token).
    pub(crate) async fn healthy(&self) -> bool {
        matches!(self.send(Method::GET, "/healthz", Vec::new()).await, Ok((s, _)) if s.is_success())
    }

    pub(crate) async fn get_json<T: DeserializeOwned>(&self, path: &str) -> Result<T> {
        let bytes = self.call(Method::GET, path, Vec::new()).await?;
        serde_json::from_slice(&bytes).with_context(|| format!("reading the answer to GET {path}"))
    }

    pub(crate) async fn post_json<B: Serialize, T: DeserializeOwned>(&self, path: &str, body: &B) -> Result<T> {
        let bytes = self.call(Method::POST, path, serde_json::to_vec(body)?).await?;
        let route = path.split('?').next().unwrap_or(path);
        serde_json::from_slice(&bytes).with_context(|| format!("reading the answer to POST {route}"))
    }

    pub(crate) async fn post_json_no_content<B: Serialize>(&self, path: &str, body: &B) -> Result<()> {
        self.call(Method::POST, path, serde_json::to_vec(body)?).await.map(|_| ())
    }

    pub(crate) async fn post_empty(&self, path: &str) -> Result<()> {
        self.call(Method::POST, path, Vec::new()).await.map(|_| ())
    }
}
