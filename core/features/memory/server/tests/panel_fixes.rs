//! Plan 40 G (docs/plans/40-memory-panel.md): the Saúde screen's fixes
//! (`extra/fix`, src/page/panel/fixes.rs) and the review's rejection with the
//! owner's reason, through the engine over the A2 seed.
//!
//! - `spool`: an event the hook left after the engine started is sent now,
//!   and the health check that counted it goes quiet.
//! - `embed` and `embed-all` without the local model: upstream's 503.
//! - `compact`: the store rebuilt, its sizes reported, every project still read.
//! - A rejection with its reason and an approval through the panel's routes;
//!   the review lists each one fewer.

mod common;
mod panel;

use serde_json::{Value, json};

use common::{TOKEN, query, repo, request, start};
use panel::PANEL;
use panel::seed;

const ARGS: &[&str] = &["--keep-alive", "--import-delay-ms", "600000"];

fn post(socket: &std::path::Path, path: &str, body: &Value) -> (u16, Value) {
    let (status, text) = request(socket, "POST", path, Some(&body.to_string()), Some(TOKEN)).expect("the engine answers");
    (status, serde_json::from_str(&text).unwrap_or(Value::String(text)))
}

fn get(socket: &std::path::Path, path: &str) -> Value {
    let (status, text) = request(socket, "GET", path, None, Some(TOKEN)).expect("the engine answers");
    assert_eq!(status, 200, "GET {path}: {text}");
    serde_json::from_str(&text).unwrap()
}

#[tokio::test]
async fn the_fixes_and_a_reasoned_rejection() {
    let tmp = tempfile::tempdir().unwrap();
    seed::seed(&tmp.path().join("data")).await.expect("seed");
    let mut engine = start(tmp.path(), ARGS);
    let socket = engine.socket.clone();
    let fix = format!("{PANEL}/extra/fix");

    // A hook event spooled while the engine was busy, after its start-up drain.
    let project = repo(tmp.path(), "spooled");
    let cwd = project.to_str().unwrap();
    let session = "33333333-3333-4333-8333-333333333333";
    let spool = tmp.path().join("data/spool");
    std::fs::create_dir_all(&spool).unwrap();
    let path = format!("/hook?{}", query(&[("event", "session-start"), ("agent", "claude-code"), ("cwd", cwd),
        ("session_id", session), ("project_strategy", "repo-root"), ("ingest_key", "fix-1")]));
    let body = json!({"session_id": session, "cwd": cwd, "hook_event_name": "SessionStart", "source": "startup"});
    std::fs::write(spool.join("0000000000001-a.json"), json!({"v": 1, "path": path, "body": body.to_string()}).to_string()).unwrap();
    assert_eq!(get(&socket, &format!("{PANEL}/extra/health"))["spool"]["pending"], 1);
    assert_eq!(post(&socket, &fix, &json!({"what": "spool"})), (200, json!({"delivered": 1, "pending": 0})));
    assert_eq!(get(&socket, &format!("{PANEL}/extra/health"))["spool"]["pending"], 0);

    for what in ["embed", "embed-all"] {
        assert_eq!(post(&socket, &fix, &json!({"what": what})), (503, json!({"error": "embedder not configured on server"})), "{what}");
    }
    assert_eq!(post(&socket, &fix, &json!({"what": "vacuum"})).0, 400);

    let (status, compacted) = post(&socket, &fix, &json!({"what": "compact"}));
    assert_eq!(status, 200, "{compacted}");
    assert!(compacted["bytes_before"].as_u64().unwrap() > 0 && compacted["bytes_after"].as_u64().is_some(), "{compacted}");
    let projects = get(&socket, &format!("{PANEL}/api/v1/projects"));
    assert!(projects.as_array().unwrap().iter().any(|p| p["project_name"] == "cadex"), "the store reads after compacting");

    let review = get(&socket, &format!("{PANEL}/extra/review"));
    let before = review["proposals"].as_array().unwrap().len();
    let id = review["proposals"][0]["id"].as_str().unwrap().to_owned();
    let reject = format!("{PANEL}/extra/review/reject");
    let (status, answer) = post(&socket, &reject, &json!({"id": id, "reason": "Not now, the rule is too broad"}));
    assert_eq!(status, 200, "{answer}");
    let after = get(&socket, &format!("{PANEL}/extra/review"));
    assert_eq!(after["proposals"].as_array().unwrap().len(), before - 1);
    assert_eq!(post(&socket, &reject, &json!({"id": id})).0, 404, "decided already");
    let next = after["proposals"][0]["id"].as_str().unwrap().to_owned();
    let (status, answer) = post(&socket, &format!("{PANEL}/extra/review/approve"), &json!({"id": next}));
    assert_eq!(status, 200, "{answer}");
    assert_eq!(get(&socket, &format!("{PANEL}/extra/review"))["proposals"].as_array().unwrap().len(), before - 2);
    engine.stop();
}
