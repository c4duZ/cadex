//! `cadex-memory run` end to end (plan 22 phase E): Claude then Codex in
//! one workstream, the busy lease, the engine's lifetime. The fakes are
//! tests/common/bench.rs's; never a real agent, never the owner's folders.

mod common;

use std::path::Path;
use std::process::Command;
use std::time::{Duration, Instant};

use common::bench::{bench, env_value, saved, stderr};
use common::{TOKEN, request, start};

#[test]
fn claude_then_codex_continue_one_workstream_with_the_dossier() {
    let tmp = tempfile::tempdir().unwrap();
    let _engine = start(tmp.path(), &["--keep-alive", "--import-delay-ms", "60000"]);
    let bench = bench(tmp.path(), false);

    let first = bench.run("claude1", &["claude"], &[]);
    assert!(first.status.success(), "{}", stderr(&first));
    assert!(saved(&first) > 0, "{}", stderr(&first));
    let args: Vec<String> = bench.read("claude1", "claude.args").lines().map(str::to_owned).collect();
    assert_eq!(args[0], "--session-id");
    assert_eq!(&args[2..], ["--settings", "/kit/settings.json"], "only Claude's kit flags, after the plan");
    let claude_session = args[1].clone();
    let env = bench.read("claude1", "claude.env");
    assert!(env_value(&env, "AI_MEMORY_RUN_ID").is_some() && env_value(&env, "AI_MEMORY_WORKSTREAM_ID").is_some());
    assert!(env_value(&env, "AI_MEMORY_HOOK_URL").is_none(), "no hook URL, not even an inherited one");
    assert!(env_value(&env, "AI_MEMORY_PREVIOUS_SESSION_HISTORY").is_none());

    let second = bench.run("codex", &["codex"], &[("FAKE_WORD", "parser")]);
    assert!(second.status.success(), "{}", stderr(&second));
    assert!(saved(&second) > 0, "{}", stderr(&second));
    let args = bench.args("codex", "codex.args");
    assert_eq!(args, ["-c", "mcp_servers.cadex.command=cadex"], "only Codex's kit flags");
    let env = bench.read("codex", "codex.env");
    assert_eq!(env_value(&env, "AI_MEMORY_WORKSTREAM_ID"), env_value(&bench.read("claude1", "claude.env"), "AI_MEMORY_WORKSTREAM_ID"));
    let dossier = env_value(&env, "AI_MEMORY_PREVIOUS_SESSION_HISTORY").expect("a harness switch gets the dossier");
    let history = bench.read("codex", "codex.history");
    assert!(history.contains("please study the tokenizer module") && history.contains("untrusted"), "{history}");
    assert_eq!(bench.read("codex", "codex.history.mode").trim(), "600");
    assert!(!Path::new(&dossier).exists(), "the dossier is deleted when the run ends");

    let third = bench.run("claude2", &["claude"], &[("FAKE_WORD", "lexer")]);
    assert!(third.status.success(), "{}", stderr(&third));
    let args: Vec<String> = bench.read("claude2", "claude.args").lines().map(str::to_owned).collect();
    assert_eq!(args[..2], ["--resume".to_owned(), claude_session], "the workstream resumes its Claude session");
    let history = bench.read("claude2", "claude.env");
    assert!(env_value(&history, "AI_MEMORY_PREVIOUS_SESSION_HISTORY").is_some(), "back from Codex: its dossier");
}

#[test]
fn a_second_launcher_on_a_held_workstream_is_refused_after_the_short_wait() {
    let tmp = tempfile::tempdir().unwrap();
    let _engine = start(tmp.path(), &["--keep-alive", "--import-delay-ms", "60000"]);
    let bench = bench(tmp.path(), false);
    let gate = tmp.path().join("gate");
    let gate_text = gate.to_str().unwrap().to_owned();
    let mut holder = bench.command("holder", &["claude"], &[("FAKE_GATE", &gate_text)]).spawn().unwrap();
    let deadline = Instant::now() + Duration::from_secs(20);
    while bench.read("holder", "claude.args").is_empty() {
        assert!(Instant::now() < deadline, "the first agent never started");
        std::thread::sleep(Duration::from_millis(50));
    }
    let started = Instant::now();
    let refused = bench.run("second", &["claude"], &[]);
    let text = stderr(&refused);
    assert!(!refused.status.success(), "{text}");
    assert!(text.contains("another launcher owns this workstream") && text.contains("already active"), "{text}");
    assert!(started.elapsed() >= Duration::from_secs(4), "upstream's 5 s busy window, not interactive");
    assert!(bench.read("second", "claude.args").is_empty(), "the second agent was never started");
    std::fs::write(&gate, "").unwrap();
    assert!(holder.wait().unwrap().success());
}

#[test]
fn the_engine_stays_up_from_the_agents_end_to_the_finish() {
    let tmp = tempfile::tempdir().unwrap();
    // No --keep-alive: the engine leaves 3 s after its last session ends.
    let mut engine = start(tmp.path(), &["--import-delay-ms", "60000"]);
    let bench = bench(tmp.path(), false);
    // A session whose process ends at once: without the launcher's own pid,
    // the engine would leave while the agent below still runs.
    let mut short = Command::new("/bin/sleep").arg("0.5").spawn().unwrap();
    let path = format!("/hook?event=session-start&agent=claude-code&pid={}&session_id=s-short", short.id());
    request(&engine.socket, "POST", &path, Some("{\"session_id\":\"s-short\"}"), Some(TOKEN));
    short.wait().unwrap();
    let output = bench.run("slow", &["claude"], &[("FAKE_SLEEP", "5")]);
    assert!(output.status.success(), "{}", stderr(&output));
    assert!(saved(&output) > 0, "{}", stderr(&output));
    assert!(engine.exits_within(Duration::from_secs(10)), "the launcher's exit ends its registration");
}
