"""Plan 20's scenarios for `make perf` (tools/perf/run.py): the agent tools
off weigh what the app weighed before them, and a fake agent driving the
preview (100 snapshots and 100 clicks on a local page) costs little and
leaves nothing running when it stops (docs/adr/0024-agent-tools.md,
docs/adr/0025-agent-drives-preview.md).

The fake agent (plan20_agent.py) runs inside the test app's terminal, as a
real agent would: the app finds its terminal by the pids above it. Each
test Cadex has its own sockets and tokens; the owner's app is never touched."""
import functools
import http.server
import json
import os
import pathlib
import socket
import tempfile
import threading
import time

HERE = pathlib.Path(__file__).resolve().parent
PAGE = """<!doctype html><title>perf page</title>
<h1>Orders</h1><p id=count>0</p>
<button onclick="document.getElementById('count').textContent = +document.getElementById('count').textContent + 1">Add one</button>
<label>Name <input name=name></label>
<ul>""" + "".join(f"<li><a href='#item{i}'>Item {i}</a></li>" for i in range(60)) + "</ul>"


def request(path, token, command, args, pids):
    """The app's answer to one command request, as a dict (or None)."""
    line = json.dumps({"v": 1, "token": token, "run": command, "args": args, "pids": pids})
    s = socket.socket(socket.AF_UNIX)
    s.settimeout(40)
    try:
        s.connect(path)
        s.sendall(line.encode() + b"\n")
        data = b""
        while not data.endswith(b"\n"):
            chunk = s.recv(65536)
            if not chunk:
                break
            data += chunk
        return json.loads(data) if data.strip() else None
    except (OSError, ValueError):
        return None
    finally:
        s.close()


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass


def serve(folder):
    """A local server for the test page, on a free port; (server, url)."""
    (pathlib.Path(folder) / "index.html").write_text(PAGE)
    handler = functools.partial(QuietHandler, directory=folder)
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server, f"http://127.0.0.1:{server.server_address[1]}/index.html"


def write_token(app):
    token = os.urandom(32).hex()
    os.makedirs(app.sessions_dir, exist_ok=True)
    with open(f"{app.sessions_dir}/perf-agent.token", "w") as f:
        f.write(token)
    return token


def off_scenario(perf):
    """agentTools, the browser and computer use all off: a command request
    with a session's token is refused, hooks still answered (plan 19), and
    the memory is the idle app's."""
    settings = {"agentTools": {"enabled": False, "browser": False}, "computerUse": {"enabled": False}}
    app = perf.TestApp("idle", perf.ROOT, settings=settings)
    try:
        token = write_token(app)
        samples = app.sample(20)
        answer = request(app.app_socket, token, "agent-tools.notify", {"text": "perf"}, [app.process.pid])
        accepted = 1 if answer and answer.get("ok") else 0
        mb = perf.avg([m for m, _ in samples[-4:]])
        print(f"    {mb:.0f} MB with the agent tools off; a command request {'ANSWERED' if accepted else 'refused'}")
        return {"tools_off_mb": mb, "tools_off_accepted": accepted}
    finally:
        app.close()


def browser_scenario(perf):
    """The fake agent in the terminal: a goto, then 100 snapshots and 100
    clicks; the app's memory growth and CPU while it drives, its CPU after."""
    folder = tempfile.mkdtemp(prefix="cadex-perf-page-")
    server, url = serve(folder)
    out = pathlib.Path(folder) / "agent.json"
    token = os.urandom(32).hex()
    app = perf.TestApp("agent", perf.ROOT, seconds=180, extra_env={
        "CADEX_PERF_TOKEN": token, "CADEX_PERF_URL": url, "CADEX_PERF_OUT": str(out),
        "CADEX_PERF_AGENT": str(HERE / "plan20_agent.py")})
    try:
        os.makedirs(app.sessions_dir, exist_ok=True)
        with open(f"{app.sessions_dir}/perf-agent.token", "w") as f:
            f.write(token)
        # Warmed up first, so the growth is the agent's and not the launch's;
        # then the agent starts, told where the test app's socket is.
        base = app.sample(16)[-1][0]
        (pathlib.Path(folder) / "go").write_text(app.app_socket)
        during = []
        deadline = time.time() + 150
        while not out.exists() and time.time() < deadline:
            during += app.sample(4)
        if not out.exists():
            raise RuntimeError("the fake agent did not finish in 150 s")
        result = json.loads(out.read_text())
        after = app.sample(10)
        top = max(m for m, _ in during) if during else 0
        if result.get("first_error"):
            print(f"    first refusal: {result['first_error']}")
        print(f"    {result['done']} of {result['asked']} answered in {result['seconds']:.1f} s; "
              f"{base:.0f} → {top:.0f} MB; {perf.avg([c for _, c in after]):.1f} % CPU after")
        return {"browser_agent_mb": top - base, "browser_agent_cpu": perf.avg([c for _, c in during]),
                "browser_agent_failed": result["asked"] - result["done"],
                "browser_agent_after_cpu": perf.avg([c for _, c in after])}
    finally:
        app.close()
        server.shutdown()
