//! The auto-improve guardrails of plan 35 phase G (the bkdg-center case,
//! 2026-11-18: the imported history was reviewed oldest first, and a session
//! that worked in another folder became four approved pages about a system
//! the Center does not have, filed in the ledger under the session that
//! ended): imported sessions are never reviewed on their own; a proposal
//! citing only paths the repository lacks is refused with a ledger line while
//! one citing a file it has is staged; the auto-improve line names the
//! reviewed session, with the ending one as `trigger`.

mod common;

use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime};

use common::agent::{ARGS, COST, end, fake_claude, ledger, wait_for, work};
use common::{ok, repo, start_with_env};

const S1: &str = "a2a2a2a2-0000-4000-8000-000000000001";
const S2: &str = "a2a2a2a2-0000-4000-8000-000000000002";
const S3: &str = "a2a2a2a2-0000-4000-8000-000000000003";
const H1: &str = "a2a2a2a2-0000-4000-8000-0000000000e1";
const H2: &str = "a2a2a2a2-0000-4000-8000-0000000000e2";

fn status(socket: &Path) -> serde_json::Value {
    serde_json::from_str(&ok(socket, "GET", "/cadex/agent/status", None).expect("status")).unwrap()
}

fn idle(socket: &Path) -> bool {
    status(socket)["queue"].as_array().is_some_and(Vec::is_empty)
}

fn proposal(path: &str, body: &str) -> serde_json::Value {
    serde_json::json!({
        "operation": "create_or_update", "path": path, "title": "A lesson", "kind": "gotcha", "confidence": 0.9,
        "rationale": "The session hit it twice.", "evidence": [{"page": "observations", "quote": "the WAL lock"}],
        "body_markdown": body, "edit_mode": "full_page",
    })
}

#[test]
fn a_proposal_citing_only_missing_paths_is_refused_and_the_line_names_the_reviewed_session() {
    let tmp = tempfile::tempdir().unwrap();
    let project = repo(tmp.path(), "acme");
    std::fs::create_dir_all(project.join("src")).unwrap();
    std::fs::write(project.join("src/cache.rs"), "fn main() {}\n").unwrap();
    let cwd = project.to_str().unwrap();
    let fake = fake_claude(tmp.path());
    fake.answer("AutoImproveLlmResponse", serde_json::json!({
        "summary": "two lessons",
        "proposals": [
            proposal("gotchas/competencias.md", "# Ciclo\n\nThe cycle lives in `app/competencias/ciclo.rb` and app/models/avaliacao.rb.\n"),
            proposal("gotchas/wal-lock.md", "# WAL lock\n\nCheckpoint the WAL in `src/cache.rs` before copying.\n"),
        ],
        "rejected_candidates": [],
    }));
    let data = tmp.path().join("data");
    fake.configure(&data, serde_json::json!({"enabled": true, "require_approval": true}));
    let engine = start_with_env(tmp.path(), ARGS, &[]);
    let s = &engine.socket;
    // The project's first job sets the watermark at this session's end.
    work(s, cwd, S1, 2, Some(1_000));
    end(s, cwd, S1, Some(900));
    wait_for("the first job", Duration::from_secs(20), || ledger(&data).iter().any(|l| l["session"] == S1) && idle(s));
    // A long session whose end runs no job (the agent off), then a short one
    // whose job reviews it: the review is S2's, set off by S3.
    fake.configure(&data, serde_json::json!({"enabled": false, "require_approval": true}));
    work(s, cwd, S2, 10, Some(300));
    end(s, cwd, S2, None);
    std::thread::sleep(Duration::from_millis(1500));
    fake.configure(&data, serde_json::json!({"enabled": true, "require_approval": true}));
    work(s, cwd, S3, 1, None);
    end(s, cwd, S3, None);
    wait_for("the review", Duration::from_secs(30), || {
        ledger(&data).iter().any(|l| l["kind"] == "auto-improve" && l["cost_usd"].as_f64() == Some(COST)) && idle(s)
    });

    let lines = ledger(&data);
    let review = lines.iter().find(|l| l["kind"] == "auto-improve" && l["cost_usd"].as_f64() == Some(COST)).unwrap();
    assert_eq!((review["session"].as_str(), review["trigger"].as_str()), (Some(S2), Some(S3)), "{review}");
    let refused = lines.iter().find(|l| l["error"].as_str().is_some_and(|e| e.starts_with("refused"))).expect("a refusal line");
    let why = refused["error"].as_str().unwrap();
    assert!(why.contains("gotchas/competencias.md") && why.contains("app/competencias/ciclo.rb"), "{why}");
    assert!(!why.contains("wal-lock"), "{why}");
    assert_eq!((refused["session"].as_str(), refused["trigger"].as_str()), (Some(S2), Some(S3)), "{refused}");
    assert_eq!(refused["cost_usd"].as_f64(), Some(0.0));
    assert_eq!(status(s)["proposals_pending"].as_u64(), Some(1), "only the proposal citing src/cache.rs is staged");
}

/// A Claude Code transcript long enough for upstream's preflight (8
/// observations, 120 s): a prompt and ten reads 30 s apart, ending
/// `ended_ago` seconds back.
fn long_transcript(account: &Path, id: &str, cwd: &Path, ended_ago: i64) -> PathBuf {
    let folder: String = cwd.to_string_lossy().chars().map(|c| if c.is_ascii_alphanumeric() { c } else { '-' }).collect();
    let dir = account.join("projects").join(folder);
    std::fs::create_dir_all(&dir).unwrap();
    let at = |step: i64| common::agent::at(ended_ago + (20 - step) * 15);
    let record = |uuid: String, role: &str, step: i64, content: serde_json::Value| serde_json::json!({
        "type": role, "uuid": uuid, "sessionId": id, "cwd": cwd, "timestamp": at(step),
        "message": {"role": role, "content": content},
    }).to_string();
    let mut lines = vec![record("u0".into(), "user", 0, serde_json::json!("look at the WAL lock in the cache"))];
    for i in 0..10 {
        let tool = format!("toolu_{i}");
        lines.push(record(format!("a{i}"), "assistant", 2 * i + 1, serde_json::json!([
            {"type": "tool_use", "id": tool, "name": "Read", "input": {"file_path": cwd.join(format!("src/f{i}.rs"))}}])));
        lines.push(record(format!("r{i}"), "user", 2 * i + 2, serde_json::json!([
            {"type": "tool_result", "tool_use_id": tool, "content": "fn main() {}"}])));
    }
    let path = dir.join(format!("{id}.jsonl"));
    std::fs::write(&path, lines.join("\n") + "\n").unwrap();
    let file = std::fs::File::options().write(true).open(&path).unwrap();
    file.set_modified(SystemTime::now() - Duration::from_secs(600)).unwrap();
    path
}

#[test]
fn imported_sessions_are_never_reviewed_on_their_own() {
    let tmp = tempfile::tempdir().unwrap();
    let project = repo(tmp.path(), "acme");
    let cwd = project.to_str().unwrap();
    let account = tmp.path().join(".claude");
    std::fs::create_dir_all(&account).unwrap();
    std::fs::write(account.join(".claude.json"), "{}").unwrap();
    let fake = fake_claude(tmp.path());
    let data = tmp.path().join("data");
    fake.configure(&data, serde_json::json!({"enabled": true, "require_approval": true}));
    {
        // A Cadex session makes the project known; its job sets the
        // watermark at its end, 30 min back.
        let engine = start_with_env(tmp.path(), ARGS, &[]);
        work(&engine.socket, cwd, S1, 2, Some(2_000));
        end(&engine.socket, cwd, S1, Some(1_800));
        wait_for("the first job", Duration::from_secs(20), || {
            ledger(&data).iter().any(|l| l["session"] == S1) && idle(&engine.socket)
        });
    }
    // Two sessions that ran outside Cadex after it, long enough to review.
    std::fs::remove_file(data.join("imports/outside.json")).ok();
    long_transcript(&account, H1, &project, 900);
    long_transcript(&account, H2, &project, 700);
    let engine = start_with_env(tmp.path(), ARGS, &[]);
    let s = &engine.socket;
    wait_for("the outside sessions imported", Duration::from_secs(20), || {
        data.join("imports/outside.json").exists() && common::tool(s, "memory_read_session_observations", serde_json::json!({
            "session_id": H2, "workspace": "default", "project": "acme"})).contains("WAL lock")
    });
    // A live session's end runs the agent; the imported ones are past the
    // watermark but not candidates.
    work(s, cwd, S2, 1, None);
    end(s, cwd, S2, None);
    wait_for("the live session's job", Duration::from_secs(20), || {
        ledger(&data).iter().any(|l| l["session"] == S2) && idle(s)
    });
    assert!(fake.calls_for("AutoImproveLlmResponse").is_empty(), "an imported session was reviewed");
    assert!(!ledger(&data).iter().any(|l| l["kind"] == "auto-improve"), "{:?}", ledger(&data));
}
