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

ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
HERE = pathlib.Path(__file__).resolve().parent
APP = ROOT / "dist/Cadex.app"
EXE = APP / "Contents/MacOS/Cadex"
HOME = pathlib.Path.home()

LIMITS = {
    "app_mb": 50,                 # 43 MB, universal (2026-10-20)
    "idle_mb": 100,               # ~78 MB with one terminal in a project
    "idle_cpu": 2.0,              # ~0 %
    "flood_peak_mb": 200,         # ~147 MB while `yes` floods
    "flood_after_mb": 130,        # ~100 MB once it stops (10 000 history lines kept)
    "tui_peak_mb": 200,           # ~147 MB redrawing the whole screen
    "home_idle_mb": 110,          # 79 MB with the home folder as the workspace
    "home_idle_cpu": 3.0,         # ~0 %: the indexes wait for a query
    "files_home_s": 15,           # 3.1 s for 100 000 files near the focus
    "files_home_mb": 60,          # +22 MB
    "notes_home_s": 30,           # 7.7 s
    "notes_home_mb": 60,          # +22 MB
    "files_repo_s": 2,            # 0.2 s for this repository
    "agent_cpu": 10.0,            # 2-4 % while a file is saved every 0.1 s
    "theme_switch_mb": 6,         # 0 MB over 300 switches after 150 to warm up (90 -> 90, 2026-10-20)
    "reading_flood_peak_mb": 200, # flood with minimum contrast 7 and ligatures on
    "terminal_tab_mb": 6,         # 0-1 MB each hidden tab (its canvas goes); 22 with the canvas kept, 43 before the shared atlas (2026-10-21)
    "all_on_over_idle_pct": 10,   # plan 17: everything on, at most 10% over idle_mb
    "all_on_cpu": 2.0,            # the same as idle_cpu
    "subagent_first_mb": 20,      # +6 to +9 MB: a 34 MB log's first opening, the text system included (2026-10-21)
    "subagent_open_mb": 8,        # 0 to +2 MB each opening after (TextKit 1 had kept +20 and jumped 70)
    "subagent_closed_mb": 5,      # +1 to +3 MB once its tab is closed again
}
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
        self.settings_file = pathlib.Path(self.dir) / "settings.json"
        self.settings_file.write_text(json.dumps(settings or {}))
        env = dict(os.environ, CADEX_BACKGROUND="1", CADEX_SPACES_FILE=f"{self.dir}/spaces.json",
                   CADEX_SETTINGS_FILE=str(self.settings_file), CADEX_THEMES_DIR=f"{self.dir}/themes",
                   SHELL=str(HERE / "loadshell.sh"), CADEX_LOAD=load, CADEX_LOAD_SECONDS=str(seconds),
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
    return {"idle_mb": max(m for m, _ in tail), "idle_cpu": avg([c for _, c in tail])}


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
    """A subagent's conversation opened at 12 s and 36 s and closed 12 s
    after each by the app (CADEX_PERF_SUBAGENT_LOG). Memory every 0.5 s,
    the median of each stretch so the 1 s jumps of switching tabs do not
    count. The first opening also loads the text system once; the second
    is what each one adds; after it closes nothing must stay. Since the
    hidden terminal lets go of its canvas (2026-10-21) the open numbers can
    be below zero: the tab costs less than the terminal it hides."""
    start = time.time()
    curve = []
    while time.time() - start < 55:
        if app.process.poll() is not None:
            raise RuntimeError(f"the app quit (status {app.process.returncode})")
        curve.append((time.time() - start, footprint_mb(app.process.pid) or 0))
        time.sleep(0.5)

    def median(begin, end):
        values = sorted(m for t, m in curve if begin <= t <= end)
        return values[len(values) // 2] if values else 0
    base, first, closed, second, after = median(7, 11), median(17, 23), median(30, 35), median(42, 47), median(52, 55)
    print(f"    base {base:.0f} MB, first open {first:.0f}, closed {closed:.0f}, second open {second:.0f}, closed {after:.0f}")
    return {"subagent_first_mb": first - base, "subagent_open_mb": second - closed, "subagent_closed_mb": after - closed}


def measure_tabs(app):
    """Five more terminal tabs opened by the app (CADEX_PERF_TABS) from
    12 s, then back to the first: what each one adds, hidden."""
    start = time.time()
    curve = []
    while time.time() - start < 30:
        if app.process.poll() is not None:
            raise RuntimeError(f"the app quit (status {app.process.returncode})")
        curve.append((time.time() - start, footprint_mb(app.process.pid) or 0))
        time.sleep(0.5)
    values = lambda begin, end: sorted(m for t, m in curve if begin <= t <= end)
    base, after = values(7, 11), values(24, 30)
    base, after = base[len(base) // 2], after[len(after) // 2]
    print(f"    base {base:.0f} MB, with five more tabs {after:.0f}")
    return {"terminal_tab_mb": (after - base) / 5}


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


ALL_ON = {"sidebar": {"items": ["agents", "files", "search", "git", "accounts"]},
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
        found = scenario("all-on", "idle", ROOT, measure_idle, settings=ALL_ON, extra_env={"CADEX_PERF_HOME": home})
        return {"all_on_mb": found["idle_mb"], "all_on_cpu": found["idle_cpu"]}
    finally:
        waiter.kill()
        shutil.rmtree(home, ignore_errors=True)


def subagent_scenario():
    folder = tempfile.mkdtemp(prefix="cadex-perf-log-")
    log = os.path.join(folder, "agent-perf.jsonl")
    try:
        write_subagent_log(log)
        return scenario("subagent", "idle", ROOT, measure_subagent, seconds=70, extra_env={"CADEX_PERF_SUBAGENT_LOG": log})
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
             ("five more terminal tabs", lambda: scenario("tabs", "idle", ROOT, measure_tabs, extra_env={"CADEX_PERF_TABS": "5"})),
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
