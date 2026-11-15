"""The fake agent of plan 20's perf scenario (tools/perf/plan20.py): runs in
the test Cadex's terminal and drives the preview as an agent would, through
the app's socket with a session's token and the pids above it. Writes
{"asked", "done", "seconds"} to $CADEX_PERF_OUT when it ends."""
import json
import os
import pathlib
import re
import signal
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from plan20 import request  # noqa: E402


def ancestors():
    pids, pid = [], os.getpid()
    while pid > 1:
        pids.append(pid)
        out = subprocess.run(["ps", "-o", "ppid=", "-p", str(pid)], capture_output=True, text=True).stdout.strip()
        pid = int(out) if out else 1
    return pids


def lead_terminal():
    """Its own process group, in front of the terminal, as an interactive
    shell gives a program: this "shell" has no job control, and the app
    reads the shell itself in front as no program (foreground group 0)."""
    signal.signal(signal.SIGTTOU, signal.SIG_IGN)
    os.setpgid(0, 0)
    tty = os.open("/dev/tty", os.O_RDWR)
    os.tcsetpgrp(tty, os.getpgrp())
    os.close(tty)


def main():
    lead_terminal()
    out = pathlib.Path(os.environ["CADEX_PERF_OUT"])
    go = out.parent / "go"
    while not go.exists():
        time.sleep(0.2)
    sock = go.read_text()
    token, url, pids = os.environ["CADEX_PERF_TOKEN"], os.environ["CADEX_PERF_URL"], ancestors()

    first_error = []

    def drive(args):
        answer = request(sock, token, "preview.agent", args, pids)
        if not (answer and answer.get("ok")) and not first_error:
            first_error.append(f"{args.get('action')}: {answer}")
        return answer.get("result", "") if answer and answer.get("ok") else None

    asked = done = 0
    start = time.time()
    asked += 1
    done += drive({"action": "goto", "url": url}) is not None
    for _ in range(100):
        asked += 1
        tree = drive({"action": "snapshot"})
        done += tree is not None
        ref = re.search(r'button "Add one" \[@(e\d+)\]', tree or "")
        asked += 1
        done += ref is not None and drive({"action": "click", "ref": ref.group(1)}) is not None
    out.write_text(json.dumps({"asked": asked, "done": done, "seconds": time.time() - start,
                               "first_error": first_error[0] if first_error else None}))


if __name__ == "__main__":
    main()
