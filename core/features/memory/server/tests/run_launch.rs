//! `cadex-memory run` around the agent (plan 22 phase E, 2026-11-16): the
//! launch environment from a profile of upstream's config and the flags,
//! the degraded launch without the engine and its recovery on the next run,
//! and the re-run inside a fake ai-jail that still reaches memory.sock. The
//! fakes are tests/common/bench.rs's; never a real agent or ai-jail.

mod common;

use common::bench::{bench, env_value, saved, stderr};
use common::start;

#[test]
fn a_profile_then_the_env_file_then_env_flags_reach_the_agent() {
    let tmp = tempfile::tempdir().unwrap();
    let _engine = start(tmp.path(), &["--keep-alive", "--import-delay-ms", "60000"]);
    let bench = bench(tmp.path(), false);
    let config = bench.dir.join("ai-memory");
    std::fs::create_dir_all(&config).unwrap();
    std::fs::write(config.join("config.toml"),
        "[run.profiles.work.env]\nA_VAR = 'profile'\nB_VAR = 'profile'\nC_VAR = 'profile'\n").unwrap();
    let env_file = bench.dir.join("launch.env");
    std::fs::write(&env_file, "# comment\nB_VAR=file\nC_VAR=file\n").unwrap();
    let output = bench.run("profile", &["--profile", "work", "--env-file", env_file.to_str().unwrap(), "--env", "C_VAR=flag",
        "claude"], &[]);
    assert!(output.status.success(), "{}", stderr(&output));
    let env = bench.read("profile", "claude.env");
    assert_eq!(env_value(&env, "A_VAR").as_deref(), Some("profile"));
    assert_eq!(env_value(&env, "B_VAR").as_deref(), Some("file"));
    assert_eq!(env_value(&env, "C_VAR").as_deref(), Some("flag"));
    let unknown = bench.run("unknown", &["--profile", "home", "claude"], &[]);
    assert!(stderr(&unknown).contains("unknown run profile \"home\"; defined profiles: work"), "{}", stderr(&unknown));
    assert!(bench.read("unknown", "claude.args").is_empty());
}

#[test]
fn without_the_engine_the_agent_runs_and_the_next_run_recovers_it() {
    let tmp = tempfile::tempdir().unwrap();
    let bench = bench(tmp.path(), false);
    let no_engine = [("CADEX_MEMORY_BIN", "/usr/bin/false")];
    let refused = bench.run("refused", &["--require-server", "claude"], &no_engine);
    assert!(!refused.status.success());
    assert!(stderr(&refused).contains("the agent was not started"), "{}", stderr(&refused));
    assert!(bench.read("refused", "claude.args").is_empty());

    let offline = bench.run("offline", &["claude"], &no_engine);
    let text = stderr(&offline);
    assert!(offline.status.success(), "{text}");
    assert!(text.contains("WARNING: the memory engine at") && text.contains("recorded for recovery"), "{text}");
    let env = bench.read("offline", "claude.env");
    assert!(env_value(&env, "AI_MEMORY_RUN_ID").is_none(), "no run exists without the engine");
    assert_eq!(bench.args("offline", "claude.args")[2..], ["--settings", "/kit/settings.json"]);
    let journal = bench.dir.join("data/run/recovery-journal.json");
    assert!(std::fs::read_to_string(&journal).unwrap().contains("degraded-run"));

    let _engine = start(tmp.path(), &["--keep-alive", "--import-delay-ms", "60000"]);
    let next = bench.run("next", &["codex"], &[]);
    let text = stderr(&next);
    assert!(next.status.success(), "{text}");
    let line = text.lines().find(|l| l.contains("recovered")).unwrap_or_else(|| panic!("no recovery: {text}"));
    assert!(line.starts_with("ai-memory: recovered 1 journaled run(s) (") && !line.contains("(0 event(s))"), "{line}");
    assert!(!std::fs::read_to_string(&journal).unwrap().contains("degraded-run"), "the entry is cleared");
}

#[test]
fn jail_reruns_inside_ai_jail_and_the_jailed_run_reaches_the_engine() {
    let tmp = tempfile::tempdir().unwrap();
    let _engine = start(tmp.path(), &["--keep-alive", "--import-delay-ms", "60000"]);
    let bench = bench(tmp.path(), true);
    let output = bench.run("jail", &["--jail", "claude"], &[]);
    let text = stderr(&output);
    assert!(output.status.success(), "{text}");
    assert!(text.contains("ai-memory: re-running inside ai-jail"), "{text}");
    let jail_args = bench.args("jail", "jail.args");
    let socket = bench.socket().to_string_lossy().into_owned();
    let mapped = jail_args.windows(2).any(|w| w[0] == "--rw-map" && w[1] == socket);
    assert!(mapped, "memory.sock is mapped into the jail: {jail_args:?}");
    for name in ["CADEX_SESSION_TOKEN", "CADEX_MEMORY_SOCKET", "CLAUDE_CONFIG_DIR"] {
        assert!(jail_args.windows(2).any(|w| w[0] == "--env" && w[1] == name), "{name} forwarded: {jail_args:?}");
    }
    let separator = jail_args.iter().position(|a| a == "--").unwrap();
    assert_eq!(jail_args[separator + 1], env!("CARGO_BIN_EXE_cadex-memory"));
    assert_eq!(jail_args[separator + 2], "run");
    let jail_env = bench.read("jail", "jail.env");
    assert_eq!(env_value(&jail_env, "CADEX_MEMORY_SOCKET").as_deref(), Some(socket.as_str()));
    let agent_env = bench.read("jail", "claude.env");
    assert_eq!(env_value(&agent_env, "FAKE_JAILED").as_deref(), Some("1"), "the agent ran inside the jail: {text}");
    assert!(env_value(&agent_env, "AI_MEMORY_HOOK_URL").is_none());
    assert!(env_value(&agent_env, "AI_MEMORY_RUN_ID").is_some(), "the jailed launcher opened a run");
    assert!(saved(&output) > 0, "{text}");
}
