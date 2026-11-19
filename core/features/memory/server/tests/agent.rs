//! The memory agent (plan 22 phase G, ADR 0029), with a fake `claude`
//! (tests/common/agent.rs): off, a SessionEnd runs nothing; on, it
//! consolidates through `claude -p` with exactly the proven flags and
//! environment, in the project's account, and the ledger has the cost; the
//! daily budget skips a job; a pause starts none; the bootstrap estimate
//! calls nothing and the run works with the agent off; auto-improve stages
//! its proposal for the owner; a session with no prompt and no tool calls
//! nothing; a dream follows a SessionEnd only when the
//! Mac is idle. (The dream stopping when the owner comes back is the unit
//! test in src/agent/dream.rs: with no embedder, a dream has nothing to run.)

mod common;

use std::path::Path;
use std::time::{Duration, Instant};

use common::agent::{COST, VERSION, fake_claude, ledger};
use common::{ok, query, repo, request, start_with_env};

const ARGS: &[&str] = &["--keep-alive", "--import-delay-ms", "100"];

fn hook(socket: &Path, event: &str, cwd: &str, session: &str, key: &str, body: serde_json::Value) {
    let qs = query(&[("event", event), ("agent", "claude-code"), ("cwd", cwd), ("session_id", session),
        ("project_strategy", "repo-root"), ("ingest_key", key)]);
    ok(socket, "POST", &format!("/hook?{qs}"), Some(&body.to_string())).unwrap_or_else(|| panic!("{event} refused"));
}

fn wait_for(what: &str, limit: Duration, mut done: impl FnMut() -> bool) {
    let deadline = Instant::now() + limit;
    while Instant::now() < deadline {
        if done() {
            return;
        }
        std::thread::sleep(Duration::from_millis(100));
    }
    panic!("timed out waiting for {what}");
}

fn at(ago_secs: i64) -> String {
    jiff::Timestamp::now().checked_sub(jiff::SignedDuration::from_secs(ago_secs)).unwrap().to_string()
}

/// A session with a prompt and `tools` edits; events `ago` seconds back,
/// 10 s apart, when given. Not ended.
fn work(socket: &Path, cwd: &str, id: &str, tools: usize, ago: Option<i64>) {
    let stamp = |body: &mut serde_json::Value, i: i64| {
        if let Some(ago) = ago {
            body["occurred_at"] = at(ago - i * 10).into();
        }
    };
    let mut start = serde_json::json!({"session_id": id, "cwd": cwd, "source": "startup"});
    stamp(&mut start, 0);
    hook(socket, "session-start", cwd, id, &format!("{id}-s"), start);
    let mut prompt = serde_json::json!({"session_id": id, "cwd": cwd, "hook_event_name": "UserPromptSubmit",
        "prompt": "fix the WAL lock in the cache"});
    stamp(&mut prompt, 1);
    hook(socket, "user-prompt-submit", cwd, id, &format!("{id}-p"), prompt);
    for i in 0..tools {
        let mut edit = serde_json::json!({"session_id": id, "cwd": cwd, "hook_event_name": "PostToolUse", "tool_name": "Edit",
            "tool_input": {"file_path": format!("{cwd}/src/cache{i}.rs")},
            "tool_response": {"filePath": format!("{cwd}/src/cache{i}.rs"), "success": true}});
        stamp(&mut edit, 2 + i as i64);
        hook(socket, "post-tool-use", cwd, id, &format!("{id}-t{i}"), edit);
    }
    let count = || {
        let out = common::tool(socket, "memory_read_session_observations", serde_json::json!({
            "session_id": id, "workspace": "default", "project": "acme", "limit": 100}));
        out.matches("tool file: Edit").count() >= tools && out.contains("WAL lock")
    };
    wait_for("the events stored", Duration::from_secs(15), count);
}

fn end(socket: &Path, cwd: &str, id: &str, ago: Option<i64>) {
    let mut body = serde_json::json!({"session_id": id, "cwd": cwd, "hook_event_name": "SessionEnd", "reason": "exit"});
    if let Some(ago) = ago {
        body["occurred_at"] = at(ago).into();
    }
    hook(socket, "session-end", cwd, id, &format!("{id}-e"), body);
}

fn status(socket: &Path) -> serde_json::Value {
    serde_json::from_str(&ok(socket, "GET", "/cadex/agent/status", None).expect("status")).unwrap()
}

/// A page's file anywhere in the wiki.
fn page(dir: &Path, name: &str) -> Option<std::path::PathBuf> {
    for entry in std::fs::read_dir(dir).ok()?.flatten() {
        let path = entry.path();
        if path.is_dir() {
            if let Some(found) = page(&path, name) {
                return Some(found);
            }
        } else if path.file_name().is_some_and(|n| n == name) {
            return Some(path);
        }
    }
    None
}

const S1: &str = "a1a1a1a1-0000-4000-8000-000000000001";
const S2: &str = "a1a1a1a1-0000-4000-8000-000000000002";

#[test]
fn off_a_session_end_runs_nothing() {
    let tmp = tempfile::tempdir().unwrap();
    let cwd = repo(tmp.path(), "acme");
    let cwd = cwd.to_str().unwrap();
    let fake = fake_claude(tmp.path());
    let data = tmp.path().join("data");
    fake.configure(&data, serde_json::json!({"enabled": false}));
    let engine = start_with_env(tmp.path(), ARGS, &[]);
    work(&engine.socket, cwd, S1, 2, None);
    end(&engine.socket, cwd, S1, None);
    std::thread::sleep(Duration::from_millis(1500));
    assert!(fake.calls().is_empty(), "claude ran with the agent off");
    assert!(ledger(&data).is_empty());
    assert_eq!(status(&engine.socket)["enabled"], false);
    let qs = query(&[("cwd", cwd)]);
    let dream = request(&engine.socket, "POST", &format!("/cadex/agent/run-dream?{qs}"), None, Some(common::TOKEN));
    assert_eq!(dream.map(|(s, _)| s), Some(409));
}

#[test]
fn on_a_session_end_consolidates_through_claude_with_the_proven_command() {
    let tmp = tempfile::tempdir().unwrap();
    let project = repo(tmp.path(), "acme");
    let cwd = project.to_str().unwrap();
    let fake = fake_claude(tmp.path());
    let data = tmp.path().join("data");
    let account = tmp.path().join("work-account");
    fake.configure(&data, serde_json::json!({"enabled": true, "config_dir": tmp.path().join("main-account"),
        "project_accounts": {cwd: account}}));
    let env = [("CLAUDECODE", "1"), ("CLAUDE_CODE_ENTRYPOINT", "cli"), ("CLAUDE_CONFIG_DIR", "/wrong")];
    let engine = start_with_env(tmp.path(), ARGS, &env);
    work(&engine.socket, cwd, S1, 2, None);
    end(&engine.socket, cwd, S1, None);

    let page_file = format!("{S1}.md");
    wait_for("the consolidated session page", Duration::from_secs(20), || {
        page(&data.join("wiki"), &page_file)
            .and_then(|p| std::fs::read_to_string(p).ok())
            .is_some_and(|t| t.contains("The fake agent summarized the session."))
    });
    let lines = ledger(&data);
    let line = lines.iter().find(|l| l["kind"] == "consolidate").expect("a consolidate line");
    assert_eq!((line["cost_usd"].as_f64(), line["ok"].as_bool()), (Some(COST), Some(true)), "{line}");
    assert_eq!((line["claude_version"].as_str(), line["model"].as_str()), (Some(VERSION), Some("haiku")));
    assert_eq!((line["project"].as_str(), line["session"].as_str()), (Some("acme"), Some(S1)));

    let calls = fake.calls_for("ConsolidatedPage");
    let call = calls.first().expect("the consolidation call");
    let a = &call.argv;
    assert_eq!(a[..6], ["-p", "--model", "haiku", "--max-budget-usd", "0.2500", "--no-session-persistence"]);
    assert_eq!(a[6..9], ["--tools", "", "--strict-mcp-config"]);
    assert_eq!((a[9].as_str(), a[11].as_str(), a[13].as_str()), ("--mcp-config", "--settings", "--system-prompt"));
    assert_eq!(a[15..], ["--output-format", "json"]);
    assert!(!a.iter().any(|x| x == "--bare"));
    assert_eq!(std::fs::read_to_string(&a[10]).ok(), None, "the scratch folder is removed after the call");
    assert!(a[14].len() > 100, "upstream's system prompt");
    assert!(call.stdin.contains("\"title\":\"ConsolidatedPage\""));
    assert!(call.cwd_entries.trim().is_empty() && call.cwd.contains("cadex-agent-"), "{} {}", call.cwd, call.cwd_entries);
    assert_eq!(call.env.get("CLAUDE_CONFIG_DIR").map(String::as_str), account.to_str(), "the project's account");
    assert!(!call.env.contains_key("CLAUDECODE"));
    assert!(!call.env.keys().any(|k| k.starts_with("CLAUDE_CODE_")), "{:?}", call.env.keys());
}

#[test]
fn a_session_with_no_prompt_and_no_tool_calls_nothing() {
    // Plan 35 C: a panel opened and closed with no prompt (3cd2e5f6, d2a9e4be in the owner's
    // memory) made a page and set off consolidate, profile and auto-improve.
    let tmp = tempfile::tempdir().unwrap();
    let cwd = repo(tmp.path(), "acme");
    let cwd = cwd.to_str().unwrap();
    let fake = fake_claude(tmp.path());
    let data = tmp.path().join("data");
    fake.configure(&data, serde_json::json!({"enabled": true}));
    let engine = start_with_env(tmp.path(), ARGS, &[]);
    hook(&engine.socket, "session-start", cwd, S1, &format!("{S1}-s"),
         serde_json::json!({"session_id": S1, "cwd": cwd, "source": "startup"}));
    end(&engine.socket, cwd, S1, None);
    wait_for("the empty session's line", Duration::from_secs(20), || {
        ledger(&data).iter().any(|l| l["session"] == S1 && l["error"] == "empty session: no prompt and no tool")
    });
    assert!(fake.calls().is_empty(), "claude ran for an empty session");
    assert!(ledger(&data).iter().all(|l| l["cost_usd"].as_f64() == Some(0.0)));
    assert!(page(&data.join("wiki"), &format!("{S1}.md")).is_none(), "an empty session has no page");
}

#[test]
fn the_daily_budget_skips_a_job_and_a_pause_starts_none() {
    let tmp = tempfile::tempdir().unwrap();
    let project = repo(tmp.path(), "acme");
    let cwd = project.to_str().unwrap();
    let fake = fake_claude(tmp.path());
    let data = tmp.path().join("data");
    fake.configure(&data, serde_json::json!({"enabled": true}));
    let engine = start_with_env(tmp.path(), ARGS, &[]);
    let s = &engine.socket;

    assert_eq!(ok(s, "POST", "/cadex/agent/pause?on=1", None).as_deref(), Some(r#"{"paused":true}"#));
    work(s, cwd, S1, 2, None);
    end(s, cwd, S1, None);
    wait_for("the job queued", Duration::from_secs(10), || status(s)["queue"][0]["state"] == "queued");
    std::thread::sleep(Duration::from_millis(500));
    assert!(fake.calls().is_empty(), "a paused agent started a job");
    assert_eq!(status(s)["paused"], true);
    ok(s, "POST", "/cadex/agent/pause?on=0", None).unwrap();
    wait_for("the consolidation after the pause", Duration::from_secs(20), || !fake.calls_for("ConsolidatedPage").is_empty());
    wait_for("the queue empty", Duration::from_secs(20), || status(s)["queue"].as_array().is_some_and(Vec::is_empty));

    // Spent so far plus 0.25 would pass 0.26: the next job is skipped.
    fake.configure(&data, serde_json::json!({"enabled": true, "daily_budget_usd": 0.26}));
    let before = fake.calls().len();
    work(s, cwd, S2, 2, None);
    end(s, cwd, S2, None);
    wait_for("the budget line", Duration::from_secs(10), || {
        ledger(&data).iter().any(|l| l["kind"] == "session-end" && l["error"] == "budget" && l["session"] == S2)
    });
    assert_eq!(fake.calls().len(), before, "a job ran past the daily budget");
    let st = status(s);
    assert!(st["spent_today_usd"].as_f64().unwrap() >= COST && st["daily_budget_usd"] == 0.26, "{st}");
    assert_eq!(st["claude_version"], VERSION);
}

#[test]
fn bootstrap_estimates_without_calling_and_runs_with_the_agent_off() {
    let tmp = tempfile::tempdir().unwrap();
    let project = repo(tmp.path(), "acme");
    let cwd = project.to_str().unwrap();
    let fake = fake_claude(tmp.path());
    let data = tmp.path().join("data");
    fake.configure(&data, serde_json::json!({"enabled": false}));
    let engine = start_with_env(tmp.path(), ARGS, &[("CLAUDE_CONFIG_DIR", "/wrong")]);
    let s = &engine.socket;
    work(s, cwd, S1, 3, None);
    end(s, cwd, S1, None);
    std::thread::sleep(Duration::from_millis(500));

    let qs = query(&[("cwd", cwd), ("dry_run", "1")]);
    let estimate: serde_json::Value = serde_json::from_str(&ok(s, "POST", &format!("/cadex/agent/bootstrap?{qs}"), None).unwrap()).unwrap();
    assert_eq!((estimate["sessions"].as_u64(), estimate["calls"].as_u64()), (Some(1), Some(1)), "{estimate}");
    assert!(estimate["observations"].as_u64().unwrap() >= 5 && estimate["estimate_usd"].as_f64().unwrap() > 0.0, "{estimate}");
    assert!(fake.calls().is_empty(), "the estimate called claude");

    let qs = query(&[("cwd", cwd)]);
    let queued = request(s, "POST", &format!("/cadex/agent/bootstrap?{qs}"), None, Some(common::TOKEN)).unwrap();
    assert_eq!(queued.0, 202, "{}", queued.1);
    // Upstream's bootstrap writes the pages and then its bootstrap.md
    // manifest: waiting for the first page only and reading the manifest at
    // once failed under `make check`'s load (2026-11-16). Wait for both.
    wait_for("the bootstrap pages and manifest", Duration::from_secs(20), || {
        page(&data.join("wiki"), "0001-use-sqlite.md").is_some() && page(&data.join("wiki"), "bootstrap.md").is_some()
    });
    let call = fake.calls_for("BootstrapBatch").pop().expect("the bootstrap call");
    assert!(call.stdin.contains("fix the WAL lock in the cache") && call.stdin.contains(S1));
    assert!(!call.env.contains_key("CLAUDE_CONFIG_DIR"), "the default account sets no CLAUDE_CONFIG_DIR");
    assert!(ledger(&data).iter().any(|l| l["kind"] == "bootstrap" && l["cost_usd"].as_f64() == Some(COST)));
}

#[test]
fn auto_improve_stages_its_proposal_for_the_owner() {
    let tmp = tempfile::tempdir().unwrap();
    let project = repo(tmp.path(), "acme");
    let cwd = project.to_str().unwrap();
    let fake = fake_claude(tmp.path());
    let data = tmp.path().join("data");
    fake.configure(&data, serde_json::json!({"enabled": true, "require_approval": true}));
    let engine = start_with_env(tmp.path(), ARGS, &[]);
    let s = &engine.socket;
    // Too short for upstream's preflight (8 observations, 120 s): reviewed
    // without a call, so it does not use the project's hour.
    work(s, cwd, S1, 2, Some(1_000));
    end(s, cwd, S1, Some(900));
    wait_for("the first session's job", Duration::from_secs(20), || {
        ledger(&data).iter().any(|l| l["session"] == S1) && status(s)["queue"].as_array().is_some_and(Vec::is_empty)
    });
    // Long enough to be reviewed.
    work(s, cwd, S2, 10, Some(300));
    end(s, cwd, S2, None);
    wait_for("the staged proposal", Duration::from_secs(30), || status(s)["proposals_pending"].as_u64() == Some(1));
    assert!(!fake.calls_for("AutoImproveLlmResponse").is_empty());
    assert!(page(&data.join("wiki"), "wal-lock.md").is_none(), "a proposal was applied without the owner");
    assert!(ledger(&data).iter().any(|l| l["kind"] == "auto-improve" && l["session"] == S2));
}

#[test]
fn a_dream_follows_a_session_end_only_when_the_mac_is_idle() {
    let tmp = tempfile::tempdir().unwrap();
    let project = repo(tmp.path(), "acme");
    let cwd = project.to_str().unwrap();
    let fake = fake_claude(tmp.path());
    let data = tmp.path().join("data");
    fake.configure(&data, serde_json::json!({"enabled": true}));
    let idle = tmp.path().join("idle");
    std::fs::write(&idle, "5").unwrap();
    let env = [("CADEX_MEMORY_TEST_IDLE_FILE", idle.to_str().unwrap()), ("CADEX_MEMORY_TEST_IDLE_POLL_MS", "50")];
    let engine = start_with_env(tmp.path(), ARGS, &env);
    let s = &engine.socket;
    let dreams = || ledger(&data).iter().filter(|l| l["kind"] == "dream").count();

    work(s, cwd, S1, 1, None);
    end(s, cwd, S1, None);
    wait_for("the job", Duration::from_secs(20), || !fake.calls_for("ConsolidatedPage").is_empty());
    std::thread::sleep(Duration::from_millis(800));
    assert_eq!(dreams(), 0, "a dream with the owner at the keyboard");

    std::fs::write(&idle, "900").unwrap();
    work(s, cwd, S2, 1, None);
    end(s, cwd, S2, None);
    wait_for("the dream", Duration::from_secs(20), || dreams() == 1);
    let line = ledger(&data).into_iter().find(|l| l["kind"] == "dream").unwrap();
    assert_eq!(line["error"], "no embedder: nothing to cluster", "{line}");

    let qs = query(&[("cwd", cwd)]);
    let manual = request(s, "POST", &format!("/cadex/agent/run-dream?{qs}"), None, Some(common::TOKEN)).unwrap();
    assert_eq!(manual.0, 202);
    wait_for("the manual dream", Duration::from_secs(10), || dreams() == 2);
}
