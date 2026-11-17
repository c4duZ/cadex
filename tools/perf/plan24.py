"""Plan 24's scenarios for `make perf` (tools/perf/run.py): many agents at
once (docs/spec/orchestration.md, docs/adr/0033-cadex-launches-agents.md).

- off (the default): the app weighs what it weighed before, and opens no
  state file, writes no LaunchAgent and keeps no job in launchd;
- on: a race of 3 and a run of 5 tasks with fake agents (fake_claude.py,
  through CADEX_CLAUDE_BIN: it reads the kit's --settings, sends the hooks,
  reports by `cadex run`, never the network): 6 agents working at once
  (the race's 3 and 3 of the run's, sending a heartbeat every 20 s), and a
  chain of 2 that reports done; the race's board and the run's page open.
  The app's memory and CPU, every agent started, the chain done, and not
  one network connection nor Keychain file open (lsof: fs_usage needs root).

Each test Cadex has its own folders, a fake account that trusts the test
repository, and its own LaunchAgent folder and label: the owner's state,
accounts and launchd are never touched."""
import json
import os
import pathlib
import subprocess
import sqlite3
import tempfile
import time

HERE = pathlib.Path(__file__).resolve().parent
LABEL = "app.cadex.perf-automations"


def folders(base):
    """The test instance's own orchestration, prompts, kit, notes, usage and LaunchAgent folders."""
    names = {"CADEX_ORCHESTRATION_DIR": "orch", "CADEX_PROMPTS_DIR": "prompts", "CADEX_KIT_DIR": "kit",
             "CADEX_USAGE_DIR": "usage", "CADEX_LAUNCH_AGENTS_DIR": "la"}
    env = {key: f"{base}/{name}" for key, name in names.items()}
    for path in env.values():
        os.makedirs(path, exist_ok=True)
    env["CADEX_WORKTREES_FILE"] = f"{base}/worktrees.json"
    env["CADEX_LAUNCH_LABEL"] = LABEL
    return env


def launchd_has_job():
    return subprocess.run(["launchctl", "print", f"gui/{os.getuid()}/{LABEL}"], capture_output=True).returncode == 0


def off_scenario(perf):
    """orchestration.enabled and orchestration.automations off: no state, no LaunchAgent."""
    base = tempfile.mkdtemp(prefix="cadex-perf24-")
    env = folders(base)

    def run(app):
        app.sample(16)
        tail = app.sample(10)
        files = sum(len(os.listdir(env[key])) for key in ["CADEX_ORCHESTRATION_DIR", "CADEX_LAUNCH_AGENTS_DIR"])
        return {"orch_off_mb": max(m for m, _ in tail), "orch_off_cpu": perf.avg([c for _, c in tail]),
                "orch_off_files": files, "orch_off_launchd_jobs": 1 if launchd_has_job() else 0}
    try:
        return perf.scenario("orchestration-off", "idle", perf.ROOT, run, extra_env=env)
    finally:
        subprocess.run(["rm", "-rf", base])


def make_repo(base):
    repo = os.path.realpath(f"{base}/repo")
    os.makedirs(repo)
    for words in (["init", "-q", "-b", "main"], ["add", "."], ["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", "init"]):
        subprocess.run(["git", *words], cwd=repo, check=True, capture_output=True)
    account = f"{base}/account"
    os.makedirs(account)
    trusted = {repo: {"hasTrustDialogAccepted": True}, repo + ".worktrees": {"hasTrustDialogAccepted": True}}
    pathlib.Path(account, ".claude.json").write_text(json.dumps({"projects": trusted}))
    return repo, account


def on_scenario(perf):
    base = os.path.realpath(tempfile.mkdtemp(prefix="cadex-perf24-"))
    env = folders(base)
    repo, account = make_repo(base)
    agent = {"account": account, "model": "haiku"}
    race = {"name": "perf-race", "prompt": "FAKE-HEARTBEAT race", "repository": repo, "agents": [agent] * 3,
            "budgetUsd": 1, "maxMinutes": 10}
    tasks = [{"title": f"long{n}", "spec": "FAKE-HEARTBEAT"} for n in range(1, 4)]
    tasks += [{"title": "first", "spec": "FAKE-DONE"}, {"title": "second", "spec": "FAKE-DONE", "after": ["first"]}]
    run_spec = {"name": "perf-run", "repository": repo, "budgetUsd": 1, "maxMinutes": 10, "tasks": tasks, "agent": agent}
    pathlib.Path(base, "race.json").write_text(json.dumps(race))
    pathlib.Path(base, "run.json").write_text(json.dumps(run_spec))
    cadex = perf.APP / "Contents/Helpers/cadex"
    env.update({"CADEX_PERF_RACE": f"{base}/race.json", "CADEX_PERF_RUN": f"{base}/run.json",
                "CADEX_CLAUDE_BIN": str(HERE / "fake_claude.py"), "FAKE_CADEX": str(cadex)})
    settings = {"orchestration": {"enabled": True, "maxAgents": 8}, "memory": {"enabled": False}, "agents": {"history": False}}

    def run(app):
        app.sample(30)  # the race and the run start at 3 s; the chain's two take turns
        tail = app.sample(30)
        agents = subprocess.run(["pgrep", "-f", str(HERE / "fake_claude.py") + " --settings " + env["CADEX_KIT_DIR"]],
                                capture_output=True, text=True).stdout.split()
        net = subprocess.run(["lsof", "-a", "-i", "-p", str(app.process.pid)], capture_output=True, text=True).stdout.strip().splitlines()
        files = subprocess.run(["lsof", "-p", str(app.process.pid)], capture_output=True, text=True).stdout
        state = {}
        db = sqlite3.connect(f"{env['CADEX_ORCHESTRATION_DIR']}/state.sqlite")
        for (line,) in db.execute("select json from tasks"):
            task = json.loads(line)
            state[task["title"]] = task["state"]
        missing = [title for title, want in [("first", "done"), ("second", "done"), ("long1", "dispatched"),
                                             ("long2", "dispatched"), ("long3", "dispatched")] if state.get(title) != want]
        contenders = db.execute("select count(*) from contenders").fetchone()[0]
        return {"orch_on_mb": max(m for m, _ in tail), "orch_on_cpu": perf.avg([c for _, c in tail]),
                "orch_agents_missing": max(0, 8 - len(agents)) + max(0, 3 - contenders),
                "orch_run_missing": len(missing),
                "orch_network": max(0, len(net) - 1), "orch_keychain": files.count(".keychain")}
    try:
        return perf.scenario("orchestration-on", "idle", repo, run, settings=settings, extra_env=env)
    finally:
        subprocess.run(["pkill", "-f", env["CADEX_KIT_DIR"]], capture_output=True)
        subprocess.run(["rm", "-rf", base])
