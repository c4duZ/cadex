//! Past and outside sessions learned from transcripts (plan 22, phase C):
//! synthetic Claude Code transcripts in fake account folders under a
//! temporary HOME, never the owner's.

mod common;

use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::{Duration, Instant, SystemTime};

use common::{Engine, ok, query, repo, start, tool};

const S_START: &str = "00000000-0000-4000-8000-000000000001";
const S_ROOT: &str = "00000000-0000-4000-8000-0000000000a1";
const S_SUB: &str = "00000000-0000-4000-8000-0000000000a2";
const S_TREE: &str = "00000000-0000-4000-8000-0000000000b1";
const S_ELSE: &str = "00000000-0000-4000-8000-0000000000c1";
const S_LATE: &str = "00000000-0000-4000-8000-0000000000d1";

/// A Claude Code transcript in `account`, as Claude Code writes one: a user
/// prompt holding `word`, an assistant reply with a tool call, its result.
fn transcript(account: &Path, id: &str, cwd: &Path, word: &str, age: Duration) -> PathBuf {
    let folder: String = cwd.to_string_lossy().chars().map(|c| if c.is_ascii_alphanumeric() { c } else { '-' }).collect();
    let dir = account.join("projects").join(folder);
    std::fs::create_dir_all(&dir).unwrap();
    let record = |uuid: &str, role: &str, content: serde_json::Value| serde_json::json!({
        "type": role, "uuid": uuid, "sessionId": id, "cwd": cwd, "timestamp": "2026-09-01T10:00:00Z",
        "message": {"role": role, "content": content},
    }).to_string();
    let lines = [
        record("u1", "user", serde_json::json!(format!("please look at the {word} module"))),
        record("a1", "assistant", serde_json::json!([
            {"type": "text", "text": "reading it"},
            {"type": "tool_use", "id": "toolu_1", "name": "Read", "input": {"file_path": cwd.join("lib.rs")}},
        ])),
        record("u2", "user", serde_json::json!([{"type": "tool_result", "tool_use_id": "toolu_1", "content": "fn main() {}"}])),
    ];
    let path = dir.join(format!("{id}.jsonl"));
    std::fs::write(&path, lines.join("\n") + "\n").unwrap();
    let file = std::fs::File::options().write(true).open(&path).unwrap();
    file.set_modified(SystemTime::now() - age).unwrap();
    path
}

fn account(home: &Path, name: &str) -> PathBuf {
    let dir = home.join(name);
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::write(dir.join(".claude.json"), "{}").unwrap();
    dir
}

fn git(dir: &Path, args: &[&str]) {
    assert!(Command::new("git").arg("-C").arg(dir).args(args).output().unwrap().status.success(), "git {args:?}");
}

fn session_start(engine: &Engine, id: &str, cwd: &Path, workspace: Option<&str>) {
    let cwd = cwd.to_str().unwrap();
    let mut pairs = vec![("event", "session-start"), ("agent", "claude-code"), ("cwd", cwd)];
    pairs.extend(workspace.map(|w| ("workspace", w)));
    pairs.extend([("session_id", id), ("project_strategy", "repo-root"), ("ingest_key", id)]);
    let body = serde_json::json!({"session_id": id, "cwd": cwd, "hook_event_name": "SessionStart", "source": "startup"});
    ok(&engine.socket, "POST", &format!("/hook?{}", query(&pairs)), Some(&body.to_string())).expect("session-start");
}

fn observations(engine: &Engine, id: &str, workspace: &str) -> String {
    tool(&engine.socket, "memory_read_session_observations", serde_json::json!({
        "session_id": id, "workspace": workspace, "project": "acme",
    }))
}

/// Wait until `path` holds something other than `before`.
fn wait_for_change(path: &Path, before: Option<&str>) -> String {
    let deadline = Instant::now() + Duration::from_secs(20);
    loop {
        let now = std::fs::read_to_string(path).ok();
        if let Some(text) = now.filter(|t| Some(t.as_str()) != before && !t.trim().is_empty() && t.trim() != "started") {
            return text;
        }
        assert!(Instant::now() < deadline, "{} never changed", path.display());
        std::thread::sleep(Duration::from_millis(50));
    }
}

fn backfill_marker(data: &Path) -> PathBuf {
    let deadline = Instant::now() + Duration::from_secs(20);
    loop {
        let found = std::fs::read_dir(data.join("imports")).ok().and_then(|d| {
            d.flatten().map(|e| e.path()).find(|p| p.file_name().unwrap().to_str().unwrap().starts_with("backfill-"))
        });
        if let Some(path) = found {
            return path;
        }
        assert!(Instant::now() < deadline, "no backfill marker");
        std::thread::sleep(Duration::from_millis(50));
    }
}

#[test]
fn the_first_session_learns_the_projects_history_from_every_account_once() {
    let tmp = tempfile::tempdir().unwrap();
    let project = repo(tmp.path(), "acme");
    git(&project, &["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", "x"]);
    let tree = tmp.path().join("acme-task");
    git(&project, &["worktree", "add", "-q", tree.to_str().unwrap()]);
    std::fs::create_dir_all(project.join("src")).unwrap();
    let elsewhere = tmp.path().join("acme2");
    std::fs::create_dir_all(&elsewhere).unwrap();
    let day = Duration::from_secs(86_400);
    let main = account(tmp.path(), ".claude");
    let second = account(tmp.path(), ".claude-two");
    transcript(&main, S_ROOT, &project, "alpaca", day * 3);
    transcript(&main, S_SUB, &project.join("src"), "bison", day * 2);
    transcript(&second, S_TREE, &tree, "condor", day);
    transcript(&second, S_ROOT, &project, "alpaca", day * 4);
    transcript(&main, S_ELSE, &elsewhere, "dingo", day);
    transcript(&main, S_START, &project, "eagle", Duration::ZERO);

    let engine = start(tmp.path(), &["--keep-alive", "--import-delay-ms", "0"]);
    session_start(&engine, S_START, &project, None);
    let marker = backfill_marker(&tmp.path().join("data"));
    assert_eq!(wait_for_change(&marker, None).trim(), "done");
    assert!(observations(&engine, S_ROOT, "default").contains("alpaca"), "the root's session");
    assert!(observations(&engine, S_SUB, "default").contains("bison"), "a subfolder's session");
    assert!(observations(&engine, S_TREE, "default").contains("condor"), "a worktree's, from the other account");
    assert!(!observations(&engine, S_ELSE, "default").contains("dingo"), "a folder beside the repo is another project");
    assert!(!observations(&engine, S_START, "default").contains("eagle"), "the starting session is not imported");
    // Posted oldest first: the briefing's recent pages put the newest on top.
    let qs = query(&[("agent", "claude-code"), ("cwd", project.to_str().unwrap()), ("project_strategy", "repo-root"),
        ("briefing", "1"), ("session_id", S_START)]);
    let briefing = ok(&engine.socket, "GET", &format!("/handoff?{qs}"), None).unwrap_or_default();
    let at = |word: &str| briefing.find(word).unwrap_or_else(|| panic!("{word} not in the briefing: {briefing}"));
    assert!(at("condor") < at("bison") && at("bison") < at("alpaca"), "{briefing}");

    // Once: a later first-of-its-kind session finds the marker.
    transcript(&main, S_LATE, &project, "falcon", day);
    session_start(&engine, "00000000-0000-4000-8000-000000000002", &project, None);
    std::thread::sleep(Duration::from_millis(1500));
    assert!(!observations(&engine, S_LATE, "default").contains("falcon"), "the history is imported once");
}

#[test]
fn an_accounts_own_memory_reads_only_that_account() {
    let tmp = tempfile::tempdir().unwrap();
    let project = repo(tmp.path(), "acme");
    let (one, two) = (tmp.path().join("acct-one"), tmp.path().join("acct-two"));
    let day = Duration::from_secs(86_400);
    transcript(&one, S_ROOT, &project, "alpaca", day);
    transcript(&two, S_TREE, &project, "condor", day);
    let dirs = format!("{}:{}", one.display(), two.display());
    let engine = start(tmp.path(), &["--keep-alive", "--import-delay-ms", "0", "--claude-dirs", &dirs]);
    let key: String = two.to_string_lossy().bytes().map(|b| if b.is_ascii_alphanumeric() { b as char } else { '-' }).collect();
    session_start(&engine, S_START, &project, Some(&key));
    assert_eq!(wait_for_change(&backfill_marker(&tmp.path().join("data")), None).trim(), "done");
    assert!(observations(&engine, S_TREE, &key).contains("condor"), "its own account");
    assert!(!observations(&engine, S_ROOT, &key).contains("alpaca"), "not the other account");
}

#[test]
fn each_start_learns_the_outside_sessions_since_the_last_one() {
    let tmp = tempfile::tempdir().unwrap();
    let project = repo(tmp.path(), "acme");
    let main = account(tmp.path(), ".claude");
    let data = tmp.path().join("data");
    let checkpoints = data.join("imports/outside.json");
    let args = ["--keep-alive", "--import-delay-ms", "0"];
    {
        // A Cadex session makes the project known.
        let engine = start(tmp.path(), &args);
        session_start(&engine, S_START, &project, None);
        wait_for_change(&backfill_marker(&data), None);
    }
    // As if the engine last ran before these sessions.
    std::fs::remove_file(&checkpoints).ok();
    let day = Duration::from_secs(86_400);
    transcript(&main, S_ROOT, &project, "heron", day);
    transcript(&main, S_TREE, &project, "raven", Duration::ZERO);
    transcript(&main, S_START, &project, "puffin", day);

    let before = {
        let engine = start(tmp.path(), &args);
        let text = wait_for_change(&checkpoints, None);
        assert!(observations(&engine, S_ROOT, "default").contains("heron"), "an outside session");
        assert!(!observations(&engine, S_TREE, "default").contains("raven"), "one maybe still open waits");
        assert!(!observations(&engine, S_START, "default").contains("puffin"), "a session the store has");
        text
    };
    // Older than the checkpoint: the next start does not read it.
    transcript(&main, S_LATE, &project, "quail", day * 2);
    let engine = start(tmp.path(), &args);
    wait_for_change(&checkpoints, Some(&before));
    assert!(!observations(&engine, S_LATE, "default").contains("quail"), "the checkpoint bounds the scan");
}
