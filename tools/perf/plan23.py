"""Plan 23's scenarios for `make perf` (tools/perf/run.py): the tailnet's
machines with a fake Tailscale daemon (docs/spec/machines.md). The test
app reaches only it (CADEX_PERF_TAILSCALE_SOCKET; nothing else is looked
for), never the owner's Tailscale. The app opens the SSH card's Tailnet
group by itself from 12 s to 32 s (CADEX_PERF_MACHINES,
apps/macos/app/PerfHooks.swift), and again from 44 s to 64 s: the reading,
a ping per online machine and the watch stream, the group built at each
change.

- on: the first opening's one-time cost apart (the text system and the
  dots' layers, which the SSH card's own hosts also pay on a first hover;
  the test app never hovers), each opening after at most 3 % over the app
  before it, CPU back to idle after, and no request once closed;
- machines.tailscale off: not one request (what `fs_usage` would show,
  counted by the daemon itself: fs_usage needs root).
"""
import json
import os
import socket
import tempfile
import threading
import time

MACHINES = 20


def status_json():
    """This Mac and 20 machines: online ones direct or through a relay, the rest off."""
    peers = {}
    for n in range(MACHINES):
        online = n % 4 != 3
        peers[f"key:{n}"] = {
            "ID": f"n{n}", "HostName": f"host-{n}", "DNSName": f"host-{n}.tail1234.ts.net.", "OS": "linux",
            "UserID": 1, "TailscaleIPs": [f"100.64.1.{n + 2}"], "Online": online, "Relay": "sao",
            "CurAddr": f"192.168.0.{n + 2}:41641" if n % 2 == 0 else "", "Active": online,
            "LastSeen": "2026-11-16T10:00:00Z"}
    return {"BackendState": "Running", "MagicDNSSuffix": "tail1234.ts.net",
            "Self": {"ID": "me", "HostName": "perf-mac", "DNSName": "perf-mac.tail1234.ts.net.", "OS": "macOS",
                     "UserID": 1, "TailscaleIPs": ["100.64.1.1"], "Online": True},
            "Peer": peers, "User": {"1": {"ID": 1, "LoginName": "owner@example.com"}}}


class FakeDaemon:
    """The LocalAPI on a Unix socket, HTTP/1.0 as Cadex speaks it; counts
    each request with the time it came."""

    def __init__(self, path):
        self.path = path
        self.requests = []
        self.server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.server.bind(path)
        self.server.listen(16)
        self.open = True
        threading.Thread(target=self.serve, daemon=True).start()

    def serve(self):
        while self.open:
            try:
                client, _ = self.server.accept()
            except OSError:
                return
            threading.Thread(target=self.answer, args=(client,), daemon=True).start()

    def answer(self, client):
        try:
            head = b""
            while b"\r\n\r\n" not in head:
                chunk = client.recv(4096)
                if not chunk:
                    return
                head += chunk
            line = head.split(b"\r\n")[0].decode()
            self.requests.append((time.time(), line))
            ok = "HTTP/1.0 200 OK\r\nContent-Type: application/json\r\n\r\n"
            if "/localapi/v0/status" in line:
                client.sendall((ok + json.dumps(status_json())).encode())
            elif "/localapi/v0/ping" in line:
                client.sendall((ok + json.dumps({"LatencySeconds": 0.012, "Endpoint": "192.168.0.9:41641"})).encode())
            elif "/localapi/v0/watch-ipn-bus" in line:
                # The engine's counters every 2 s, as the real one (2026-11-16).
                client.sendall(ok.encode())
                while self.open:
                    client.sendall(b'{"Version":"perf","Engine":{"RBytes":1,"WBytes":2,"NumLive":15}}\n')
                    time.sleep(2)
            else:
                client.sendall(b"HTTP/1.0 404 Not Found\r\n\r\n")
        except OSError:
            pass
        finally:
            client.close()

    def close(self):
        self.open = False
        self.server.close()
        os.unlink(self.path)


def run(perf, settings):
    """The test app with the fake daemon; (samples by phase, requests, out)."""
    folder = tempfile.mkdtemp(prefix="cx23-", dir="/tmp")  # a Unix socket's path is short
    daemon = FakeDaemon(folder + "/t.sock")
    out = folder + "/machines.out"
    app = perf.TestApp("idle", perf.ROOT, seconds=90, settings=settings,
                       extra_env={"CADEX_PERF_TAILSCALE_SOCKET": daemon.path, "CADEX_PERF_MACHINES": out})
    try:
        phases = {"base": app.sample(10), "first": app.sample(22), "between": app.sample(10), "second": app.sample(22)}
        deadline = time.time() + 10
        while "twice" not in (open(out).read() if os.path.exists(out) else "") and time.time() < deadline:
            time.sleep(0.2)
        closed_at = time.time()
        phases["after"] = app.sample(12)
        late = [r for at, r in daemon.requests if at > closed_at + 1]
        return phases, daemon.requests, late, (open(out).read() if os.path.exists(out) else "")
    finally:
        app.close()
        daemon.close()
        os.rmdir(folder) if not os.listdir(folder) else None


def on_scenario(perf):
    phases, requests, late, out = run(perf, {})
    top = {name: max(m for m, _ in samples) for name, samples in phases.items()}
    idle = max(m for m, _ in phases["base"][-3:])
    before = max(m for m, _ in phases["between"][-3:])
    after_cpu = perf.avg([c for _, c in phases["after"]])
    print(f"    {idle:.0f} MB idle; first opening {top['first']:.0f} MB, then {before:.0f}; second opening {top['second']:.0f} MB "
          f"({out.strip()}); {after_cpu:.2f} % CPU after; {len(requests)} requests, {len(late)} after closing")
    if "closed 20 twice" not in out:
        raise RuntimeError(f"the group did not read the 20 machines twice: {out!r}")
    return {"machines_first_open_mb": top["first"] - idle, "machines_open_over_idle_pct": 100 * (top["second"] - before) / before,
            "machines_after_cpu": after_cpu, "machines_requests_after_close": len(late)}


def off_scenario(perf):
    _, requests, _, _ = run(perf, {"machines": {"tailscale": False}})
    print(f"    {len(requests)} requests to Tailscale with machines.tailscale off")
    return {"machines_off_requests": len(requests)}
