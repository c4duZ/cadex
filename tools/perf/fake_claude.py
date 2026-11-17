#!/usr/bin/env python3
"""A fake `claude` for the orchestration's tests and `make perf` (plan 24 F):
reads the kit's --settings like Claude Code (its env), sends the hooks the
kit registers (SessionStart, Stop, SessionEnd) through `cadex hook`, and
acts on words in its prompt (the last argument), reporting by `cadex run`:

  FAKE-DONE        report-done, then idle
  FAKE-SPAWN       spawn a sub-task whose spec is FAKE-SLEEP, then sleep
  FAKE-ASK         ask a question, then idle
  FAKE-HEARTBEAT   a heartbeat every 20 s
  FAKE-SLEEP       work for FAKE_SLEEP seconds (default 300), then idle
  FAKE-SILENT      nothing at all (it stalls)
  FAKE-BLOCKED     says it waits for a permission (OSC 7501 blocked), then waits

It tells the terminal its state by OSC 7501 like Claude Code (working when
it starts, idle when it stops).

It never talks to the network. Idle means: wait until killed."""
import json, os, signal, subprocess, sys, time, uuid

args = sys.argv[1:]
prompt = args[-1] if args else ""
settings = args[args.index("--settings") + 1] if "--settings" in args else None
env = dict(os.environ)
if settings and os.path.exists(settings):
    env.update(json.load(open(settings)).get("env", {}))
session = str(uuid.uuid4())
cadex = os.environ.get("FAKE_CADEX", "cadex")


def log(text):
    if os.environ.get("FAKE_LOG"):
        with open(os.environ["FAKE_LOG"], "a") as out:
            out.write(f"{os.getpid()} {text}\n")


def hook(event):
    payload = {"session_id": session, "transcript_path": "/dev/null", "cwd": os.getcwd(), "hook_event_name": event, "source": "startup"}
    subprocess.run([cadex, "hook", event], input=json.dumps(payload).encode(), env=env, timeout=15, capture_output=True)


def run(*words):
    done = subprocess.run([cadex, "run", *words], env=env, timeout=45, capture_output=True, text=True)
    log(f"{words[0]} -> {done.returncode} {done.stdout.strip()} {done.stderr.strip()}")


def status(state, kind=""):
    extra = f":kind={kind}" if kind else ""
    sys.stdout.write(f"\x1b]7501;state={state}:app=claude-code{extra}\x07")
    sys.stdout.flush()


def idle():
    status("idle")
    hook("Stop")
    while True:
        time.sleep(3600)


signal.signal(signal.SIGTERM, lambda *_: (hook("SessionEnd"), sys.exit(0)))
log("started: " + prompt[:40])
hook("SessionStart")
hook("UserPromptSubmit")
status("working")
if "FAKE-BLOCKED" in prompt:
    status("blocked", "permission")
    while True:
        time.sleep(3600)
if "FAKE-SPAWN" in prompt:
    path = os.path.join(os.getcwd(), "child-spec.md")
    open(path, "w").write("FAKE-SLEEP child")
    run("orchestration.spawn", "title=child", "spec-file=" + path)
    time.sleep(int(os.environ.get("FAKE_SLEEP", "300")))
    idle()
if "FAKE-ASK" in prompt:
    run("orchestration.ask", "question=Which color?")
    idle()
if "FAKE-HEARTBEAT" in prompt:
    while True:
        run("orchestration.report-heartbeat", "note=fake working")
        time.sleep(20)
if "FAKE-SLEEP" in prompt:
    time.sleep(int(os.environ.get("FAKE_SLEEP", "300")))
    idle()
if "FAKE-DONE" in prompt:
    time.sleep(2)
    run("orchestration.report-done", "summary=fake done")
    idle()
idle()
