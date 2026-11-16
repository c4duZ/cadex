//! What the engine's integration tests share: start `cadex-memory` on a
//! socket in a temporary folder with a session token on disk, and speak
//! HTTP/1.1 to it the way `cadex memory-hook` does.

#![allow(dead_code)]

pub mod agent;
pub mod bench;

use std::io::{Read, Write};
use std::os::unix::net::UnixStream;
use std::path::{Path, PathBuf};
use std::process::{Child, Command};
use std::time::{Duration, Instant};

/// The token the tests' kit session wrote (64 hex characters, as the app's).
pub const TOKEN: &str = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";

pub struct Engine {
    pub child: Child,
    pub socket: PathBuf,
}

impl Drop for Engine {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

impl Engine {
    /// Whether the process ended within `limit`.
    pub fn exits_within(&mut self, limit: Duration) -> bool {
        let deadline = Instant::now() + limit;
        while Instant::now() < deadline {
            if self.child.try_wait().ok().flatten().is_some() {
                return true;
            }
            std::thread::sleep(Duration::from_millis(50));
        }
        false
    }
}

/// Start the engine in `dir` with `extra` arguments; wait for /healthz.
pub fn start(dir: &Path, extra: &[&str]) -> Engine {
    start_with_env(dir, extra, &[])
}

/// `start`, with more variables in the engine's environment.
pub fn start_with_env(dir: &Path, extra: &[&str], env: &[(&str, &str)]) -> Engine {
    let socket = dir.join("m.sock");
    let tokens = dir.join("sessions");
    std::fs::create_dir_all(&tokens).unwrap();
    std::fs::write(tokens.join("kit-test.token"), TOKEN).unwrap();
    let child = Command::new(env!("CARGO_BIN_EXE_cadex-memory"))
        .args(["--socket", socket.to_str().unwrap()])
        .args(["--data-dir", dir.join("data").to_str().unwrap()])
        .args(["--tokens-dir", tokens.to_str().unwrap()])
        .arg("--no-embeddings")
        .args(extra)
        .env("HOME", dir)
        // CADEX_TEST_ENGINE_LOG=info (or a filter) to see what a failing
        // run's engine did; its log goes to the test's output.
        .env("CADEX_MEMORY_LOG", std::env::var("CADEX_TEST_ENGINE_LOG").unwrap_or_else(|_| "warn".into()))
        .envs(env.iter().copied())
        .spawn()
        .expect("spawn cadex-memory");
    let engine = Engine { child, socket };
    let deadline = Instant::now() + Duration::from_secs(20);
    while Instant::now() < deadline {
        if request(&engine.socket, "GET", "/healthz", None, None).is_some_and(|(s, _)| s == 200) {
            return engine;
        }
        std::thread::sleep(Duration::from_millis(50));
    }
    panic!("cadex-memory did not answer on {}", engine.socket.display());
}

/// One HTTP/1.1 request over the Unix socket: (status, body).
pub fn request(socket: &Path, method: &str, path: &str, body: Option<&str>, token: Option<&str>) -> Option<(u16, String)> {
    let token: Vec<(&str, &str)> = token.map(|t| ("X-Cadex-Token", t)).into_iter().collect();
    request_with(socket, method, path, body, &token)
}

/// `request` with any headers.
pub fn request_with(socket: &Path, method: &str, path: &str, body: Option<&str>, headers: &[(&str, &str)]) -> Option<(u16, String)> {
    let mut stream = UnixStream::connect(socket).ok()?;
    let body = body.unwrap_or("");
    let token: String = headers.iter().map(|(k, v)| format!("{k}: {v}\r\n")).collect();
    let head = format!(
        "{method} {path} HTTP/1.1\r\nHost: localhost\r\n{token}Content-Type: application/json\r\n\
         Accept: application/json, text/event-stream\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
        body.len()
    );
    stream.write_all(head.as_bytes()).ok()?;
    stream.write_all(body.as_bytes()).ok()?;
    let mut raw = Vec::new();
    stream.read_to_end(&mut raw).ok()?;
    let text = String::from_utf8_lossy(&raw).into_owned();
    let (headers, payload) = text.split_once("\r\n\r\n")?;
    let status: u16 = headers.split_whitespace().nth(1)?.parse().ok()?;
    if headers.to_ascii_lowercase().contains("transfer-encoding: chunked") {
        return Some((status, dechunk(payload)));
    }
    Some((status, payload.to_string()))
}

/// The body of a 2xx answer to a request with the session token.
pub fn ok(socket: &Path, method: &str, path: &str, body: Option<&str>) -> Option<String> {
    request(socket, method, path, body, Some(TOKEN)).filter(|(s, _)| (200..300).contains(s)).map(|(_, b)| b)
}

fn dechunk(mut rest: &str) -> String {
    let mut out = String::new();
    while let Some((size, tail)) = rest.split_once("\r\n") {
        let n = usize::from_str_radix(size.trim(), 16).unwrap_or(0);
        if n == 0 || tail.len() < n {
            break;
        }
        out.push_str(&tail[..n]);
        rest = tail[n..].trim_start_matches("\r\n");
    }
    out
}

pub fn tool(socket: &Path, name: &str, arguments: serde_json::Value) -> String {
    let call = serde_json::json!({
        "jsonrpc": "2.0", "id": 1, "method": "tools/call",
        "params": {"name": name, "arguments": arguments},
    });
    ok(socket, "POST", "/mcp", Some(&call.to_string())).unwrap_or_else(|| panic!("{name} failed"))
}

/// `tool`, as the MCP call of hook session `session` (upstream's bridge
/// header, which routes an unscoped call to the session's project).
pub fn tool_in_session(socket: &Path, session: &str, name: &str, arguments: serde_json::Value) -> String {
    let call = serde_json::json!({
        "jsonrpc": "2.0", "id": 1, "method": "tools/call",
        "params": {"name": name, "arguments": arguments},
    });
    let headers = [("X-Cadex-Token", TOKEN), ("X-Memory-Actor-Session-Id", session)];
    request_with(socket, "POST", "/mcp", Some(&call.to_string()), &headers)
        .filter(|(s, _)| *s == 200)
        .map(|(_, b)| b)
        .unwrap_or_else(|| panic!("{name} failed"))
}

pub fn query(pairs: &[(&str, &str)]) -> String {
    pairs
        .iter()
        .map(|(k, v)| format!("{k}={}", v.replace('/', "%2F").replace(' ', "%20")))
        .collect::<Vec<_>>()
        .join("&")
}

/// A git repository named `name` in `dir`, as a project's folder.
pub fn repo(dir: &Path, name: &str) -> PathBuf {
    let project = dir.join(name);
    std::fs::create_dir_all(&project).unwrap();
    assert!(Command::new("git").args(["init", "-q"]).current_dir(&project).status().unwrap().success());
    project
}
