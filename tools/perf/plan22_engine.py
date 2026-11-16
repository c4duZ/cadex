"""What plan 22's perf scenarios (tools/perf/plan22.py) share: a release
`cadex-memory` in a temporary folder with a session token on disk, spoken to
over its socket the way `cadex memory-hook` speaks (HTTP/1.1, X-Cadex-Token),
and the `cadex memory-hook` itself run as Claude Code runs it. HOME is the
temporary folder, so the engine's import never reads the owner's accounts.
"""
import http.client
import json
import os
import shutil
import socket
import subprocess
import tempfile
import time
import urllib.parse

TOKEN = "c" * 64
PROJECT = "perfrepo"


class UnixHTTP(http.client.HTTPConnection):
    def __init__(self, path):
        super().__init__("localhost", timeout=120)
        self.path = path

    def connect(self):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(120)
        self.sock.connect(self.path)


class Engine:
    """A release cadex-memory on `<tmp>/m.sock`, data in `<tmp>/data`, with a
    session (this process's pid) so it stays up, in the git repo `<tmp>/perfrepo`."""

    def __init__(self, app, args=(), models=None):
        self.app = app
        self.bin = str(app / "Contents/Helpers/cadex-memory")
        self.cli = str(app / "Contents/Helpers/cadex")
        self.dir = tempfile.mkdtemp(prefix="cadex-perf-memory-")
        self.socket = f"{self.dir}/m.sock"
        self.data = f"{self.dir}/data"
        self.tokens = f"{self.dir}/sessions"
        os.makedirs(self.tokens)
        with open(f"{self.tokens}/perf.token", "w") as f:
            f.write(TOKEN)
        if models:
            shutil.copytree(models, f"{self.data}/models")
        self.repo = os.path.realpath(f"{self.dir}/{PROJECT}")
        os.makedirs(self.repo)
        subprocess.run(["git", "init", "-q"], cwd=self.repo, check=True)
        self.process = subprocess.Popen(
            [self.bin, "--socket", self.socket, "--data-dir", self.data, "--tokens-dir", self.tokens, *args],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, env=self.env())
        deadline = time.time() + 20
        while not os.path.exists(self.socket):
            if time.time() > deadline or self.process.poll() is not None:
                raise RuntimeError("cadex-memory did not start")
            time.sleep(0.05)
        self.hook("session-start", "perf-1", {"hook_event_name": "SessionStart", "source": "startup"}, pid=os.getpid())

    def env(self):
        """Only what the engine and the hook need: nothing of the shell this
        runs in (a Cadex tab has the owner's CADEX_* and CLAUDE_* in it)."""
        return {"PATH": "/usr/bin:/bin", "HOME": self.dir, "TMPDIR": self.dir, "CADEX_MEMORY_LOG": "warn"}

    @property
    def pid(self):
        return self.process.pid

    def request(self, method, path, body=None):
        """(status, body) of one request on a new connection, as the hook makes it."""
        conn = UnixHTTP(self.socket)
        headers = {"X-Cadex-Token": TOKEN, "Content-Type": "application/json",
                   "Accept": "application/json, text/event-stream"}
        conn.request(method, path, body, headers)
        answer = conn.getresponse()
        data = answer.read()
        conn.close()
        return answer.status, data

    def hook(self, event, session, payload, pid=None):
        """POST /hook as `cadex memory-hook` sends it (events.zig, hookTarget)."""
        body = {"session_id": session, "cwd": self.repo, **payload}
        query = {"event": event, "agent": "claude-code", "cwd": self.repo, "session_id": session,
                 "project_strategy": "repo-root", "ingest_key": os.urandom(16).hex()}
        if pid:
            query["pid"] = pid
        status, _ = self.request("POST", "/hook?" + urllib.parse.urlencode(query), json.dumps(body))
        if status >= 300:
            raise RuntimeError(f"{event} refused ({status})")

    def briefing(self, session):
        """GET /handoff with briefing=1 (events.zig, handoffTarget), not
        claiming the handoff (claim=0, as the Memory page asks)."""
        query = {"agent": "claude-code", "cwd": self.repo, "project_strategy": "repo-root",
                 "briefing": "1", "session_id": session, "claim": "0"}
        status, body = self.request("GET", "/handoff?" + urllib.parse.urlencode(query))
        if status != 200:
            raise RuntimeError(f"briefing refused ({status})")
        return body

    def tool(self, name, arguments):
        call = {"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": {"name": name, "arguments": arguments}}
        status, body = self.request("POST", "/mcp", json.dumps(call))
        answer = json.loads(body) if status == 200 else {}
        result = answer.get("result") or {}
        if status != 200 or "error" in answer or result.get("isError"):
            raise RuntimeError(f"{name} failed ({status}): {body[:200]!r}")
        return result

    def write_pages(self, start, count):
        """`count` pages in batches of 100, the most upstream's batch tool takes."""
        for first in range(start, start + count, 100):
            pages = [{"path": f"notes/page-{n:05}.md", "body": page_body(n), "create_only": True}
                     for n in range(first, min(first + 100, start + count))]
            self.tool("memory_write_pages_batch", {"workspace": "default", "project": PROJECT, "pages": pages})

    def memory_hook(self, claude_event, payload):
        """Run the whole `cadex memory-hook <event>` as Claude Code does, with
        the kit's environment; (milliseconds, stdout)."""
        env = dict(self.env(), CADEX_SESSION_TOKEN=TOKEN, CADEX_MEMORY_SOCKET=self.socket,
                   CADEX_MEMORY_DIR=self.data, CADEX_MEMORY_BIN=self.bin, CADEX_SESSIONS_DIR=self.tokens)
        stdin = json.dumps({"cwd": self.repo, "hook_event_name": claude_event, **payload})
        started = time.perf_counter()
        out = subprocess.run([self.cli, "memory-hook", claude_event], input=stdin, capture_output=True,
                             text=True, env=env, cwd=self.repo, timeout=10)
        return (time.perf_counter() - started) * 1000, out.stdout

    def close(self):
        self.process.terminate()
        try:
            self.process.wait(10)
        except subprocess.TimeoutExpired:
            self.process.kill()
        shutil.rmtree(self.dir, ignore_errors=True)


WORDS = ("terminal render cache socket memory engine page wiki search index tree theme palette "
         "worktree commit branch review comment agent session hook briefing handoff model vector").split()


def page_body(n):
    """A page of ~1.5 KB, different words in each, as a project's notes are."""
    lines = [f"# Note {n}", "", f"Decision {n} about the {WORDS[n % len(WORDS)]} and the {WORDS[(n * 7) % len(WORDS)]}."]
    for i in range(12):
        lines.append(" ".join(WORDS[(n + i * j) % len(WORDS)] for j in range(1, 16)) + f" ({n}-{i}).")
    return "\n".join(lines) + "\n"


def engine_running(data_dir):
    """Whether a cadex-memory serves `data_dir` (its command line names it)."""
    out = subprocess.run(["pgrep", "-f", f"cadex-memory .*--data-dir {data_dir}"], capture_output=True, text=True).stdout
    return bool(out.split())
