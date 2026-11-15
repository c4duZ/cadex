"""Plan 21's scenarios for `make perf` (tools/perf/run.py): a task's review
with 50 files and 5 thousand changed lines, opened and scrolled, with 20
comments and 200 authorship events sent while it scrolls; and everything
off weighing what the idle app weighs (docs/spec/review.md). The test app
opens the review itself (CADEX_PERF_REVIEW, apps/macos/app/PerfHooks.swift)
and writes when it is ready and when it stops scrolling."""
import datetime
import json
import os
import pathlib
import socket
import subprocess
import tempfile
import time

FILES = 50
LINES = 200
CHANGED_EVERY = 2  # 100 changed lines a file: 5 000 in all


def git(cwd, *args):
    subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True)


def fake_task(root):
    """main with 50 files of 200 lines; the task's worktree changes every other line."""
    repo = pathlib.Path(root) / "repo"
    repo.mkdir()
    git(repo, "init", "-q", "-b", "main")
    git(repo, "config", "user.email", "perf@cadex")
    git(repo, "config", "user.name", "perf")
    for f in range(FILES):
        (repo / f"file{f:02}.swift").write_text("".join(f"let value{n} = {n}\n" for n in range(LINES)))
    git(repo, "add", ".")
    git(repo, "commit", "-q", "-m", "base")
    worktree = pathlib.Path(root) / "task"
    git(repo, "worktree", "add", "-q", "-b", "task", str(worktree), "main")
    for f in range(FILES):
        lines = [f"let value{n} = {n * 10} // the agent\n" if n % CHANGED_EVERY == 0 else f"let value{n} = {n}\n" for n in range(LINES)]
        (worktree / f"file{f:02}.swift").write_text("".join(lines))
    return str(worktree.resolve())


def write_comments(review_dir, worktree):
    """20 comments pending on the task, as the review feature keeps them."""
    now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    pending = [{"id": f"perf-{i}", "path": f"file{i:02}.swift", "old": False, "start": 1, "end": 1,
                "lines": ["let value0 = 0 // the agent"], "before": [], "after": ["let value1 = 1"],
                "body": f"Comment {i}: check this.", "created": now, "stale": False} for i in range(20)]
    folder = pathlib.Path(review_dir) / "repo"
    folder.mkdir(parents=True, exist_ok=True)
    (folder / "task.json").write_text(json.dumps({"pending": pending, "sent": []}))


def send_edit(path, token, file, line):
    """One PostToolUse event, as `cadex hook` sends it; True when answered."""
    payload = {"session_id": "perf-session", "cwd": os.path.dirname(file), "tool_name": "Edit", "file": file,
               "whole": False, "lines": [[line, line]]}
    s = socket.socket(socket.AF_UNIX)
    s.settimeout(2)
    try:
        s.connect(path)
        s.sendall(json.dumps({"v": 1, "token": token, "event": "PostToolUse", "pid": os.getpid(), "payload": payload}).encode() + b"\n")
        return b'"ok":true' in s.recv(4096)
    except OSError:
        return False
    finally:
        s.close()


def review_scenario(perf):
    """The review opened at 12 s and scrolled for 15 s, 200 edits sent meanwhile."""
    root = tempfile.mkdtemp(prefix="cadex-perf-review-")
    worktree = fake_task(root)
    review_dir = os.path.join(root, "review")
    write_comments(review_dir, worktree)
    out = os.path.join(root, "review.out")
    app = perf.TestApp("idle", pathlib.Path(worktree), seconds=60,
                       extra_env={"CADEX_PERF_REVIEW": out, "CADEX_REVIEW_DIR": review_dir})
    try:
        token = os.urandom(32).hex()
        os.makedirs(app.sessions_dir, exist_ok=True)
        with open(f"{app.sessions_dir}/perf-review.token", "w") as f:
            f.write(token)
        base = app.sample(10)[-1][0]
        deadline = time.time() + 40
        while not os.path.exists(out) and time.time() < deadline:
            time.sleep(0.2)
        if not os.path.exists(out):
            raise RuntimeError("the review did not open in 40 s")
        opened = float(open(out).read().split()[1])
        refused = 0
        during = []
        start = time.time()
        for i in range(200):
            if not send_edit(app.app_socket, token, f"{worktree}/file{i % FILES:02}.swift", 1 + (i // FILES) * 2):
                refused += 1
            if i % 20 == 19:
                during += app.sample(1, every=1)
        while "scrolled" not in open(out).read() and time.time() - start < 30:
            during += app.sample(2)
        # Settled: what the open review keeps once the scrolling stops; the
        # peak is the scrolling's freed memory macOS has not taken back yet.
        after = app.sample(12)
        top = max(m for m, _ in during) if during else 0
        settled = perf.avg([m for m, _ in after[-3:]])
        print(f"    open in {opened:.2f} s; {base:.0f} → peak {top:.0f}, settled {settled:.0f} MB; "
              f"{perf.avg([c for _, c in during]):.1f} % CPU scrolling, {perf.avg([c for _, c in after]):.1f} % after; {refused} of 200 edits refused")
        return {"review_open_s": opened, "review_mb": settled - base, "review_peak_mb": top - base,
                "review_cpu": perf.avg([c for _, c in during]), "review_after_cpu": perf.avg([c for _, c in after[-3:]]),
                "review_edits_refused": refused}
    finally:
        app.close()


def off_scenario(perf):
    """review.authorship off and no review: the idle app's weight."""
    app = perf.TestApp("idle", perf.ROOT, settings={"review": {"authorship": False}})
    try:
        # Measured the way the idle app is (run.py, measure_idle), so the two compare:
        # an average over other seconds once read 6 MB over an idle reading that came low.
        app.sample(16)
        mb = max(m for m, _ in app.sample(10))
        print(f"    {mb:.0f} MB with authorship off")
        return {"review_off_mb": mb}
    finally:
        app.close()
