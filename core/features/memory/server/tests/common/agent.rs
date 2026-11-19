//! A fake `claude` for the memory agent's tests (plan 22 phase G,
//! 2026-11-16): a shell script, named in agent.json's `claude`, that records
//! each run (argv NUL-separated, environment, working folder and what is in
//! it, stdin) in a folder of its own and prints a canned
//! `--output-format json` result chosen by the schema the request carries.
//! No real `claude`, no network.

use std::collections::HashMap;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

use super::{ok, query};

/// The cost every fake call reports.
pub const COST: f64 = 0.0123;
pub const VERSION: &str = "9.9.9 (Claude Code)";

pub struct FakeClaude {
    pub exe: PathBuf,
    pub log: PathBuf,
}

/// One recorded run.
#[derive(Debug)]
pub struct Call {
    pub argv: Vec<String>,
    pub env: HashMap<String, String>,
    pub cwd: String,
    pub cwd_entries: String,
    pub stdin: String,
}

fn result(text: &str) -> String {
    serde_json::json!({
        "type": "result", "subtype": "success", "is_error": false, "result": text,
        "total_cost_usd": COST, "session_id": "fake-session",
        "modelUsage": {"claude-haiku-fake": {"inputTokens": 10, "outputTokens": 5}},
        "usage": {"input_tokens": 10, "output_tokens": 5},
    })
    .to_string()
}

/// The canned answers, by the title of the schema in the request.
fn answers() -> Vec<(&'static str, serde_json::Value)> {
    vec![
        ("ConsolidatedPage", serde_json::json!({
            "title": "Agent consolidated page",
            "body_markdown": "# Agent consolidated page\n\nThe fake agent summarized the session.\n",
            "tags": ["fake"],
        })),
        ("BootstrapBatch", serde_json::json!({
            "pages": [{"path": "decisions/0001-use-sqlite.md", "title": "Use SQLite",
                       "body_markdown": "The project chose SQLite for the cache.", "tags": []}],
            "rationale": "fake bootstrap",
        })),
        ("AutoImproveLlmResponse", serde_json::json!({
            "summary": "one gotcha",
            "proposals": [{
                "operation": "create_or_update", "path": "gotchas/wal-lock.md", "title": "WAL lock gotcha",
                "kind": "gotcha", "confidence": 0.9, "rationale": "The session hit it twice.",
                "evidence": [{"page": "observations", "quote": "the WAL lock"}],
                "body_markdown": "# WAL lock gotcha\n\nCheckpoint the WAL before copying the database.\n",
                "edit_mode": "full_page",
            }],
            "rejected_candidates": [],
        })),
    ]
}

/// Write the script and its answers under `dir`.
pub fn fake_claude(dir: &Path) -> FakeClaude {
    let root = dir.join("fake-claude");
    let log = root.join("calls");
    std::fs::create_dir_all(&log).unwrap();
    let mut branches = String::new();
    for (title, answer) in answers() {
        let file = root.join(format!("{title}.json"));
        std::fs::write(&file, result(&answer.to_string())).unwrap();
        branches.push_str(&format!(
            "elif grep -q '\"title\":\"{title}\"' \"$d/stdin\"; then cat '{}'\n",
            file.display()
        ));
    }
    std::fs::write(root.join("other.json"), result("{}")).unwrap();
    let script = format!(
        "#!/bin/sh\n\
         if [ \"$1\" = \"--version\" ]; then echo '{VERSION}'; exit 0; fi\n\
         d=$(mktemp -d '{log}/call.XXXXXX')\n\
         for a in \"$@\"; do printf '%s\\0' \"$a\"; done > \"$d/argv\"\n\
         env > \"$d/env\"\n\
         pwd > \"$d/cwd\"\n\
         ls -A > \"$d/cwd_entries\"\n\
         cat > \"$d/stdin\"\n\
         if false; then :\n\
         {branches}\
         else cat '{other}'\n\
         fi\n\
         touch \"$d/done\"\n",
        log = log.display(),
        other = root.join("other.json").display(),
    );
    let exe = root.join("claude");
    std::fs::write(&exe, script).unwrap();
    std::fs::set_permissions(&exe, std::fs::Permissions::from_mode(0o755)).unwrap();
    FakeClaude { exe, log }
}

impl FakeClaude {
    /// Every finished run.
    pub fn calls(&self) -> Vec<Call> {
        let mut out = Vec::new();
        for entry in std::fs::read_dir(&self.log).unwrap().flatten() {
            let d = entry.path();
            if !d.join("done").exists() {
                continue;
            }
            let read = |name: &str| std::fs::read_to_string(d.join(name)).unwrap_or_default();
            let argv = read("argv").split('\0').map(str::to_owned).collect::<Vec<_>>();
            let argv = argv[..argv.len().saturating_sub(1)].to_vec();
            let env = read("env").lines().filter_map(|l| l.split_once('=')).map(|(k, v)| (k.to_owned(), v.to_owned())).collect();
            out.push(Call { argv, env, cwd: read("cwd").trim().to_owned(), cwd_entries: read("cwd_entries"), stdin: read("stdin") });
        }
        out
    }

    /// The runs whose request carried the schema titled `title`.
    pub fn calls_for(&self, title: &str) -> Vec<Call> {
        self.calls().into_iter().filter(|c| c.stdin.contains(&format!("\"title\":\"{title}\""))).collect()
    }

    /// agent.json in `data`, with this fake as `claude`.
    pub fn configure(&self, data: &Path, fields: serde_json::Value) {
        let mut config = serde_json::json!({"claude": self.exe, "model": "haiku", "call_budget_usd": 0.25, "daily_budget_usd": 1.0});
        for (k, v) in fields.as_object().unwrap() {
            config[k] = v.clone();
        }
        std::fs::create_dir_all(data).unwrap();
        std::fs::write(data.join("agent.json"), config.to_string()).unwrap();
    }
}

/// The ledger's lines.
pub fn ledger(data: &Path) -> Vec<serde_json::Value> {
    let text = std::fs::read_to_string(data.join("agent").join("ledger.jsonl")).unwrap_or_default();
    text.lines().filter_map(|l| serde_json::from_str(l).ok()).collect()
}

// The sessions the agent tests drive (moved from tests/agent.rs, plan 35 D,
// so tests/agent_audit.rs drives them the same way).

/// The engine's arguments in the agent tests: up with no session, jobs soon.
pub const ARGS: &[&str] = &["--keep-alive", "--import-delay-ms", "100"];

pub fn hook(socket: &Path, event: &str, cwd: &str, session: &str, key: &str, body: serde_json::Value) {
    let qs = query(&[("event", event), ("agent", "claude-code"), ("cwd", cwd), ("session_id", session),
        ("project_strategy", "repo-root"), ("ingest_key", key)]);
    ok(socket, "POST", &format!("/hook?{qs}"), Some(&body.to_string())).unwrap_or_else(|| panic!("{event} refused"));
}

pub fn wait_for(what: &str, limit: Duration, mut done: impl FnMut() -> bool) {
    let deadline = Instant::now() + limit;
    while Instant::now() < deadline {
        if done() {
            return;
        }
        std::thread::sleep(Duration::from_millis(100));
    }
    panic!("timed out waiting for {what}");
}

pub fn at(ago_secs: i64) -> String {
    jiff::Timestamp::now().checked_sub(jiff::SignedDuration::from_secs(ago_secs)).unwrap().to_string()
}

/// A session with a prompt and `tools` edits; events `ago` seconds back,
/// 10 s apart, when given. Not ended.
pub fn work(socket: &Path, cwd: &str, id: &str, tools: usize, ago: Option<i64>) {
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
        let out = super::tool(socket, "memory_read_session_observations", serde_json::json!({
            "session_id": id, "workspace": "default", "project": "acme", "limit": 100}));
        out.matches("tool file: Edit").count() >= tools && out.contains("WAL lock")
    };
    wait_for("the events stored", Duration::from_secs(15), count);
}

pub fn end(socket: &Path, cwd: &str, id: &str, ago: Option<i64>) {
    let mut body = serde_json::json!({"session_id": id, "cwd": cwd, "hook_event_name": "SessionEnd", "reason": "exit"});
    if let Some(ago) = ago {
        body["occurred_at"] = at(ago).into();
    }
    hook(socket, "session-end", cwd, id, &format!("{id}-e"), body);
}

impl FakeClaude {
    /// Change the canned answer for the schema titled `title` (plan 35 G:
    /// proposals that cite paths); the script reads it at each run.
    pub fn answer(&self, title: &str, answer: serde_json::Value) {
        let file = self.exe.parent().unwrap().join(format!("{title}.json"));
        std::fs::write(file, result(&answer.to_string())).unwrap();
    }
}
