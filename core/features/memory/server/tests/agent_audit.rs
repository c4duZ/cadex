//! The memory agent's audit (plan 35 phase D, 2026-11-19), with the fake
//! `claude` of tests/common/agent.rs: a session end with work leaves each
//! call's request and response in `<data-dir>/agent/calls/`, 0600, named by
//! its ledger line; a SessionStart leaves the briefing it got in
//! `<data-dir>/agent/briefings/<session>.md`, and the Memory page's preview
//! (`claim=0`) leaves none. (Retention is the unit test in
//! src/agent/audit.rs.)

mod common;

use std::os::unix::fs::PermissionsExt;
use std::path::Path;
use std::time::Duration;

use common::agent::{ARGS, end, fake_claude, hook, ledger, wait_for, work};
use common::{ok, query, repo, start_with_env};

const S1: &str = "b2b2b2b2-0000-4000-8000-000000000001";
const S2: &str = "b2b2b2b2-0000-4000-8000-000000000002";

fn mode(path: &Path) -> u32 {
    std::fs::metadata(path).unwrap().permissions().mode() & 0o777
}

#[test]
fn a_session_end_leaves_each_calls_request_and_response() {
    let tmp = tempfile::tempdir().unwrap();
    let project = repo(tmp.path(), "acme");
    let cwd = project.to_str().unwrap();
    let fake = fake_claude(tmp.path());
    let data = tmp.path().join("data");
    fake.configure(&data, serde_json::json!({"enabled": true}));
    let engine = start_with_env(tmp.path(), ARGS, &[]);
    work(&engine.socket, cwd, S1, 2, None);
    end(&engine.socket, cwd, S1, None);

    wait_for("the consolidate line", Duration::from_secs(20), || ledger(&data).iter().any(|l| l["kind"] == "consolidate"));
    let line = ledger(&data).into_iter().find(|l| l["kind"] == "consolidate").unwrap();
    let rel = line["call"].as_str().unwrap_or_else(|| panic!("no call file on {line}"));
    let file = data.join("agent").join(rel);
    assert!(rel.starts_with("calls/") && rel.contains("-consolidate-"), "{rel}");
    assert_eq!((mode(&file), mode(file.parent().unwrap())), (0o600, 0o700));

    let record: serde_json::Value = serde_json::from_str(&std::fs::read_to_string(&file).unwrap()).unwrap();
    assert_eq!((record["project"].as_str(), record["session"].as_str()), (Some("acme"), Some(S1)));
    let request = &record["request"];
    let sent = fake.calls_for("ConsolidatedPage").pop().expect("the consolidation call");
    assert_eq!(request["stdin"].as_str(), Some(sent.stdin.as_str()), "the stdin as sent");
    assert!(request["stdin"].as_str().unwrap().contains("fix the WAL lock in the cache"));
    assert!(request["system"].as_str().unwrap().len() > 100, "upstream's system prompt");
    let argv: Vec<&str> = request["argv"].as_array().unwrap().iter().filter_map(|a| a.as_str()).collect();
    assert_eq!((argv[0], argv[13]), ("-p", "--system-prompt"));
    assert!(argv[14].starts_with("<system prompt"), "the system prompt only once: {}", argv[14]);
    let response = &record["response"];
    assert_eq!((response["exit"].as_i64(), response["error"].is_null()), (Some(0), true), "{response}");
    let answer = response["stdout"]["result"].as_str().expect("the parsed answer");
    assert!(answer.contains("The fake agent summarized the session."), "{answer}");
    assert!(!record.to_string().contains("CLAUDE_CONFIG_DIR"), "no environment in the audit");
}

#[test]
fn a_session_start_leaves_the_briefing_it_got() {
    let tmp = tempfile::tempdir().unwrap();
    let project = repo(tmp.path(), "acme");
    let cwd = project.to_str().unwrap();
    let data = tmp.path().join("data");
    std::fs::write(project.join(".ai-memory.toml"), "project = \"acme\"\n[briefing]\ninject_on_session_start = true\n").unwrap();
    let engine = start_with_env(tmp.path(), ARGS, &[]);
    let s = &engine.socket;
    common::tool(s, "memory_write_page", serde_json::json!({"workspace": "default", "project": "acme",
        "path": "_rules/tabs.md", "body": "# Tabs\n\nIndent with tabs.\n", "kind": "rule"}));
    let briefings = data.join("agent").join("briefings");

    // The Memory page's preview asks with `claim=0` and no session: nothing kept.
    let preview = query(&[("cwd", cwd)]);
    ok(s, "GET", &format!("/cadex/memory/briefing?{preview}"), None).expect("the preview");
    let peek = query(&[("agent", "claude-code"), ("cwd", cwd), ("session_id", S2), ("claim", "0")]);
    ok(s, "GET", &format!("/handoff?{peek}"), None).expect("a peek");

    // The real start, as `cadex memory-hook` makes it.
    hook(s, "session-start", cwd, S1, "s1", serde_json::json!({"session_id": S1, "cwd": cwd, "source": "startup"}));
    let qs = query(&[("agent", "claude-code"), ("cwd", cwd), ("project_strategy", "repo-root"), ("session_id", S1)]);
    let got = ok(s, "GET", &format!("/handoff?{qs}"), None).expect("the session's context");
    assert!(got.contains("Indent with tabs"), "{got}");
    let file = briefings.join(format!("{S1}.md"));
    wait_for("the kept briefing", Duration::from_secs(5), || file.exists());
    assert_eq!(std::fs::read_to_string(&file).unwrap(), got, "the file is what the session got");
    assert_eq!((mode(&file), mode(&briefings)), (0o600, 0o700));
    let kept: Vec<_> = std::fs::read_dir(&briefings).unwrap().flatten().map(|e| e.file_name()).collect();
    assert_eq!(kept.len(), 1, "only the real start: {kept:?}");
}
