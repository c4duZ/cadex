//! The engine end to end, the way the Cadex hooks and MCP reach it: start the
//! binary on a socket in a temporary folder, write pages through MCP, open a
//! session through the hook routes and read the briefing back, then search.
//! Runs without the embedding model (no download in tests) and without the
//! wiki watcher, as `make check` does.

use std::io::{Read, Write};
use std::os::unix::net::UnixStream;
use std::path::{Path, PathBuf};
use std::process::{Child, Command};
use std::time::{Duration, Instant};

struct Engine {
    child: Child,
    socket: PathBuf,
}

impl Drop for Engine {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

fn start(dir: &Path) -> Engine {
    let socket = dir.join("m.sock");
    let child = Command::new(env!("CARGO_BIN_EXE_cadex-memory"))
        .args(["--socket", socket.to_str().unwrap()])
        .args(["--data-dir", dir.join("data").to_str().unwrap()])
        .args(["--no-embeddings", "--no-watcher"])
        .env("HOME", dir)
        .env("CADEX_MEMORY_LOG", "warn")
        .spawn()
        .expect("spawn cadex-memory");
    let engine = Engine { child, socket };
    let deadline = Instant::now() + Duration::from_secs(20);
    while Instant::now() < deadline {
        if request(&engine.socket, "GET", "/healthz", None).is_some_and(|b| b == "ok") {
            return engine;
        }
        std::thread::sleep(Duration::from_millis(50));
    }
    panic!("cadex-memory did not answer on {}", engine.socket.display());
}

/// One HTTP/1.1 request over the Unix socket; the body of a 2xx answer.
fn request(socket: &Path, method: &str, path: &str, body: Option<&str>) -> Option<String> {
    let mut stream = UnixStream::connect(socket).ok()?;
    let body = body.unwrap_or("");
    let head = format!(
        "{method} {path} HTTP/1.1\r\nHost: localhost\r\nContent-Type: application/json\r\n\
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
    if !(200..300).contains(&status) {
        return None;
    }
    if headers.to_ascii_lowercase().contains("transfer-encoding: chunked") {
        return Some(dechunk(payload));
    }
    Some(payload.to_string())
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

fn tool(socket: &Path, name: &str, arguments: serde_json::Value) -> String {
    let call = serde_json::json!({
        "jsonrpc": "2.0", "id": 1, "method": "tools/call",
        "params": {"name": name, "arguments": arguments},
    });
    request(socket, "POST", "/mcp", Some(&call.to_string()))
        .unwrap_or_else(|| panic!("{name} failed"))
}

fn query(pairs: &[(&str, &str)]) -> String {
    pairs
        .iter()
        .map(|(k, v)| format!("{k}={}", v.replace('/', "%2F").replace(' ', "%20")))
        .collect::<Vec<_>>()
        .join("&")
}

#[test]
fn a_session_gets_the_projects_pages_and_search_finds_them() {
    let tmp = tempfile::tempdir().unwrap();
    let project = tmp.path().join("acme");
    std::fs::create_dir_all(&project).unwrap();
    assert!(Command::new("git").args(["init", "-q"]).current_dir(&project).status().unwrap().success());
    let engine = start(tmp.path());

    let page = |path: &str, body: &str| {
        let args = serde_json::json!({
            "workspace": "default", "project": "acme", "path": path, "body": body,
        });
        let out = tool(&engine.socket, "memory_write_page", args);
        assert!(!out.contains("\"isError\":true"), "{path}: {out}");
    };
    page("_rules/style.md", "# Style\n\nIdentifiers are in English; specs are in Portuguese.\n");
    page("decisions/socket.md", "# Engine socket\n\nThe engine listens on a pelican socket.\n");

    let cwd = project.to_str().unwrap();
    let session = "11111111-1111-4111-8111-111111111111";
    let start_event = serde_json::json!({
        "session_id": session, "cwd": cwd, "hook_event_name": "SessionStart",
        "source": "startup", "transcript_path": project.join("t.jsonl"),
    });
    let qs = query(&[("event", "session-start"), ("agent", "claude-code"), ("cwd", cwd),
        ("project_strategy", "repo-root"), ("ingest_key", "smoke1")]);
    request(&engine.socket, "POST", &format!("/hook?{qs}"), Some(&start_event.to_string()))
        .expect("session-start accepted");

    let qs = query(&[("agent", "claude-code"), ("cwd", cwd), ("project_strategy", "repo-root"),
        ("briefing", "1"), ("session_id", session)]);
    let briefing = request(&engine.socket, "GET", &format!("/handoff?{qs}"), None).unwrap_or_default();
    assert!(briefing.contains("Identifiers are in English"), "briefing without the rule: {briefing}");

    let found = tool(&engine.socket, "memory_query", serde_json::json!({
        "query": "pelican", "workspace": "default", "project": "acme", "limit": 5,
    }));
    assert!(found.contains("decisions/socket.md"), "search missed the page: {found}");
}
