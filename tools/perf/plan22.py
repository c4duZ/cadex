"""Plan 22's scenarios for `make perf` (tools/perf/run.py): the memory
engine, `cadex-memory`, measured from the release app's bundle
(docs/spec/memory.md, docs/plans/22-memory.md phase I):

- idle with no model loaded: its footprint and CPU;
- with the embedding model loaded by 500 pages written and 10 searches: the
  peak; then, the model unloaded after --embed-idle-secs and the engine
  re-executed by itself (server/src/restart.rs), back to the idle weight;
- a wiki of 2 thousand pages and a fake session sending 500 events: the tool
  hook and the briefing over the socket, and the whole `cadex memory-hook`.

The app's side (no engine without an agent session) is measured with the
idle app in run.py. The model comes from CADEX_PERF_MODELS (a folder with
all-MiniLM-L6-v2/, as `make memory-eval MODELS=` takes) or, without it, is
downloaded by the engine itself into its temporary folder (~87 MB).
"""
import os
import statistics
import threading
import time

from plan22_engine import PROJECT, Engine

IDLE_SECS = 5        # --embed-idle-secs here; the app's default is 60
MODEL = "all-MiniLM-L6-v2"


def engine_samples(perf, pid, seconds, every=1.0):
    """(footprint MB, CPU %) of the engine over `seconds`, as TestApp.sample."""
    samples = []
    end = time.time() + seconds
    last_time, last_cpu = time.time(), perf.cpu_seconds(pid) or 0
    while time.time() < end:
        time.sleep(every)
        now, used = time.time(), perf.cpu_seconds(pid)
        if used is None:
            raise RuntimeError("cadex-memory quit")
        samples.append((perf.footprint_mb(pid) or 0, 100 * (used - last_cpu) / (now - last_time)))
        last_time, last_cpu = now, used
    return samples


class Peak:
    """The highest footprint of `pid`, sampled every 0.25 s in a thread."""

    def __init__(self, perf, pid):
        self.perf, self.pid, self.top, self.stop = perf, pid, 0.0, threading.Event()
        self.thread = threading.Thread(target=self.run, daemon=True)

    def run(self):
        while not self.stop.is_set():
            self.top = max(self.top, self.perf.footprint_mb(self.pid) or 0)
            self.stop.wait(0.25)

    def __enter__(self):
        self.thread.start()
        return self

    def __exit__(self, *exc):
        self.stop.set()
        self.thread.join()


def idle_scenario(perf):
    """A session open, nothing asked: the engine with no model."""
    engine = Engine(perf.APP)
    try:
        engine_samples(perf, engine.pid, 12)  # the import's delay and the start's maintenance settle
        tail = engine_samples(perf, engine.pid, 10)
        mb, cpu = max(m for m, _ in tail), perf.avg([c for _, c in tail])
        print(f"    {mb:.1f} MB, {cpu:.2f} % CPU with a session open and no model")
        return {"memory_idle_mb": mb, "memory_idle_cpu": cpu}
    finally:
        engine.close()


def model_present(engine):
    folder = f"{engine.data}/models/{MODEL}"
    names = os.listdir(folder) if os.path.isdir(folder) else []
    return len([n for n in names if not n.endswith(".part")]) >= 3 and not any(n.endswith(".part") for n in names)


def ensure_model(engine):
    """The model in the engine's folder: copied, or fetched by the engine on
    the first search that needs it (lazy_embedder.rs), as on a first session."""
    if model_present(engine):
        return
    engine.tool("memory_query", {"workspace": "default", "project": PROJECT, "query": "terminal"})
    deadline = time.time() + 300
    while not model_present(engine):
        if time.time() > deadline:
            raise RuntimeError("the embedding model was not fetched in 5 min (no network? set CADEX_PERF_MODELS)")
        time.sleep(1)


def model_scenario(perf):
    """The model loaded by writes and searches, then unloaded and given back."""
    engine = Engine(perf.APP, ["--embed-idle-secs", str(IDLE_SECS)], models=os.environ.get("CADEX_PERF_MODELS"))
    try:
        ensure_model(engine)
        pid = engine.pid
        with Peak(perf, pid) as peak:
            engine.write_pages(0, 500)
            for word in ("terminal cache", "review comment", "worktree branch", "theme palette", "agent hook",
                         "wiki page", "search index", "session briefing", "vector model", "socket engine"):
                engine.tool("memory_query", {"workspace": "default", "project": PROJECT, "query": word, "limit": 10})
        # Unloaded IDLE_SECS after the last use, then the re-exec (~70 ms)
        # in the same pid; a few seconds more for the new process to settle.
        time.sleep(IDLE_SECS + 6)
        if engine.process.poll() is not None or engine.pid != pid:
            raise RuntimeError("cadex-memory did not survive its restart")
        after = engine_samples(perf, pid, 6)
        mb = max(m for m, _ in after)
        print(f"    peak {peak.top:.0f} MB with the model; {mb:.1f} MB once it unloaded and the engine restarted")
        return {"memory_model_peak_mb": peak.top, "memory_model_after_mb": mb}
    finally:
        engine.close()


def ms(started):
    return (time.perf_counter() - started) * 1000


def wiki_scenario(perf):
    """2 000 pages, then a session of 500 events, briefings, and the whole hook."""
    engine = Engine(perf.APP, ["--no-embeddings"])
    try:
        started = time.perf_counter()
        engine.write_pages(0, 2000)
        write_s = ms(started) / 1000
        tool_ms, prompt_ms = [], []
        for n in range(500):
            started = time.perf_counter()
            if n % 10 == 0:
                engine.hook("user-prompt-submit", "perf-2", {"hook_event_name": "UserPromptSubmit", "prompt": f"change note {n}"})
                prompt_ms.append(ms(started))
            else:
                engine.hook("post-tool-use", "perf-2", {
                    "hook_event_name": "PostToolUse", "tool_name": "Edit",
                    "tool_input": {"file_path": f"{engine.repo}/src/file{n % 40}.zig", "old_string": "a", "new_string": "b"},
                    "tool_response": {"filePath": f"{engine.repo}/src/file{n % 40}.zig", "success": True}})
                tool_ms.append(ms(started))
        brief_ms = []
        for _ in range(20):
            started = time.perf_counter()
            engine.briefing("perf-3")
            brief_ms.append(ms(started))
        whole_tool = [engine.memory_hook("PostToolUse", {
            "session_id": "perf-2", "tool_name": "Edit",
            "tool_input": {"file_path": f"{engine.repo}/src/whole.zig", "old_string": "a", "new_string": "b"},
            "tool_response": {"success": True}})[0] for _ in range(30)]
        starts = [engine.memory_hook("SessionStart", {"session_id": f"perf-start-{i}", "source": "startup"}) for i in range(10)]
        if not all("hookSpecificOutput" in out or out.strip() for _, out in starts):
            raise RuntimeError("a SessionStart came back with no briefing")
        idle = engine_samples(perf, engine.pid, 6)
        result = {"memory_tool_hook_ms": statistics.median(tool_ms), "memory_briefing_ms": statistics.median(brief_ms),
                  "memory_whole_hook_ms": statistics.median(whole_tool),
                  "memory_whole_start_ms": statistics.median([t for t, _ in starts]),
                  "memory_wiki_idle_mb": max(m for m, _ in idle)}
        print(f"    2 000 pages written in {write_s:.0f} s; socket: tool hook {result['memory_tool_hook_ms']:.2f} ms, "
              f"prompt {statistics.median(prompt_ms):.2f} ms, briefing {result['memory_briefing_ms']:.2f} ms (medians); "
              f"whole cadex memory-hook: PostToolUse {result['memory_whole_hook_ms']:.1f} ms, "
              f"SessionStart {result['memory_whole_start_ms']:.1f} ms; {result['memory_wiki_idle_mb']:.1f} MB after")
        return result
    finally:
        engine.close()
