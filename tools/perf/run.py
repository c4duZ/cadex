#!/usr/bin/env python3
"""Cadex's weight budget (`make perf`): runs the release app and the core's
indexes through the situations that once made it heavy, and fails when one
goes over its limit. Mac only; takes about five minutes.

Each scenario starts a test Cadex (CADEX_BACKGROUND=1, its own spaces file,
so the owner's are untouched) whose "shell" runs a load (loadshell.sh), and
samples its memory (footprint) and CPU (ps). The indexes are measured
through the C API by index_probe.c, compiled here against libcadex.a.

The limits leave room over what was measured on 2026-10-20 (in the comment
of each), so a real regression fails and noise does not. Raise one only
with a reason written next to it.
"""
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import time

import plan19
import plan20
import plan21
import plan22
import plan23
import plan24
from plan22_engine import engine_running

ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
HERE = pathlib.Path(__file__).resolve().parent
APP = ROOT / "dist/Cadex.app"
EXE = APP / "Contents/MacOS/Cadex"
HOME = pathlib.Path.home()

from limits import LIMITS
# Themes the switch scenario goes through: official, tweakcn and base16.
SWITCH_THEMES = ["caffeine", "catppuccin", "github-high-contrast", "gruvbox-soft", "tokyonight-storm", "0x96f", "nord"]


def footprint_mb(pid):
    out = subprocess.run(["footprint", "-p", str(pid)], capture_output=True, text=True).stdout
    for line in out.splitlines():
        words = line.split()
        if "Footprint:" in words:
            i = words.index("Footprint:")
            value, unit = float(words[i + 1]), words[i + 2]
            return value / 1024 if unit == "KB" else value * 1024 if unit == "GB" else value
    return None


def cpu_seconds(pid):
    """CPU time used so far. ps's %cpu is a slow-decaying average that
    still carried the launch's cost: idle read 2.5 % where the app used
    0.1 % (2026-10-20). Differences of this are exact."""
    out = subprocess.run(["ps", "-o", "time=", "-p", str(pid)], capture_output=True, text=True).stdout.strip()
    if not out:
        return None
    minutes, seconds = out.split(":")
    return int(minutes) * 60 + float(seconds)


class TestApp:
    """A test Cadex with `load` in its terminal, opened on `folder` (None:
    no folder, the home one)."""

    def __init__(self, load, folder, seconds=20, settings=None, extra_env=None):
        self.dir = tempfile.mkdtemp(prefix="cadex-perf-")
        # Its own sockets and tokens (plan 19): never the owner's app.sock
        # nor terminal daemon, which every run took until 2026-11-15.
        self.sockets = f"{self.dir}/s"
        self.app_socket = f"{self.sockets}/app.sock"
        self.terminal_socket = f"{self.sockets}/terminal-1.sock"
        self.sessions_dir = f"{self.dir}/sessions"
        self.settings_file = pathlib.Path(self.dir) / "settings.json"
        self.settings_file.write_text(json.dumps(settings or {}))
        env = dict(os.environ, CADEX_BACKGROUND="1", CADEX_PROJECTS_FILE=f"{self.dir}/projects.json",
                   CADEX_SETTINGS_FILE=str(self.settings_file), CADEX_THEMES_DIR=f"{self.dir}/themes",
                   SHELL=str(HERE / "loadshell.sh"), CADEX_LOAD=load, CADEX_LOAD_SECONDS=str(seconds),
                   CADEX_SOCKETS_DIR=self.sockets, CADEX_SESSIONS_DIR=self.sessions_dir,
                   CADEX_TERMINAL_SOCKET=self.terminal_socket,
                   # Its own memory folder: the warm-up and the engine wrote
                   # the owner's real one until 2026-11-16 (plan 22).
                   CADEX_MEMORY_DIR=f"{self.dir}/memory",
                   **(extra_env or {}))
        args = [str(EXE)] + ([str(folder)] if folder else [])
        self.process = subprocess.Popen(args, env=env, cwd=str(folder or HOME),
                                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def sample(self, seconds, every=2):
        """(memory MB, CPU %) pairs over `seconds`, the CPU of each interval;
        stops if the app quits."""
        samples = []
        end = time.time() + seconds
        last_time, last_cpu = time.time(), cpu_seconds(self.process.pid) or 0
        while time.time() < end:
            time.sleep(every)
            if self.process.poll() is not None:
                raise RuntimeError(f"the app quit (status {self.process.returncode})")
            now, used = time.time(), cpu_seconds(self.process.pid) or 0
            samples.append((footprint_mb(self.process.pid) or 0, 100 * (used - last_cpu) / (now - last_time)))
            last_time, last_cpu = now, used
        return samples

    def close(self):
        self.process.terminate()
        try:
            self.process.wait(10)
        except subprocess.TimeoutExpired:
            self.process.kill()
        shutil.rmtree(self.dir, ignore_errors=True)


def scenario(name, load, folder, run, seconds=20, settings=None, extra_env=None):
    app = TestApp(load, folder, seconds, settings, extra_env)
    try:
        return run(app)
    finally:
        app.close()


def avg(values):
    return sum(values) / len(values) if values else 0


def measure_idle(app):
    app.sample(16)  # the first read of the project and the shell settle
    tail = app.sample(10)
    return {"idle_mb": max(m for m, _ in tail), "idle_cpu": avg([c for _, c in tail]),
            "daemon_off_running": 0 if plan19.daemon_pid(app.terminal_socket) is None else 1,
            # Plan 22: no agent session, no memory engine (the warm-up's ran and left).
            "memory_engine_running": 1 if engine_running(f"{app.dir}/memory") else 0}


def measure_flood(app):
    during = app.sample(20)
    after = app.sample(14)
    return {"flood_peak_mb": max(m for m, _ in during), "flood_after_mb": after[-1][0]}


def measure_tui(app):
    return {"tui_peak_mb": max(m for m, _ in app.sample(20))}


def measure_home(app):
    app.sample(14)
    tail = app.sample(10)
    return {"home_idle_mb": max(m for m, _ in tail), "home_idle_cpu": avg([c for _, c in tail])}


def measure_agent(app):
    app.sample(12)
    folder = ROOT / ".cadex-perf-agent"
    folder.mkdir(exist_ok=True)
    start, used = time.time(), cpu_seconds(app.process.pid) or 0
    try:
        for i in range(200):
            (folder / f"file{i % 5}.md").write_text(f"edit {i} {time.time()}\n")
            time.sleep(0.1)
    finally:
        shutil.rmtree(folder, ignore_errors=True)
    return {"agent_cpu": 100 * ((cpu_seconds(app.process.pid) or 0) - used) / (time.time() - start)}


def measure_theme_switch(app):
    """Settings edited by hand switch the theme 300 times: memory must not
    grow (explorer and status bar leaked ~10 MB per 100 switches until
    2026-10-20)."""
    def switch(count):
        for i in range(count):
            theme = SWITCH_THEMES[i % len(SWITCH_THEMES)]
            app.settings_file.write_text(json.dumps({"appearance": {"theme": theme, "mode": "dark" if (i // 7) % 2 else "light"}}))
            time.sleep(0.12)
    app.sample(12)
    # The first switches grow the app once (~25 MB: each theme's first
    # drawing), then it stays flat (2026-10-20); the growth after is the leak.
    switch(150)
    before = app.sample(4)[-1][0]
    switch(300)
    after = app.sample(4)[-1][0]
    return {"theme_switch_mb": after - before}


def measure_reading_flood(app):
    return {"reading_flood_peak_mb": max(m for m, _ in app.sample(20))}


def write_subagent_log(path):
    """A log shaped like the largest on the owner's Mac (34 MB, ~30 KB of
    replies, 2026-10-21): 150 short replies and tool calls, and 40 tool
    results of ~800 KB, the weight the tab must never hold."""
    with open(path, "w") as out:
        out.write(json.dumps({"type": "user", "message": {"content": "Read every screen and report"}}) + "\n")
        for i in range(150):
            out.write(json.dumps({"type": "assistant", "message": {"content": [
                {"type": "text", "text": f"Step {i}: " + "reading the next screen and comparing it. " * 4},
                {"type": "tool_use", "id": f"t{i}", "name": "Read", "input": {"file_path": f"/repo/screen{i}.swift"}}]}}) + "\n")
            if i % 4 == 0:
                out.write(json.dumps({"type": "user", "message": {"content": [
                    {"type": "tool_result", "tool_use_id": f"t{i}", "content": "x" * 800_000}]}}) + "\n")


def measure_subagent(app):
    """A subagent's conversation opened at 12 s and 48 s and closed 12 s
    after each by the app (CADEX_PERF_SUBAGENT_LOG). What stays is read 16
    to 22 s after each close: closing peaks at 130-140 MB for 1-2 s (the
    terminal shown again makes its canvas) and settles about 12 s later;
    read 4 to 7 s after, a close delayed by a loaded Mac put the peak in
    the window, +13 and +44 MB in the full run of 2026-11-16, +0 to +3 alone. Memory every 0.5 s,
    the median of each stretch so the 1 s jumps of switching tabs do not
    count. The first opening also loads the text system once; the second
    is what each one adds; after it closes nothing must stay. Since the
    hidden terminal lets go of its canvas (2026-10-21) the open numbers can
    be below zero: the tab costs less than the terminal it hides."""
    start = time.time()
    curve = []
    while time.time() - start < 83:
        if app.process.poll() is not None:
            raise RuntimeError(f"the app quit (status {app.process.returncode})")
        curve.append((time.time() - start, footprint_mb(app.process.pid) or 0))
        time.sleep(0.5)

    def median(begin, end):
        values = sorted(m for t, m in curve if begin <= t <= end)
        return values[len(values) // 2] if values else 0
    base, first, closed, second, after = median(7, 11), median(17, 23), median(40, 46), median(53, 59), median(76, 82)
    print(f"    base {base:.0f} MB, first open {first:.0f}, closed {closed:.0f}, second open {second:.0f}, closed {after:.0f}")
    return {"subagent_first_mb": first - base, "subagent_open_mb": second - closed, "subagent_closed_mb": after - closed}


def measure_tabs(app, count=5):
    """`count` more terminal tabs opened by the app (CADEX_PERF_TABS) from
    12 s, one a second, then back to the first: what each one adds, hidden."""
    start = time.time()
    curve = []
    while time.time() - start < 25 + count:
        if app.process.poll() is not None:
            raise RuntimeError(f"the app quit (status {app.process.returncode})")
        curve.append((time.time() - start, footprint_mb(app.process.pid) or 0))
        time.sleep(0.5)
    values = lambda begin, end: sorted(m for t, m in curve if begin <= t <= end)
    base, after = values(7, 11), values(19 + count, 25 + count)
    base, after = base[len(base) // 2], after[len(after) // 2]
    print(f"    base {base:.0f} MB, with {count} more tabs {after:.0f}")
    return {"terminal_tab_mb": (after - base) / count}


def write_agents_home(home, pid):
    """Three accounts with a live session each (`pid`, a process that waits)
    and three SSH hosts on this Mac, none listening: what the all-on
    scenario reads (plan 17, phase F)."""
    def write(path, text):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as out:
            out.write(text)
    for i, folder in enumerate([".claude", ".claude-work", ".claude-side"]):
        config = f"{home}/.claude.json" if folder == ".claude" else f"{home}/{folder}/.claude.json"
        write(config, json.dumps({"oauthAccount": {"organizationName": f"Perf {i}"}}))
        write(f"{home}/{folder}/sessions/{i}.json", json.dumps({
            "pid": pid, "sessionId": f"perf-{i}", "cwd": str(ROOT), "name": f"perf-{i}",
            "status": "busy" if i == 0 else "idle", "statusUpdatedAt": int(time.time() * 1000)}))
    write(f"{home}/.ssh/config", "".join(f"Host perf{i}\n  HostName 127.0.0.1\n  Port {9 + i}\n" for i in range(3)))


def write_history_home(home):
    """Plan 18's accounts: the default one, ~/.claude-work and one Cadex
    made (linked to ~/.claude's settings and skills), with 200 transcripts in
    Claude Code's format among them, tool results and API requests included."""
    def write(path, text):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as out:
            out.write(text)
    write(f"{home}/.claude/settings.json", "{}")
    write(f"{home}/.claude/skills/perf/SKILL.md", "perf")
    managed = f"{home}/Library/Application Support/Cadex/accounts/perf"
    os.makedirs(managed, exist_ok=True)
    for name in ["settings.json", "skills"]:
        os.symlink(f"{home}/.claude/{name}", f"{managed}/{name}")
    dirs = [f"{home}/.claude", f"{home}/.claude-work", managed]
    for i, folder in enumerate(dirs):
        config = f"{home}/.claude.json" if i == 0 else f"{folder}/.claude.json"
        write(config, json.dumps({"oauthAccount": {"organizationName": f"Perf {i}", "accountUuid": f"u{i}"}}))
    project = "-" + "".join(c if c.isalnum() else "-" for c in str(ROOT))[1:]
    filler = "lorem ipsum dolor sit amet " * 40
    for n in range(200):
        sid = f"00000000-0000-4000-8000-{n:012d}"
        lines = [json.dumps({"type": "ai-title", "aiTitle": f"Perf conversation {n}", "sessionId": sid})]
        for turn in range(12):
            at = f"2026-11-14T{10 + turn % 10:02d}:{n % 60:02d}:00Z"
            base = {"sessionId": sid, "cwd": str(ROOT), "gitBranch": "main", "timestamp": at}
            lines.append(json.dumps({**base, "type": "user", "message": {"role": "user", "content": f"request {turn} of {n}"}}))
            lines.append(json.dumps({**base, "type": "assistant", "message": {"role": "assistant", "content": [{"type": "text", "text": filler}]}}))
            lines.append(json.dumps({**base, "type": "user", "toolUseResult": {"stdout": filler * 3},
                                     "message": {"role": "user", "content": [{"type": "tool_result", "tool_use_id": "t", "content": filler * 3}]}}))
            lines.append(json.dumps({"type": "api-request-blob", "sessionId": sid, "message": filler * 2}))
        write(f"{dirs[n % 3]}/projects/{project}/{sid}.jsonl", "\n".join(lines) + "\n")


def history_scenario(open_page):
    """History open or closed over plan 18's accounts and transcripts."""
    home = tempfile.mkdtemp(prefix="cadex-perf-history-")
    try:
        write_history_home(home)
        first = ["agent-history", "files"] if open_page else ["files", "agent-history"]
        settings = {"sidebar": {"items": first + ["git", "agents", "accounts"]}}
        env = {"CADEX_PERF_HOME": home} | ({"CADEX_PERF_SIDEBAR": "agent-history"} if open_page else {})
        found = scenario("history", "idle", ROOT, measure_idle, settings=settings, extra_env=env)
        key = "history_open" if open_page else "history_closed"
        index = os.path.exists(f"{home}/Library/Application Support/Cadex/history.sqlite")
        print(f"    {found['idle_mb']:.0f} MB, index file {'made' if index else 'not made'}")
        out = {f"{key}_mb": found["idle_mb"], f"{key}_cpu": found["idle_cpu"]}
        # Open, the index must be made (else the page never showed); closed, never.
        out[f"{key}_index_wrong"] = 0 if index == open_page else 1
        return out
    finally:
        shutil.rmtree(home, ignore_errors=True)


ALL_ON = {"sidebar": {"items": ["agents", "files", "git", "accounts"]},
          "statusBar": {"left": ["folder", "branch", "terminals", "agents", "usage"],
                        "right": ["ports", "ssh", "ram", "cpu", "cadexMemory", "environment"]}}


def all_on_scenario():
    """Every status bar item, the Agents page open, three accounts and
    sessions and three SSH hosts: at most 10% over the idle scenario and
    the same CPU (plan 17, phase F)."""
    home = tempfile.mkdtemp(prefix="cadex-perf-home-")
    waiter = subprocess.Popen(["sleep", "120"])
    try:
        write_agents_home(home, waiter.pid)
        found = scenario("all-on", "idle", ROOT, measure_idle, settings=ALL_ON,
                         extra_env={"CADEX_PERF_HOME": home, "CADEX_PERF_SIDEBAR": "agents"})
        return {"all_on_mb": found["idle_mb"], "all_on_cpu": found["idle_cpu"]}
    finally:
        waiter.kill()
        shutil.rmtree(home, ignore_errors=True)


def subagent_scenario():
    folder = tempfile.mkdtemp(prefix="cadex-perf-log-")
    log = os.path.join(folder, "agent-perf.jsonl")
    try:
        write_subagent_log(log)
        return scenario("subagent", "idle", ROOT, measure_subagent, seconds=90, extra_env={"CADEX_PERF_SUBAGENT_LOG": log})
    finally:
        shutil.rmtree(folder, ignore_errors=True)


def build_probe():
    probe = pathlib.Path(tempfile.mkdtemp(prefix="cadex-probe-")) / "index_probe"
    subprocess.run(["clang", "-O2", "-I", str(ROOT / "core/include"), "-o", str(probe), str(HERE / "index_probe.c"),
                    str(ROOT / "core/zig-out/lib/libcadex.a"), "-lc++", "-framework", "CoreServices",
                    "-framework", "CoreFoundation"], check=True)
    return probe


def run_probe(probe, kind, root, focus, needle):
    out = subprocess.run([str(probe), kind, str(root), str(focus), needle], capture_output=True, text=True, timeout=300).stdout
    values = dict(pair.split("=") for pair in out.split())
    return {k: float(v) for k, v in values.items()}


def measure_indexes():
    probe = build_probe()
    try:
        files_home = run_probe(probe, "files", HOME, ROOT, "FolderFollow")
        notes_home = run_probe(probe, "notes", HOME, ROOT / "docs/spec", "docs/spec/search.md")
        files_repo = run_probe(probe, "files", ROOT, ROOT, "FolderFollow")
    finally:
        shutil.rmtree(probe.parent, ignore_errors=True)
    results = {"files_home_s": files_home["seconds"], "files_home_mb": files_home["mb"],
               "notes_home_s": notes_home["seconds"], "notes_home_mb": notes_home["mb"],
               "files_repo_s": files_repo["seconds"]}
    missing = [name for name, r in [("⌘P", files_home), ("notes", notes_home), ("⌘P (repo)", files_repo)] if not r["found"]]
    return results, missing


def main():
    if not EXE.exists():
        print("dist/Cadex.app not found: run `make package` first (make perf does)")
        return 1
    results = {"app_mb": sum(f.stat().st_size for f in APP.rglob("*") if f.is_file()) / 1048576}
    steps = [("one terminal, idle, in a project", lambda: scenario("idle", "idle", ROOT, measure_idle)),
             ("a program flooding the terminal", lambda: scenario("flood", "flood", ROOT, measure_flood)),
             ("a TUI redrawing the screen", lambda: scenario("tui", "tui", ROOT, measure_tui)),
             ("the home folder as the workspace", lambda: scenario("home", "idle", None, measure_home)),
             ("an agent saving files", lambda: scenario("agent", "idle", ROOT, measure_agent)),
             ("switching themes 300 times", lambda: scenario("themes", "idle", ROOT, measure_theme_switch)),
             ("everything of plan 17 on: every status bar item, Agents open, accounts, hosts", all_on_scenario),
             ("a subagent's 34 MB conversation, opened and closed", subagent_scenario),
             ("plan 18: three accounts, 200 conversations, History open", lambda: history_scenario(True)),
             ("plan 18: the same with History closed", lambda: history_scenario(False)),
             ("five more terminal tabs", lambda: scenario("tabs", "idle", ROOT, measure_tabs, extra_env={"CADEX_PERF_TABS": "5"})),
             ("plan 19: ten terminals kept by the daemon, with the window and with the app killed",
              lambda: plan19.kept_scenario(sys.modules[__name__])),
             ("plan 19: five sessions sending hooks every second", lambda: plan19.hooks_scenario(sys.modules[__name__])),
             ("plan 20: the agent tools off", lambda: plan20.off_scenario(sys.modules[__name__])),
             ("plan 20: a fake agent, 100 snapshots and 100 clicks in the preview", lambda: plan20.browser_scenario(sys.modules[__name__])),
             ("plan 21: a review of 50 files, scrolled, with comments and 200 edits", lambda: plan21.review_scenario(sys.modules[__name__])),
             ("plan 21: authorship off", lambda: plan21.off_scenario(sys.modules[__name__])),
             ("plan 22: the memory engine idle, a session open", lambda: plan22.idle_scenario(sys.modules[__name__])),
             ("plan 22: the embedding model loaded, then given back", lambda: plan22.model_scenario(sys.modules[__name__])),
             ("plan 22: a wiki of 2 000 pages and a session of 500 events", lambda: plan22.wiki_scenario(sys.modules[__name__])),
             ("plan 23: the tailnet's 20 machines, the SSH card's group open and closed", lambda: plan23.on_scenario(sys.modules[__name__])),
             ("plan 23: machines.tailscale off", lambda: plan23.off_scenario(sys.modules[__name__])),
             ("plan 24: races and runs off", lambda: plan24.off_scenario(sys.modules[__name__])),
             ("plan 24: a race of 3 and a run of 5 with fake agents, 6 working at once", lambda: plan24.on_scenario(sys.modules[__name__])),
             ("flooding with minimum contrast and ligatures", lambda: scenario(
                 "reading", "flood", ROOT, measure_reading_flood,
                 settings={"terminal": {"minimumContrast": 7, "fontFeatures": ["calt", "liga"]}}))]
    failures = []
    for title, step in steps:
        print(f"… {title}", flush=True)
        try:
            results.update(step())
        except RuntimeError as error:
            failures.append(f"{title}: {error}")
    print("… the indexes on the home folder and on this repository", flush=True)
    index_results, missing = measure_indexes()
    results.update(index_results)
    failures += [f"{name}: the focus's file was left out" for name in missing]

    print()
    # Plan 17's rule: all of it on weighs at most 10% over the app with it off.
    if "all_on_mb" in results and "idle_mb" in results:
        results["all_on_over_idle_pct"] = 100 * (results["all_on_mb"] - results["idle_mb"]) / results["idle_mb"]
    # Plan 18's rule: the History open or closed weighs at most 10% over idle.
    if "review_off_mb" in results and "idle_mb" in results:
        results["review_off_over_idle_mb"] = results["review_off_mb"] - results["idle_mb"]
    if "orch_off_mb" in results and "idle_mb" in results:
        results["orch_off_over_idle_mb"] = results["orch_off_mb"] - results["idle_mb"]
    if "tools_off_mb" in results and "idle_mb" in results:
        results["tools_off_over_idle_mb"] = results["tools_off_mb"] - results["idle_mb"]
    for key in ["history_open", "history_closed"]:
        if f"{key}_mb" in results and "idle_mb" in results:
            results[f"{key}_over_idle_pct"] = 100 * (results[f"{key}_mb"] - results["idle_mb"]) / results["idle_mb"]
    for key, limit in LIMITS.items():
        value = results.get(key)
        if value is None:
            continue
        ok = value <= limit
        if not ok:
            failures.append(f"{key}: {value:.1f} over the limit of {limit}")
        print(f"{'ok  ' if ok else 'FAIL'} {key:16} {value:8.1f}   (limit {limit})")
    print()
    if failures:
        print("\n".join(failures))
        return 1
    print("weight within the budget")
    return 0


if __name__ == "__main__":
    sys.exit(main())
