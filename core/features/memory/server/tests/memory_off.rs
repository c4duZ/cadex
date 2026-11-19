//! The memory turned off (plan 35 I): in a project (`off-projects.json`,
//! written by the app) its sessions' events are taken and never stored, no
//! agent job runs, its pages leave the other projects' global search and a
//! call naming it is refused; in a paused session (`paused/<id>`) nothing
//! after the pause is stored and its end calls nothing. Turned back on,
//! what was recorded before is still there.

mod common;

use std::path::Path;
use std::time::Duration;

use common::agent::{ARGS, fake_claude, hook, ledger, work};
use common::{repo, start_with_env, tool};

const S1: &str = "a3a3a3a3-0000-4000-8000-000000000001";
const S2: &str = "a3a3a3a3-0000-4000-8000-000000000002";
const S3: &str = "a3a3a3a3-0000-4000-8000-000000000003";

fn turn_off(data: &Path, roots: &[&Path]) {
    std::fs::write(data.join("off-projects.json"), serde_json::json!({"roots": roots}).to_string()).unwrap();
}

fn prompt(socket: &Path, cwd: &str, id: &str, words: &str) {
    hook(socket, "user-prompt-submit", cwd, id, &format!("{id}-{words}"),
         serde_json::json!({"session_id": id, "cwd": cwd, "hook_event_name": "UserPromptSubmit", "prompt": words}));
}

fn end(socket: &Path, cwd: &str, id: &str) {
    hook(socket, "session-end", cwd, id, &format!("{id}-e"),
         serde_json::json!({"session_id": id, "cwd": cwd, "hook_event_name": "SessionEnd", "reason": "exit"}));
}

fn observations(socket: &Path, id: &str, project: &str) -> String {
    tool(socket, "memory_read_session_observations", serde_json::json!({
        "session_id": id, "workspace": "default", "project": project, "limit": 100}))
}

/// The projects of a global query's hits.
fn global_projects(socket: &Path, words: &str) -> Vec<String> {
    let out: serde_json::Value = serde_json::from_str(&tool(socket, "memory_query", serde_json::json!({"query": words, "global": true}))).unwrap();
    let text = out.pointer("/result/content/0/text").and_then(|t| t.as_str()).unwrap_or("{}");
    let inner: serde_json::Value = serde_json::from_str(text).unwrap_or_default();
    let hits = inner["global_hits"].as_array().cloned().unwrap_or_default();
    hits.iter().filter_map(|h| h["project_name"].as_str().map(str::to_owned)).collect()
}

#[test]
fn an_off_project_records_nothing_runs_nothing_and_leaves_the_global_search() {
    let tmp = tempfile::tempdir().unwrap();
    let acme = repo(tmp.path(), "acme");
    let other = repo(tmp.path(), "other");
    let (cwd, other_cwd) = (acme.to_str().unwrap(), other.to_str().unwrap());
    let fake = fake_claude(tmp.path());
    let data = tmp.path().join("data");
    fake.configure(&data, serde_json::json!({"enabled": true}));
    let engine = start_with_env(tmp.path(), ARGS, &[]);
    let s = &engine.socket;
    // Both projects known, each with a page about the lighthouse, while on.
    work(s, cwd, S1, 1, None);
    for (dir, project) in [(other_cwd, "other"), (cwd, "acme")] {
        hook(s, "session-start", dir, S3, &format!("{project}-s"), serde_json::json!({"session_id": S3, "cwd": dir, "source": "startup"}));
        std::thread::sleep(Duration::from_millis(300));
        tool(s, "memory_write_page", serde_json::json!({"workspace": "default", "project": project,
            "path": "concepts/lighthouse.md", "body": "# Lighthouse\n\nThe lighthouse keeper.\n", "kind": "concept"}));
    }
    let mut both = global_projects(s, "lighthouse");
    both.sort();
    assert_eq!(both, ["acme", "other"]);

    turn_off(&data, &[&acme]);
    assert_eq!(global_projects(s, "lighthouse"), ["other"], "an off project leaves the others' search");
    let named = tool(s, "memory_query", serde_json::json!({"query": "lighthouse", "workspace": "default", "project": "acme"}));
    assert!(named.contains("memory is off") && named.contains("\"isError\":true"), "{named}");

    hook(s, "session-start", &format!("{cwd}/src"), S2, "s2-s", serde_json::json!({"session_id": S2, "cwd": cwd, "source": "startup"}));
    prompt(s, cwd, S2, "the walrus migration");
    end(s, cwd, S2);
    std::thread::sleep(Duration::from_millis(1500));
    assert!(fake.calls().is_empty(), "claude ran for an off project");
    assert!(ledger(&data).iter().all(|l| l["session"] != S2), "no job for an off project");

    turn_off(&data, &[]);
    assert!(!observations(s, S2, "acme").contains("walrus"), "nothing stored while off");
    assert!(observations(s, S1, "acme").contains("WAL lock"), "what was recorded before stays");
}

#[test]
fn a_paused_session_stops_recording_and_its_end_calls_nothing() {
    let tmp = tempfile::tempdir().unwrap();
    let acme = repo(tmp.path(), "acme");
    let cwd = acme.to_str().unwrap();
    let fake = fake_claude(tmp.path());
    let data = tmp.path().join("data");
    fake.configure(&data, serde_json::json!({"enabled": true}));
    let engine = start_with_env(tmp.path(), ARGS, &[]);
    let s = &engine.socket;
    work(s, cwd, S1, 1, None);
    std::fs::create_dir_all(data.join("paused")).unwrap();
    std::fs::write(data.join("paused").join(S1), "").unwrap();
    prompt(s, cwd, S1, "the narwhal secret");
    end(s, cwd, S1);
    std::thread::sleep(Duration::from_millis(1500));
    let seen = observations(s, S1, "acme");
    assert!(seen.contains("WAL lock"), "the pause deletes nothing");
    assert!(!seen.contains("narwhal"), "nothing after the pause");
    assert!(fake.calls().is_empty(), "a paused session's end called claude");
    assert!(ledger(&data).iter().all(|l| l["session"] != S1));
}
