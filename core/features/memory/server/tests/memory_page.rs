//! The Memory page's engine routes (plan 22 phase H, 2026-11-16), as
//! `cadex memory-agent` calls them: the overview of a folder; the briefing,
//! equal to what the following real SessionStart gets and never consuming
//! the handoff; writing a page (a new version and a commit, the metadata
//! kept); deleting one; the reindex of a file edited on disk; the proposals
//! approved and rejected; projects.json. (The engine down is the client's
//! answer, `{"running":false}` without connecting: agent_client.zig.)

mod common;

use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::Duration;

use common::agent::fake_claude;
use common::session::{end, hook, wait_for, work};
use common::{TOKEN, ok, query, repo, request, start, start_with_env, tool};

const ARGS: &[&str] = &["--keep-alive", "--import-delay-ms", "100"];
const S1: &str = "b2b2b2b2-0000-4000-8000-000000000001";
const S2: &str = "b2b2b2b2-0000-4000-8000-000000000002";

fn json(socket: &Path, method: &str, path: &str, body: Option<&str>) -> serde_json::Value {
    let (status, text) = request(socket, method, path, body, Some(TOKEN)).expect("the engine answers");
    assert!((200..300).contains(&status), "{method} {path}: {status} {text}");
    serde_json::from_str(&text).unwrap_or_else(|_| panic!("not JSON: {text}"))
}

fn route(name: &str, pairs: &[(&str, &str)]) -> String {
    format!("/cadex/memory/{name}?{}", query(pairs))
}

fn commits(dir: &Path) -> usize {
    let out = Command::new("git").args(["rev-list", "--count", "HEAD"]).current_dir(dir).output().unwrap();
    String::from_utf8_lossy(&out.stdout).trim().parse().unwrap_or(0)
}

fn git(dir: &Path, args: &[&str]) -> String {
    String::from_utf8_lossy(&Command::new("git").args(args).current_dir(dir).output().unwrap().stdout).into_owned()
}

fn read_page(socket: &Path, path: &str) -> String {
    tool(socket, "memory_read_page", serde_json::json!({"workspace": "default", "project": "acme", "path": path}))
}

fn wiki_dir(socket: &Path, cwd: &str) -> PathBuf {
    let overview = json(socket, "GET", &route("overview", &[("cwd", cwd)]), None);
    PathBuf::from(overview["wiki_dir"].as_str().expect("the project's wiki folder"))
}

#[test]
fn the_overview_names_the_project_and_projects_json_follows() {
    let tmp = tempfile::tempdir().unwrap();
    let project = repo(tmp.path(), "acme");
    let cwd = project.to_str().unwrap();
    let data = tmp.path().join("data");
    let engine = start(tmp.path(), ARGS);
    let s = &engine.socket;

    let fresh = json(s, "GET", &route("overview", &[("cwd", cwd)]), None);
    assert_eq!(fresh["running"], true);
    assert_eq!((fresh["workspace"].as_str(), fresh["project"].as_str()), (Some("default"), Some("acme")));
    assert!(fresh["wiki_dir"].is_null(), "no project in the store yet: {fresh}");
    assert_eq!((fresh["pages"].as_u64(), fresh["sessions"].as_u64(), fresh["model"].as_str()), (Some(0), Some(0), Some("off")));
    assert_eq!(fresh["imported"], serde_json::json!({"state": "none", "sessions": 0, "accounts": []}));
    let elsewhere = tmp.path().join("loose");
    std::fs::create_dir_all(&elsewhere).unwrap();
    let loose = json(s, "GET", &route("overview", &[("cwd", elsewhere.to_str().unwrap())]), None);
    assert!(loose["project"].is_null() && loose["workspace"].is_null(), "{loose}");

    // A SessionStart resolves the project: projects.json has it at once.
    hook(s, "session-start", cwd, S1, "s1", serde_json::json!({"session_id": S1, "cwd": cwd, "source": "startup"}));
    let file = data.join("projects.json");
    wait_for("projects.json", Duration::from_secs(10), || std::fs::read_to_string(&file).is_ok_and(|t| t.contains("\"acme\"")));
    assert_eq!(std::fs::metadata(&file).unwrap().permissions().mode() & 0o777, 0o600);
    let written = json(s, "POST", &route("write-page", &[("cwd", cwd), ("path", "notes/a.md")]), Some("# A\n\nNote.\n"));
    assert_eq!(written, serde_json::json!({"ok": true, "path": "notes/a.md"}));

    let up = json(s, "GET", &route("overview", &[("cwd", cwd)]), None);
    let dir = PathBuf::from(up["wiki_dir"].as_str().unwrap());
    assert!(dir.join("notes/a.md").is_file(), "{up}");
    assert!(dir.starts_with(data.join("wiki")));
    assert!(up["pages"].as_u64().unwrap() >= 1 && up["sessions"].as_u64() == Some(1), "{up}");
    wait_for("the history import done", Duration::from_secs(10), || {
        json(s, "GET", &route("overview", &[("cwd", cwd)]), None)["imported"]["state"] == "done"
    });
    let listed: serde_json::Value = serde_json::from_str(&std::fs::read_to_string(&file).unwrap()).unwrap();
    let entry = &listed["projects"][0];
    assert_eq!((entry["workspace"].as_str(), entry["project"].as_str()), (Some("default"), Some("acme")));
    assert_eq!(entry["wiki_dir"], up["wiki_dir"]);
    let root = PathBuf::from(entry["root"].as_str().unwrap());
    assert_eq!(root.canonicalize().unwrap(), project.canonicalize().unwrap());
}

#[test]
fn the_briefing_is_what_the_next_session_start_gets_and_claims_nothing() {
    let tmp = tempfile::tempdir().unwrap();
    let project = repo(tmp.path(), "acme");
    let cwd = project.to_str().unwrap();
    // The brief comes from the marker only, as upstream (plan 35 B): Cadex writes this file.
    std::fs::write(project.join(".ai-memory.toml"), "project = \"acme\"\n[briefing]\ninject_on_session_start = true\n").unwrap();
    let engine = start(tmp.path(), ARGS);
    let s = &engine.socket;
    tool(s, "memory_write_page", serde_json::json!({"workspace": "default", "project": "acme",
        "path": "_rules/tabs.md", "body": "# Tabs\n\nIndent with tabs.\n", "kind": "rule"}));
    work(s, cwd, S1, 2, None);
    end(s, cwd, S1, None);
    let list = || tool(s, "memory_handoff_list", serde_json::json!({"workspace": "default", "project": "acme"}));
    wait_for("Cadex's handoff", Duration::from_secs(15), || list().contains("src/cache1.rs"));

    let briefing = || ok(s, "GET", &route("briefing", &[("cwd", cwd)]), None).expect("the briefing");
    let first = briefing();
    assert!(first.contains("pending handoff from previous session") && first.contains("src/cache1.rs"), "{first}");
    assert!(first.contains("Indent with tabs"), "the brief is in: {first}");
    assert!(!first.contains("📬"), "the notice was swapped for the handoff: {first}");
    assert_eq!(briefing(), first, "asking again finds the same handoff");

    // The real start, as `cadex memory-hook` makes it.
    hook(s, "session-start", cwd, S2, "s2", serde_json::json!({"session_id": S2, "cwd": cwd, "source": "startup"}));
    let qs = query(&[("agent", "claude-code"), ("cwd", cwd), ("project_strategy", "repo-root"), ("session_id", S2)]);
    let real = ok(s, "GET", &format!("/handoff?{qs}"), None).expect("the session's context");
    assert_eq!(real, first, "the page showed what the session got");
    assert!(!briefing().contains("pending handoff from previous session"), "the session claimed it");
    std::fs::remove_file(project.join(".ai-memory.toml")).unwrap();
    assert!(!briefing().contains("Indent with tabs"), "no marker, no brief (upstream's default)");

    let empty = repo(tmp.path(), "empty");
    let none = ok(s, "GET", &route("briefing", &[("cwd", empty.to_str().unwrap())]), None).expect("an empty briefing");
    assert!(none.trim().is_empty(), "{none}");
}

#[test]
fn with_no_core_page_the_brief_is_not_sent_even_when_the_marker_asks() {
    // Plan 35 E: the bkdg-center's brief was only titles of session pages, under a footer naming
    // pinned / _rules/ / _slots/ pages it did not have.
    let tmp = tempfile::tempdir().unwrap();
    let project = repo(tmp.path(), "acme");
    let cwd = project.to_str().unwrap();
    std::fs::write(project.join(".ai-memory.toml"), "project = \"acme\"\n[briefing]\ninject_on_session_start = true\n").unwrap();
    let engine = start(tmp.path(), ARGS);
    let s = &engine.socket;
    tool(s, "memory_write_page", serde_json::json!({"workspace": "default", "project": "acme",
        "path": "decisions/wal-lock.md", "body": "# Keep the WAL lock\n\nOne writer.\n", "kind": "decision"}));
    let briefing = || ok(s, "GET", &route("briefing", &[("cwd", cwd)]), None).expect("the briefing");
    let none = briefing();
    assert!(!none.contains("Keep the WAL lock") && !none.contains("compiled from"), "only recent titles, no brief: {none}");
    tool(s, "memory_write_page", serde_json::json!({"workspace": "default", "project": "acme",
        "path": "_rules/tabs.md", "body": "# Tabs\n\nIndent with tabs.\n", "kind": "rule"}));
    let some = briefing();
    assert!(some.contains("Indent with tabs") && some.contains("Keep the WAL lock"), "a core page brings the brief: {some}");
}

#[test]
fn writing_a_page_keeps_its_metadata_and_commits_and_deleting_removes_it() {
    let tmp = tempfile::tempdir().unwrap();
    let project = repo(tmp.path(), "acme");
    let cwd = project.to_str().unwrap();
    let engine = start(tmp.path(), ARGS);
    let s = &engine.socket;
    let at = [("cwd", cwd), ("path", "gotchas/wal.md")];
    let first = "---\nkind: gotcha\ntags: [wal]\nentities: [sqlite]\nabstract: Checkpoint first\n---\n# WAL\n\nFirst text.\n";
    json(s, "POST", &route("write-page", &at), Some(first));
    let dir = wiki_dir(s, cwd);
    let file = dir.join("gotchas/wal.md");
    let before = commits(&dir);
    let id_of = |text: &str| serde_json::from_str::<serde_json::Value>(text).ok().map(|v| v.to_string()).unwrap_or_default();
    let v1 = id_of(&read_page(s, "gotchas/wal.md"));

    json(s, "POST", &route("write-page", &at), Some("# WAL\n\nSecond text.\n"));
    let on_disk = std::fs::read_to_string(&file).unwrap();
    assert!(on_disk.contains("Second text.") && !on_disk.contains("First text."), "{on_disk}");
    assert!(on_disk.contains("kind: gotcha") && on_disk.contains("wal") && on_disk.contains("sqlite"), "metadata kept: {on_disk}");
    assert!(on_disk.contains("Checkpoint first"), "{on_disk}");
    assert!(read_page(s, "gotchas/wal.md").contains("Second text."));
    assert_ne!(id_of(&read_page(s, "gotchas/wal.md")), v1, "a new version");
    assert!(commits(&dir) > before, "the write was committed");
    assert!(git(&dir, &["status", "--porcelain", "--", "gotchas"]).is_empty());

    let gone = json(s, "POST", &route("delete-page", &at), None);
    assert_eq!(gone, serde_json::json!({"ok": true}));
    assert!(!file.exists());
    assert!(git(&dir, &["log", "-1", "--format=%s"]).contains("memory_delete_page"));
    let bad = request(s, "POST", &route("write-page", &[("cwd", cwd), ("path", "../x.md")]), Some("x"), Some(TOKEN)).unwrap();
    assert_eq!(bad.0, 400, "{}", bad.1);
    assert!(serde_json::from_str::<serde_json::Value>(&bad.1).unwrap()["error"].is_string());
}

#[test]
fn reindex_takes_in_a_file_edited_on_disk_and_commits_it() {
    let tmp = tempfile::tempdir().unwrap();
    let project = repo(tmp.path(), "acme");
    let cwd = project.to_str().unwrap();
    let engine = start(tmp.path(), ARGS);
    let s = &engine.socket;
    json(s, "POST", &route("write-page", &[("cwd", cwd), ("path", "notes/r.md")]), Some("# R\n\nOne fact.\n"));
    let dir = wiki_dir(s, cwd);
    let file = dir.join("notes/r.md");
    let text = std::fs::read_to_string(&file).unwrap();
    std::fs::write(&file, text.replace("One fact.", "Two facts, edited by hand.")).unwrap();

    let reindexed = json(s, "POST", &route("reindex", &[("cwd", cwd)]), None);
    assert_eq!(reindexed, serde_json::json!({"ok": true, "changed": 1}));
    assert!(read_page(s, "notes/r.md").contains("Two facts, edited by hand."));
    assert!(git(&dir, &["status", "--porcelain", "--", "notes"]).is_empty(), "committed");
    assert_eq!(git(&dir, &["log", "-1", "--format=%s"]).trim(), "cadex reindex: default/acme");
    let again = json(s, "POST", &route("reindex", &[("cwd", cwd)]), None);
    assert_eq!(again["changed"], 0);
}

/// An engine with the memory agent on and a staged proposal (as
/// tests/agent.rs makes one, with the fake `claude`).
fn with_a_proposal(tmp: &Path) -> (common::Engine, String) {
    let project = repo(tmp, "acme");
    let cwd = project.to_str().unwrap().to_owned();
    let fake = fake_claude(tmp);
    fake.configure(&tmp.join("data"), serde_json::json!({"enabled": true, "require_approval": true}));
    let engine = start_with_env(tmp, ARGS, &[]);
    let s = &engine.socket;
    work(s, &cwd, S1, 2, Some(1_000));
    end(s, &cwd, S1, Some(900));
    let status = || json(s, "GET", "/cadex/agent/status", None);
    wait_for("the first job", Duration::from_secs(20), || {
        status()["recent"].as_array().is_some_and(|r| r.iter().any(|l| l["session"] == S1)) && status()["queue"].as_array().is_some_and(Vec::is_empty)
    });
    work(s, &cwd, S2, 10, Some(300));
    end(s, &cwd, S2, None);
    wait_for("the staged proposal", Duration::from_secs(30), || status()["proposals_pending"].as_u64() == Some(1));
    (engine, cwd)
}

fn proposals(s: &Path, cwd: &str) -> Vec<serde_json::Value> {
    json(s, "GET", &route("proposals", &[("cwd", cwd)]), None)["proposals"].as_array().unwrap().clone()
}

#[test]
fn a_rejected_proposal_leaves_the_list_and_writes_nothing() {
    let tmp = tempfile::tempdir().unwrap();
    let (engine, cwd) = with_a_proposal(tmp.path());
    let s = &engine.socket;
    let list = proposals(s, &cwd);
    assert_eq!(list.len(), 1);
    let p = &list[0];
    assert_eq!((p["path"].as_str(), p["title"].as_str(), p["kind"].as_str()), (Some("gotchas/wal-lock.md"), Some("WAL lock gotcha"), Some("gotcha")));
    assert!(p["body"].as_str().unwrap().contains("Checkpoint the WAL") && p["summary"].as_str().unwrap().contains("hit it twice"), "{p}");
    assert!(p["created_at"].as_str().unwrap().parse::<jiff::Timestamp>().is_ok(), "{p}");
    let id = p["id"].as_str().unwrap();
    assert_eq!(json(s, "POST", &route("reject", &[("id", id)]), None), serde_json::json!({"ok": true}));
    assert!(proposals(s, &cwd).is_empty());
    let again = request(s, "POST", &route("approve", &[("id", id)]), None, Some(TOKEN)).unwrap();
    assert_eq!(again.0, 404, "decided already: {}", again.1);
    assert!(!wiki_dir(s, &cwd).join("gotchas/wal-lock.md").exists());
}

#[test]
fn an_approved_proposal_becomes_a_committed_page() {
    let tmp = tempfile::tempdir().unwrap();
    let (engine, cwd) = with_a_proposal(tmp.path());
    let s = &engine.socket;
    let id = proposals(s, &cwd)[0]["id"].as_str().unwrap().to_owned();
    assert_eq!(json(s, "POST", &route("approve", &[("id", &id)]), None), serde_json::json!({"ok": true}));
    assert!(proposals(s, &cwd).is_empty());
    let dir = wiki_dir(s, &cwd);
    assert!(std::fs::read_to_string(dir.join("gotchas/wal-lock.md")).unwrap().contains("Checkpoint the WAL"));
    assert!(read_page(s, "gotchas/wal-lock.md").contains("Checkpoint the WAL"));
    assert_eq!(git(&dir, &["log", "-1", "--format=%s"]).trim(), "auto-improve approved: gotchas/wal-lock.md");
}
