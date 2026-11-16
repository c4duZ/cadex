//! A bench for `cadex-memory run` (plan 22 phase E): fake agents on a
//! temporary PATH write transcripts where the workstream crate looks (a
//! temporary HOME and CLAUDE_CONFIG_DIR) and record their arguments and
//! environment; an optional fake `ai-jail` records how it was called and
//! runs the wrapped command with only the variables named by `--env`, as
//! ai-jail does. Never a real agent, never the owner's folders.

#![allow(dead_code)]

use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Output};

use super::{TOKEN, repo};

/// Claude Code: one prompt (`$FAKE_WORD`) and one reply in the session the
/// arguments name; `$FAKE_BG` marks it a background session; `agents`
/// lists every session of the checkout as a live background one (attach id
/// `bg` + first 4 characters); `attach` only records.
const FAKE_CLAUDE: &str = r#"#!/bin/sh
cwd=$(pwd -P)
dir="$CLAUDE_CONFIG_DIR/projects/$(printf '%s' "$cwd" | sed 's/[^A-Za-z0-9]/-/g')"
if [ "$1" = agents ]; then
  printf '%s\n' "$@" > "$FAKE_LOG/claude.agents.args"
  printf '['; sep=""
  for f in "$dir"/*.jsonl; do s=$(basename "$f" .jsonl); a=$(printf '%s' "$s" | cut -c1-4)
    printf '%s{"id":"bg%s","sessionId":"%s","kind":"background","cwd":"%s"}' "$sep" "$a" "$s" "$cwd"; sep=","; done
  printf ']\n'; exit 0
fi
env > "$FAKE_LOG/claude.env"
printf '%s\n' "$@" > "$FAKE_LOG/claude.args"
[ "$1" = attach ] && exit 0
id=""; prev=""
for a in "$@"; do case "$prev" in --session-id|--resume) id="$a";; esac; prev="$a"; done
mkdir -p "$dir"
n=$$
printf '{"type":"user","uuid":"u%s","sessionId":"%s","cwd":"%s","timestamp":"2026-11-16T10:00:00Z","message":{"role":"user","content":"please study the %s module"}}\n' "$n" "$id" "$cwd" "$FAKE_WORD" >> "$dir/$id.jsonl"
printf '{"type":"assistant","uuid":"a%s","sessionId":"%s","cwd":"%s","timestamp":"2026-11-16T10:00:01Z","message":{"role":"assistant","content":[{"type":"text","text":"studied %s"}]}}\n' "$n" "$id" "$cwd" "$FAKE_WORD" >> "$dir/$id.jsonl"
if [ -n "$FAKE_BG" ]; then printf '{"type":"system","sessionKind":"bg","sessionId":"%s","cwd":"%s"}\n' "$id" "$cwd" >> "$dir/$id.jsonl"; fi
if [ -n "$FAKE_GATE" ]; then while [ ! -e "$FAKE_GATE" ]; do sleep 0.1; done; fi
if [ -n "$FAKE_SLEEP" ]; then sleep "$FAKE_SLEEP"; fi
exit 0
"#;

/// Codex: copies the dossier and its mode, then writes a rollout under
/// `$HOME/.codex/sessions` (or appends to the resumed one).
const FAKE_CODEX: &str = r#"#!/bin/sh
env > "$FAKE_LOG/codex.env"
printf '%s\n' "$@" > "$FAKE_LOG/codex.args"
if [ -n "$AI_MEMORY_PREVIOUS_SESSION_HISTORY" ]; then
  cp "$AI_MEMORY_PREVIOUS_SESSION_HISTORY" "$FAKE_LOG/codex.history"
  stat -f %Lp "$AI_MEMORY_PREVIOUS_SESSION_HISTORY" > "$FAKE_LOG/codex.history.mode"
fi
id="00000000-0000-4000-8000-$(printf '%012d' $$)"
cwd=$(pwd -P)
day="$HOME/.codex/sessions/2026/11/16"
mkdir -p "$day"
f="$day/rollout-2026-11-16T10-00-00-$id.jsonl"
if [ "$1" = resume ]; then f=$(ls "$day"/*"$2".jsonl); else
printf '{"type":"session_meta","payload":{"id":"%s","cwd":"%s"}}\n' "$id" "$cwd" > "$f"; fi
printf '{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"continue the %s work"}]}}\n' "$FAKE_WORD" >> "$f"
printf '{"type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"continued"}]}}\n' >> "$f"
exit 0
"#;

/// Grok and OpenCode: record the call (`--version` answers `$FAKE_VERSION`).
const FAKE_RECORDER: &str = r#"#!/bin/sh
name=$(basename "$0")
if [ "$1" = --version ]; then echo "$FAKE_VERSION"; exit 0; fi
env > "$FAKE_LOG/$name.env"
printf '%s\n' "$@" > "$FAKE_LOG/$name.args"
exit 0
"#;

/// ai-jail: `--help` lists the flags, `--dry-run` passes, no wrapper
/// contract; otherwise it records its argv and environment and runs what
/// follows `--` with a cleared environment holding only the `--env` names
/// (plus what the fakes need, and `FAKE_JAILED`: sh drops `PS1`), and
/// `PS1` as ai-jail sets it on macOS.
const FAKE_AI_JAIL: &str = r#"#!/bin/sh
case "$1" in
  --help) echo "--network --agent-state --no-save-config --env --map / --rw-map --ssh / --no-ssh"; exit 0;;
  --dry-run) exit 0;;
  capabilities) exit 1;;
esac
printf '%s\n' "$@" > "$FAKE_LOG/jail.args"
env > "$FAKE_LOG/jail.env"
names=""; prev=""
while [ $# -gt 0 ]; do
  if [ "$1" = "--" ]; then shift; break; fi
  if [ "$prev" = "--env" ]; then names="$names $1"; fi
  prev="$1"; shift
done
pairs=""
for n in $names; do eval "v=\${$n}"; pairs="$pairs $n=$v"; done
exec env -i "PS1=(jail) " "FAKE_JAILED=1" "PATH=$PATH" "HOME=$HOME" "TMPDIR=$TMPDIR" "FAKE_LOG=$FAKE_LOG" "FAKE_WORD=$FAKE_WORD" $pairs "$@"
"#;

pub struct Bench {
    pub dir: PathBuf,
    pub project: PathBuf,
}

fn install(bin: &Path, name: &str, body: &str) {
    std::fs::write(bin.join(name), body).unwrap();
    std::fs::set_permissions(bin.join(name), std::fs::Permissions::from_mode(0o755)).unwrap();
}

/// The fake agents (and, with `jail`, the fake ai-jail) in `dir/bin`.
pub fn bench(dir: &Path, jail: bool) -> Bench {
    let bin = dir.join("bin");
    std::fs::create_dir_all(&bin).unwrap();
    for (name, body) in [("claude", FAKE_CLAUDE), ("codex", FAKE_CODEX), ("grok", FAKE_RECORDER), ("opencode", FAKE_RECORDER)] {
        install(&bin, name, body);
    }
    if jail {
        install(&bin, "ai-jail", FAKE_AI_JAIL);
    }
    std::fs::create_dir_all(dir.join("tmp")).unwrap();
    let project = repo(dir, "acme").canonicalize().unwrap();
    Bench { dir: dir.canonicalize().unwrap(), project }
}

impl Bench {
    pub fn socket(&self) -> PathBuf {
        self.dir.join("m.sock")
    }

    /// `cadex-memory run <args...>` in the project, logging to `log`.
    pub fn command(&self, log: &str, args: &[&str], extra_env: &[(&str, &str)]) -> Command {
        let log = self.dir.join(log);
        std::fs::create_dir_all(&log).unwrap();
        let mut command = Command::new(env!("CARGO_BIN_EXE_cadex-memory"));
        command
            .arg("run")
            .args(["--socket", self.socket().to_str().unwrap()])
            .args(["--data-dir", self.dir.join("data").to_str().unwrap()])
            .args(["--claude-kit-arg", "--settings", "--claude-kit-arg", "/kit/settings.json"])
            .args(["--codex-kit-arg", "-c", "--codex-kit-arg", "mcp_servers.cadex.command=cadex"])
            .args(args)
            .current_dir(&self.project)
            .env_clear()
            .env("PATH", format!("{}:/usr/bin:/bin", self.dir.join("bin").display()))
            .env("HOME", &self.dir)
            .env("TMPDIR", self.dir.join("tmp"))
            .env("AI_MEMORY_DATA_DIR", self.dir.join("ai-memory"))
            .env("CLAUDE_CONFIG_DIR", self.dir.join("claude-account"))
            .env("CADEX_SESSION_TOKEN", TOKEN)
            .env("AI_MEMORY_HOOK_URL", "http://stale.invalid")
            .env("FAKE_LOG", &log)
            .env("FAKE_WORD", "tokenizer")
            .envs(extra_env.iter().copied());
        command
    }

    pub fn run(&self, log: &str, args: &[&str], extra_env: &[(&str, &str)]) -> Output {
        self.command(log, args, extra_env).output().unwrap()
    }

    pub fn read(&self, log: &str, file: &str) -> String {
        std::fs::read_to_string(self.dir.join(log).join(file)).unwrap_or_default()
    }

    pub fn args(&self, log: &str, file: &str) -> Vec<String> {
        self.read(log, file).lines().map(str::to_owned).collect()
    }
}

pub fn stderr(output: &Output) -> String {
    String::from_utf8_lossy(&output.stderr).into_owned()
}

/// The `N` of "saved N new event(s)".
pub fn saved(output: &Output) -> usize {
    let text = stderr(output);
    let line = text.lines().find(|l| l.contains("new event(s)")).unwrap_or_else(|| panic!("no saved line: {text}"));
    line.split("saved ").nth(1).and_then(|r| r.split(' ').next()).and_then(|n| n.parse().ok()).unwrap()
}

pub fn env_value(env: &str, name: &str) -> Option<String> {
    env.lines().find_map(|l| l.strip_prefix(&format!("{name}=")).map(str::to_owned))
}
