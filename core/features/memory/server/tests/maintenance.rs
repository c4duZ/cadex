//! Maintenance on events, never by a clock (plan 22 phase F): upstream's
//! forget sweep removes an expired page and evicts a cold episodic one after
//! a SessionEnd or at the engine's start; a second event within a day does
//! nothing; with no event nothing runs; a SessionStart is answered quickly
//! while the sweep works.

mod common;

use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

use common::{Engine, ok, query, repo, start, tool};

const DAY_US: i64 = 86_400_000_000;
/// Short, so the tests do not wait the default 1.5 s after each event.
const DELAY: &[&str] = &["--keep-alive", "--import-delay-ms", "100"];

fn now_us() -> i64 {
    std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_micros() as i64
}

fn stamp(data: &Path, job: &str) -> PathBuf {
    data.join("maintenance").join(format!("{job}.json"))
}

fn last_run(data: &Path, job: &str) -> Option<i64> {
    let text = std::fs::read_to_string(stamp(data, job)).ok()?;
    serde_json::from_str::<serde_json::Value>(&text).ok()?["last_success_us"].as_i64()
}

/// Make the job's last run look `days` old, so the next event finds it due.
fn age_stamp(data: &Path, job: &str, days: i64) {
    let body = serde_json::json!({"last_success_us": now_us() - days * DAY_US});
    std::fs::write(stamp(data, job), body.to_string()).unwrap();
}

fn wait_for(what: &str, limit: Duration, mut ok: impl FnMut() -> bool) {
    let deadline = Instant::now() + limit;
    while Instant::now() < deadline {
        if ok() {
            return;
        }
        std::thread::sleep(Duration::from_millis(50));
    }
    panic!("timed out waiting for {what}");
}

/// A page's file in the wiki, wherever its scope folder is.
fn page_file(dir: &Path, name: &str) -> Option<PathBuf> {
    for entry in std::fs::read_dir(dir).ok()?.flatten() {
        let path = entry.path();
        if path.is_dir() {
            if let Some(found) = page_file(&path, name) {
                return Some(found);
            }
        } else if path.file_name().is_some_and(|n| n == name) {
            return Some(path);
        }
    }
    None
}

fn exists(data: &Path, name: &str) -> bool {
    page_file(&data.join("wiki"), name).is_some()
}

/// A page whose `expires_at` is past: the sweep's TTL pass hard-deletes it.
fn expired_page(engine: &Engine, name: &str) {
    let out = tool(&engine.socket, "memory_write_page", serde_json::json!({
        "workspace": "default", "project": "acme", "path": format!("notes/{name}"),
        "body": format!("# {name}\n\nA note that expired.\n"), "expires_at": "2020-01-01",
    }));
    assert!(!out.contains("\"isError\":true"), "{name}: {out}");
}

/// An episodic page last updated 200 days ago, never read: its retention
/// (e^(-0.02·200) ≈ 0.02) is under upstream's cold threshold (0.20).
fn cold_page(engine: &Engine, data: &Path, name: &str) {
    let out = tool(&engine.socket, "memory_write_page", serde_json::json!({
        "workspace": "default", "project": "acme", "path": format!("notes/{name}"),
        "body": format!("# {name}\n\nAn old episode.\n"), "tier": "episodic",
    }));
    assert!(!out.contains("\"isError\":true"), "{name}: {out}");
    let db = rusqlite::Connection::open(data.join("db/memory.sqlite")).unwrap();
    db.busy_timeout(Duration::from_secs(5)).unwrap();
    let changed = db
        .execute("UPDATE pages SET updated_at = ?1 WHERE path = ?2 AND is_latest = 1",
            rusqlite::params![now_us() - 200 * DAY_US, format!("notes/{name}")])
        .unwrap();
    assert_eq!(changed, 1, "the cold page's row");
}

fn session(socket: &Path, cwd: &str, id: &str, event: &str) {
    let qs = query(&[("event", event), ("agent", "claude-code"), ("cwd", cwd), ("session_id", id),
        ("project_strategy", "repo-root"), ("ingest_key", &format!("{id}-{event}"))]);
    let body = serde_json::json!({"session_id": id, "cwd": cwd, "source": "startup"});
    ok(socket, "POST", &format!("/hook?{qs}"), Some(&body.to_string())).unwrap_or_else(|| panic!("{event} refused"));
}

/// The engine up and its start's run done (the stamps written).
fn started(dir: &Path) -> (Engine, PathBuf) {
    let engine = start(dir, DELAY);
    let data = dir.join("data");
    wait_for("the start's maintenance", Duration::from_secs(20), || {
        ["forget-sweep", "rule-lint", "hollow-projects"].iter().all(|j| last_run(&data, j).is_some())
    });
    (engine, data)
}

#[test]
fn a_session_end_sweeps_and_a_second_one_within_a_day_does_not() {
    let tmp = tempfile::tempdir().unwrap();
    let project = repo(tmp.path(), "acme");
    let cwd = project.to_str().unwrap();
    let (engine, data) = started(tmp.path());
    expired_page(&engine, "expired.md");
    cold_page(&engine, &data, "cold.md");
    assert!(exists(&data, "expired.md") && exists(&data, "cold.md"));
    age_stamp(&data, "forget-sweep", 2);

    session(&engine.socket, cwd, "77777777-7777-4777-8777-777777777777", "session-start");
    session(&engine.socket, cwd, "77777777-7777-4777-8777-777777777777", "session-end");
    wait_for("the expired and the cold page swept", Duration::from_secs(20), || {
        !exists(&data, "expired.md") && !exists(&data, "cold.md")
    });
    let swept_at = last_run(&data, "forget-sweep").unwrap();
    assert!(now_us() - swept_at < DAY_US, "the stamp moved to now");

    expired_page(&engine, "later.md");
    session(&engine.socket, cwd, "88888888-8888-4888-8888-888888888888", "session-start");
    session(&engine.socket, cwd, "88888888-8888-4888-8888-888888888888", "session-end");
    std::thread::sleep(Duration::from_secs(2));
    assert!(exists(&data, "later.md"), "a second SessionEnd within a day swept again");
    assert_eq!(last_run(&data, "forget-sweep"), Some(swept_at));
}

#[test]
fn the_engines_start_sweeps_what_is_due() {
    let tmp = tempfile::tempdir().unwrap();
    repo(tmp.path(), "acme");
    let (first, data) = started(tmp.path());
    expired_page(&first, "expired.md");
    drop(first);
    age_stamp(&data, "forget-sweep", 2);

    let _second = start(tmp.path(), DELAY);
    wait_for("the expired page swept at start", Duration::from_secs(20), || !exists(&data, "expired.md"));
}

#[test]
fn with_no_event_nothing_runs() {
    let tmp = tempfile::tempdir().unwrap();
    repo(tmp.path(), "acme");
    let (engine, data) = started(tmp.path());
    expired_page(&engine, "expired.md");
    for job in ["forget-sweep", "rule-lint", "hollow-projects"] {
        age_stamp(&data, job, 30);
    }
    let before = last_run(&data, "forget-sweep");
    std::thread::sleep(Duration::from_secs(3));
    assert!(exists(&data, "expired.md"), "the sweep ran with no event");
    assert_eq!(last_run(&data, "forget-sweep"), before);
}

#[test]
fn a_session_start_is_answered_quickly_while_the_sweep_runs() {
    let tmp = tempfile::tempdir().unwrap();
    let project = repo(tmp.path(), "acme");
    let cwd = project.to_str().unwrap();
    let (engine, data) = started(tmp.path());
    let names: Vec<String> = (0..60).map(|i| format!("expired-{i}.md")).collect();
    for name in &names {
        expired_page(&engine, name);
    }
    age_stamp(&data, "forget-sweep", 2);
    session(&engine.socket, cwd, "99999999-9999-4999-8999-999999999999", "session-end");

    let mut slowest = Duration::ZERO;
    let mut during = 0;
    let deadline = Instant::now() + Duration::from_secs(60);
    for n in 0.. {
        let left = names.iter().filter(|name| exists(&data, name)).count();
        if left == 0 || Instant::now() > deadline {
            break;
        }
        let id = format!("aaaaaaaa-aaaa-4aaa-8aaa-{n:012}");
        let asked = Instant::now();
        session(&engine.socket, cwd, &id, "session-start");
        let qs = query(&[("agent", "claude-code"), ("cwd", cwd), ("project_strategy", "repo-root"), ("briefing", "1"), ("session_id", &id)]);
        ok(&engine.socket, "GET", &format!("/handoff?{qs}"), None).expect("briefing");
        slowest = slowest.max(asked.elapsed());
        if left < names.len() {
            during += 1;
        }
    }
    assert!(names.iter().all(|name| !exists(&data, name)), "the sweep did not finish");
    // The hook gives the SessionStart and its briefing 1 s together.
    assert!(slowest < Duration::from_secs(1), "a SessionStart took {slowest:?} while the sweep ran");
    eprintln!("session starts answered while the sweep ran: {during}, slowest {slowest:?}");
}
