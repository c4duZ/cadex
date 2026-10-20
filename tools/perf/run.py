#!/usr/bin/env python3
"""Cadex's weight budget (`make perf`): runs the release app and the core's
indexes through the situations that once made it heavy, and fails when one
goes over its limit. Mac only; takes about four minutes.

Each scenario starts a test Cadex (CADEX_BACKGROUND=1, its own spaces file,
so the owner's are untouched) whose "shell" runs a load (loadshell.sh), and
samples its memory (footprint) and CPU (ps). The indexes are measured
through the C API by index_probe.c, compiled here against libcadex.a.

The limits leave room over what was measured on 2026-10-20 (in the comment
of each), so a real regression fails and noise does not. Raise one only
with a reason written next to it.
"""
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
}


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

    def __init__(self, load, folder, seconds=20):
        self.dir = tempfile.mkdtemp(prefix="cadex-perf-")
        env = dict(os.environ, CADEX_BACKGROUND="1", CADEX_SPACES_FILE=f"{self.dir}/spaces.json",
                   SHELL=str(HERE / "loadshell.sh"), CADEX_LOAD=load, CADEX_LOAD_SECONDS=str(seconds))
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


def scenario(name, load, folder, run, seconds=20):
    app = TestApp(load, folder, seconds)
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
             ("an agent saving files", lambda: scenario("agent", "idle", ROOT, measure_agent))]
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
