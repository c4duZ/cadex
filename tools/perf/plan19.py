"""Plan 19's scenarios for `make perf` (tools/perf/run.py): ten terminals
through the terminal daemon, with the window and with the app gone, and
five sessions sending hooks every second (docs/adr/0022-terminal-daemon.md).
Each test Cadex has its own sockets (CADEX_SOCKETS_DIR, CADEX_TERMINAL_SOCKET)
and tokens (CADEX_SESSIONS_DIR): the owner's app is never touched."""
import json
import os
import signal
import socket
import struct
import subprocess
import threading
import time


def daemon_pid(socket_path):
    out = subprocess.run(["pgrep", "-f", f"cadex-terminald --socket {socket_path}"], capture_output=True, text=True).stdout.split()
    return int(out[0]) if out else None


def daemon_sessions(socket_path):
    """(alive, total) sessions the daemon lists, through its own protocol."""
    s = socket.socket(socket.AF_UNIX)
    s.settimeout(3)
    s.connect(socket_path)
    buf = b""

    def frame(kind, payload=b""):
        return struct.pack("<IB", len(payload) + 1, kind) + payload

    def next_frame():
        nonlocal buf
        while True:
            if len(buf) >= 5:
                n = struct.unpack("<I", buf[:4])[0]
                if len(buf) >= 4 + n:
                    kind, payload, buf = buf[4], buf[5:4 + n], buf[4 + n:]
                    return kind, payload
            buf += s.recv(65536)

    s.sendall(frame(1, struct.pack("<H", 1)))
    next_frame()
    s.sendall(frame(4))
    _, p = next_frame()
    s.close()
    count, i, alive = struct.unpack("<I", p[:4])[0], 4, 0
    for _ in range(count):
        length = struct.unpack("<H", p[i:i + 2])[0]
        i += 2 + length
        _, is_alive, _, _ = struct.unpack("<iBiB", p[i:i + 10])
        i += 10
        alive += is_alive
    return alive, count


def cpu_percent(pid, seconds, cpu_seconds):
    start, used = time.time(), cpu_seconds(pid) or 0
    time.sleep(seconds)
    return 100 * ((cpu_seconds(pid) or 0) - used) / (time.time() - start)


def kept_scenario(perf):
    """terminal.keepSessions on, nine more tabs (ten terminals in the
    daemon): what each adds to the app, the daemon's weight with the window,
    then the app killed and the daemon alone, its ten shells still there."""
    app = perf.TestApp("idle", perf.ROOT, settings={"terminal": {"keepSessions": True}}, extra_env={"CADEX_PERF_TABS": "9"})
    sock = app.terminal_socket
    try:
        tab = perf.measure_tabs(app, count=9)["terminal_tab_mb"]
        pid = daemon_pid(sock)
        if pid is None:
            raise RuntimeError("no terminal daemon with keepSessions on")
        window_mb = perf.footprint_mb(pid) or 0
        window_cpu = cpu_percent(pid, 10, perf.cpu_seconds)
        app.process.kill()
        app.process.wait(10)
        time.sleep(2)
        alive, total = daemon_sessions(sock)
        alone_mb = perf.footprint_mb(pid) or 0
        alone_cpu = cpu_percent(pid, 10, perf.cpu_seconds)
        print(f"    {tab:.1f} MB a kept tab; daemon {window_mb:.1f} MB with the window, {alone_mb:.1f} alone, {alive} of 10 shells kept")
        return {"kept_tab_mb": tab, "daemon_window_mb": window_mb, "daemon_window_cpu": window_cpu,
                "daemon_alone_mb": alone_mb, "daemon_alone_cpu": alone_cpu, "daemon_lost_shells": 10 - alive}
    finally:
        pid = daemon_pid(sock)
        if pid:
            # SIGKILL, not SIGTERM: SIGTERM would save the shells' output
            # for the next launch, in the owner's Application Support.
            os.kill(pid, signal.SIGKILL)
        app.close()


def send_hook(path, token, pid, event):
    """True when the app took it (answered ok)."""
    line = json.dumps({"v": 1, "token": token, "event": event, "pid": pid,
                       "payload": {"session_id": f"perf-{pid}", "cwd": "/tmp", "transcript_path": f"/tmp/perf-{pid}.jsonl"}})
    s = socket.socket(socket.AF_UNIX)
    s.settimeout(2)
    try:
        s.connect(path)
        s.sendall(line.encode() + b"\n")
        return b'"ok":true' in s.recv(4096)
    except OSError:
        return False
    finally:
        s.close()


def hooks_scenario(perf):
    """Five sessions Cadex opened (their tokens in the test's folder, real
    pids) sending a hook every second each for 20 s: the app's CPU then, and
    what its memory grew."""
    app = perf.TestApp("idle", perf.ROOT, seconds=60)
    sleepers = [subprocess.Popen(["sleep", "120"]) for _ in range(5)]
    try:
        tokens = os.urandom(32).hex(), os.urandom(32).hex(), os.urandom(32).hex(), os.urandom(32).hex(), os.urandom(32).hex()
        os.makedirs(app.sessions_dir, exist_ok=True)
        for i, token in enumerate(tokens):
            with open(f"{app.sessions_dir}/perf-{i}.token", "w") as f:
                f.write(token)
        base = app.sample(16)[-1][0]
        stop = threading.Event()
        refused = []

        def send():
            events = ["SessionStart", "Stop", "Notification", "CwdChanged"]
            n = 0
            while not stop.is_set():
                for token, sleeper in zip(tokens, sleepers):
                    if not send_hook(app.app_socket, token, sleeper.pid, events[n % len(events)]):
                        refused.append(n)
                n += 1
                stop.wait(1)

        sender = threading.Thread(target=send)
        sender.start()
        try:
            during = app.sample(20)
        finally:
            stop.set()
            sender.join()
        top = max(m for m, _ in during)
        print(f"    base {base:.0f} MB, {top:.0f} MB at most while 5 sessions hooked every second")
        return {"hooks_cpu": perf.avg([c for _, c in during]), "hooks_mb": top - base, "hooks_refused": len(refused)}
    finally:
        for sleeper in sleepers:
            sleeper.kill()
        app.close()
