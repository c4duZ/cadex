//! The process around the engine (plan 22, phase C): who may talk to the
//! socket, the replay of the hook queue at start, and the exit when the
//! last `claude` ends, whether it registered by SessionStart or was handed
//! over by a restart (`--sessions`).

mod common;

use std::os::unix::fs::FileTypeExt;
use std::process::Command;
use std::time::{Duration, Instant};

use common::{ok, query, repo, request, start, tool};

/// The engine's linger after the last session (sessions.rs), plus slack for
/// a loaded machine.
const EXIT_LIMIT: Duration = Duration::from_secs(6);

fn fake_claude() -> std::process::Child {
    Command::new("/bin/sleep").arg("60").spawn().unwrap()
}

#[test]
fn the_socket_wants_a_session_token_except_for_health() {
    let tmp = tempfile::tempdir().unwrap();
    let engine = start(tmp.path(), &["--keep-alive"]);
    let s = &engine.socket;
    let hook = "/hook?event=stop&agent=claude-code";
    assert_eq!(request(s, "POST", hook, Some("{}"), None).map(|r| r.0), Some(401));
    assert_eq!(request(s, "POST", hook, Some("{}"), Some(&"f".repeat(64))).map(|r| r.0), Some(401));
    assert_eq!(request(s, "POST", "/mcp", Some("{}"), Some("short")).map(|r| r.0), Some(401));
    assert_eq!(request(s, "GET", "/healthz", None, None).map(|r| r.0), Some(200));
    // A session opened after the engine started: its token file is new.
    let late = "9".repeat(64);
    std::fs::write(tmp.path().join("sessions/kit-late.token"), &late).unwrap();
    let status = request(s, "POST", hook, Some("{}"), Some(&late)).map(|r| r.0).unwrap();
    assert!((200..300).contains(&status), "late token refused: {status}");
}

#[test]
fn queued_hook_events_are_replayed_at_start() {
    let tmp = tempfile::tempdir().unwrap();
    let project = repo(tmp.path(), "spooled");
    let cwd = project.to_str().unwrap();
    let session = "22222222-2222-4222-8222-222222222222";
    let spool = tmp.path().join("data/spool");
    std::fs::create_dir_all(&spool).unwrap();
    let queue = |name: &str, event: &str, body: serde_json::Value| {
        let path = format!("/hook?{}", query(&[("event", event), ("agent", "claude-code"), ("cwd", cwd),
            ("session_id", session), ("project_strategy", "repo-root"), ("ingest_key", name)]));
        let file = serde_json::json!({"v": 1, "path": path, "body": body.to_string()});
        std::fs::write(spool.join(format!("{name}.json")), file.to_string()).unwrap();
    };
    queue("0000000000001-a", "session-start", serde_json::json!({
        "session_id": session, "cwd": cwd, "hook_event_name": "SessionStart", "source": "startup",
    }));
    queue("0000000000002-b", "user-prompt-submit", serde_json::json!({
        "session_id": session, "cwd": cwd, "hook_event_name": "UserPromptSubmit",
        "prompt": "rename the albatross module",
    }));
    std::fs::write(spool.join("0000000000003-c.json"), "{\"v\":1,\"path\":\"/elsewhere\"}").unwrap();

    let engine = start(tmp.path(), &["--keep-alive"]);
    let deadline = Instant::now() + Duration::from_secs(10);
    let left = || std::fs::read_dir(&spool).unwrap().flatten()
        .filter(|e| e.path().extension().is_some_and(|x| x == "json")).count();
    while left() > 0 && Instant::now() < deadline {
        std::thread::sleep(Duration::from_millis(50));
    }
    assert_eq!(left(), 0, "the queue was not drained");
    assert!(spool.join("0000000000003-c.rejected").exists(), "a bad entry is set aside, not lost");

    let recent = tool(&engine.socket, "memory_read_session_observations", serde_json::json!({
        "session_id": session, "workspace": "default", "project": "spooled",
    }));
    assert!(recent.contains("albatross"), "the queued prompt did not land: {recent}");
}

#[test]
fn the_engine_leaves_when_its_last_session_ends() {
    let tmp = tempfile::tempdir().unwrap();
    let project = repo(tmp.path(), "leaving");
    let mut engine = start(tmp.path(), &[]);
    let mut claude = fake_claude();
    let cwd = project.to_str().unwrap();
    let qs = query(&[("event", "session-start"), ("agent", "claude-code"), ("cwd", cwd),
        ("project_strategy", "repo-root"), ("ingest_key", "leave1"), ("pid", &claude.id().to_string())]);
    let body = serde_json::json!({"session_id": "33333333-3333-4333-8333-333333333333", "cwd": cwd});
    ok(&engine.socket, "POST", &format!("/hook?{qs}"), Some(&body.to_string())).expect("session-start");
    assert!(!engine.exits_within(Duration::from_millis(500)), "left with a session alive");
    claude.kill().unwrap();
    claude.wait().unwrap();
    assert!(engine.exits_within(EXIT_LIMIT), "still running after its last session ended");
    assert!(!engine.socket.exists(), "the socket file stayed behind");
}

#[test]
fn sessions_handed_over_by_a_restart_keep_the_engine_alive_until_they_end() {
    let tmp = tempfile::tempdir().unwrap();
    let mut claude = fake_claude();
    let pid = claude.id().to_string();
    // A pid that is already gone counts as ended, not as alive.
    let mut engine = start(tmp.path(), &["--sessions", &format!("{pid},999999")]);
    assert!(!engine.exits_within(Duration::from_millis(500)));
    claude.kill().unwrap();
    claude.wait().unwrap();
    // Without the handed-over session the startup grace (10 s) would apply.
    assert!(engine.exits_within(EXIT_LIMIT), "the handed-over session was not tracked");
}

#[test]
fn a_warm_up_migrates_the_store_and_leaves_without_a_socket() {
    let tmp = tempfile::tempdir().unwrap();
    let data = tmp.path().join("data");
    let mut child = Command::new(env!("CARGO_BIN_EXE_cadex-memory"))
        .args(["--warm", "--no-embeddings", "--data-dir", data.to_str().unwrap()])
        .env("HOME", tmp.path())
        .env("CADEX_MEMORY_LOG", "warn")
        .spawn()
        .expect("spawn cadex-memory --warm");
    // Debug build on a loaded machine; the release one takes well under a second.
    let deadline = Instant::now() + Duration::from_secs(20);
    let status = loop {
        if let Some(status) = child.try_wait().unwrap() {
            break status;
        }
        if Instant::now() > deadline {
            let _ = child.kill();
            panic!("the warm-up did not leave");
        }
        std::thread::sleep(Duration::from_millis(50));
    };
    assert!(status.success(), "warm-up failed: {status}");
    assert!(data.join("db/memory.sqlite").is_file(), "no store after the warm-up");
    assert!(data.join("wiki").is_dir(), "no wiki after the warm-up");
    let sockets: Vec<_> = std::fs::read_dir(&data).unwrap().flatten()
        .filter(|e| e.file_type().is_ok_and(|t| t.is_socket())).collect();
    assert!(sockets.is_empty(), "a warm-up bound a socket");
}
