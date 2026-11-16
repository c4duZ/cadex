//! `cadex-memory run` choosing and launching agents (plan 22 phase E,
//! 2026-11-16): the automatic harness, `--yolo`, Claude's background attach,
//! Grok's context packet and OpenCode's dialect. The fakes are
//! tests/common/bench.rs's; never a real agent, never the owner's folders.

mod common;

use std::process::Command;

use common::bench::{Bench, bench, saved, stderr};
use common::start;

/// A Claude transcript of this checkout, older than anything else.
fn old_claude_session(bench: &Bench, id: &str) {
    let cwd = bench.project.to_str().unwrap();
    let dir = bench.dir.join("claude-account/projects").join(cwd.replace(|c: char| !c.is_ascii_alphanumeric(), "-"));
    std::fs::create_dir_all(&dir).unwrap();
    let file = dir.join(format!("{id}.jsonl"));
    std::fs::write(&file, format!(
        "{{\"type\":\"user\",\"uuid\":\"u0\",\"sessionId\":\"{id}\",\"cwd\":\"{cwd}\",\"timestamp\":\"2026-11-15T10:00:00Z\",\"message\":{{\"role\":\"user\",\"content\":\"old work\"}}}}\n"
    )).unwrap();
    assert!(Command::new("touch").args(["-t", "202611150900"]).arg(&file).status().unwrap().success());
}

/// A Codex rollout of this checkout, newer than the Claude transcript.
fn new_codex_session(bench: &Bench, id: &str) {
    let day = bench.dir.join(".codex/sessions/2026/11/16");
    std::fs::create_dir_all(&day).unwrap();
    std::fs::write(day.join(format!("rollout-2026-11-16T09-00-00-{id}.jsonl")), format!(
        "{{\"type\":\"session_meta\",\"payload\":{{\"id\":\"{id}\",\"cwd\":\"{}\"}}}}\n\
         {{\"type\":\"response_item\",\"payload\":{{\"type\":\"message\",\"role\":\"user\",\"content\":[{{\"type\":\"input_text\",\"text\":\"earlier\"}}]}}}}\n",
        bench.project.display()
    )).unwrap();
}

#[test]
fn with_no_harness_named_the_newest_checkout_session_continues() {
    let tmp = tempfile::tempdir().unwrap();
    let _engine = start(tmp.path(), &["--keep-alive", "--import-delay-ms", "60000"]);
    let bench = bench(tmp.path(), false);
    old_claude_session(&bench, "11111111-1111-4111-8111-111111111111");
    let codex_id = "00000000-0000-4000-8000-000000000042";
    new_codex_session(&bench, codex_id);
    let output = bench.run("auto", &[], &[]);
    let text = stderr(&output);
    assert!(output.status.success(), "{text}");
    assert!(text.contains(&format!("continuing newest checkout-local codex session {codex_id}")), "{text}");
    let args = bench.args("auto", "codex.args");
    assert_eq!(args[..2], ["resume".to_owned(), codex_id.to_owned()], "{args:?}");
    assert!(bench.read("auto", "claude.args").is_empty());
    assert!(!text.contains("exited successfully"), "no post-run menu without a terminal: {text}");
}

#[test]
fn yolo_adds_the_harness_flag_without_a_prompt_off_a_terminal() {
    let tmp = tempfile::tempdir().unwrap();
    let _engine = start(tmp.path(), &["--keep-alive", "--import-delay-ms", "60000"]);
    let bench = bench(tmp.path(), false);
    let output = bench.run("yolo", &["claude", "--yolo", "--model", "x"], &[]);
    let text = stderr(&output);
    assert!(output.status.success(), "{text}");
    assert!(!text.contains("Proceed?"), "{text}");
    let args = bench.args("yolo", "claude.args");
    assert!(args.iter().any(|a| a == "--dangerously-skip-permissions"), "{args:?}");
    assert!(!args.iter().any(|a| a == "--yolo"), "the wrapper flag never reaches the agent: {args:?}");
    let output = bench.run("yolo-codex", &["--yolo", "codex"], &[]);
    assert!(output.status.success(), "{}", stderr(&output));
    assert!(bench.args("yolo-codex", "codex.args").iter().any(|a| a == "--dangerously-bypass-approvals-and-sandbox"));
}

#[test]
fn a_linked_claude_session_running_in_the_background_is_attached() {
    let tmp = tempfile::tempdir().unwrap();
    let _engine = start(tmp.path(), &["--keep-alive", "--import-delay-ms", "60000"]);
    let bench = bench(tmp.path(), false);
    let first = bench.run("first", &["claude"], &[("FAKE_BG", "1")]);
    assert!(first.status.success(), "{}", stderr(&first));
    let session = bench.args("first", "claude.args")[1].clone();
    let second = bench.run("second", &["claude"], &[]);
    let text = stderr(&second);
    assert!(second.status.success(), "{text}");
    let attach_id = format!("bg{}", &session[..4]);
    assert_eq!(bench.args("second", "claude.args"), ["attach".to_owned(), attach_id.clone()], "no kit flags on an attach");
    assert!(text.contains(&format!("attaching to it (`claude attach {attach_id}`)")), "{text}");
    let listed = bench.args("second", "claude.agents.args");
    assert_eq!(listed[..3], ["agents".to_owned(), "--json".to_owned(), "--cwd".to_owned()]);
}

#[test]
fn grok_gets_the_workstream_packet_as_rules() {
    let tmp = tempfile::tempdir().unwrap();
    let _engine = start(tmp.path(), &["--keep-alive", "--import-delay-ms", "60000"]);
    let bench = bench(tmp.path(), false);
    let first = bench.run("claude", &["claude"], &[]);
    assert!(saved(&first) > 0, "{}", stderr(&first));
    let output = bench.run("grok", &["grok"], &[]);
    let text = stderr(&output);
    assert!(output.status.success(), "{text}");
    let args = bench.args("grok", "grok.args");
    let rules = args.iter().position(|a| a == "--rules").unwrap_or_else(|| panic!("no --rules: {args:?}\n{text}"));
    assert!(args[rules + 1..].join("\n").contains("tokenizer"), "the packet carries Claude's work: {args:?}");
    assert!(!args.iter().any(|a| a == "--settings" || a == "-c"), "no kit flags for Grok: {args:?}");
    let again = bench.run("grok2", &["grok", "--rules=mine"], &[]);
    assert!(stderr(&again).contains("--rules was supplied natively"), "{}", stderr(&again));
}

#[test]
fn opencode_is_launched_in_the_dialect_its_version_names() {
    let tmp = tempfile::tempdir().unwrap();
    let _engine = start(tmp.path(), &["--keep-alive", "--import-delay-ms", "60000"]);
    let bench = bench(tmp.path(), false);
    let output = bench.run("v2", &["opencode"], &[("FAKE_VERSION", "opencode 2.1.0")]);
    let text = stderr(&output);
    assert!(output.status.success(), "{text}");
    assert!(!bench.read("v2", "opencode.args").is_empty(), "the resolved executable ran: {text}");
    let refused = bench.run("bad", &["opencode"], &[("FAKE_VERSION", "nonsense")]);
    assert!(!refused.status.success());
    assert!(stderr(&refused).contains("could not determine the OpenCode major"), "{}", stderr(&refused));
}
