"""Plan 27's scenario for `make perf` (tools/perf/run.py): the work's tree with many projects
and tasks (docs/spec/sidebar.md). Eight repositories, each with six task worktrees and a
terminal tab open in it, as projects of a test instance (its own projects.json): the tree lists
every worktree off the main thread and redraws on each change. The app's weight and CPU
against the idle app."""
import json
import os
import subprocess
import tempfile

PROJECTS = 8
TASKS = 6


def git(*args, cwd):
    subprocess.run(["git", "-c", "user.name=perf", "-c", "user.email=perf@example.invalid", *args],
                   cwd=cwd, check=True, capture_output=True)


def make_projects(base):
    """The repositories and their worktrees, and the projects.json that opens them."""
    projects = []
    for n in range(PROJECTS):
        repo = f"{base}/repo{n}"
        os.makedirs(repo)
        with open(f"{repo}/README.md", "w") as f:
            f.write("perf\n")
        git("init", "-q", "-b", "main", cwd=repo)
        git("add", "-A", cwd=repo)
        git("commit", "-q", "-m", "init", cwd=repo)
        for t in range(TASKS):
            git("worktree", "add", "-q", "-b", f"task-{t}", f"{base}/repo{n}.worktrees/task-{t}", cwd=repo)
        layout = {"pane": {"folder": repo}}
        projects.append({"name": f"repo{n}", "folder": repo,
                         "tabs": {"items": [{"terminal": {"layout": layout, "focus": 0}}], "active": 0}})
    with open(f"{base}/projects.json", "w") as f:
        json.dump({"version": 1, "projects": projects, "active": 0}, f)
    return f"{base}/projects.json"


def tree_scenario(perf):
    base = tempfile.mkdtemp(prefix="cadex-perf27-")
    try:
        projects = make_projects(base)

        def run(app):
            app.sample(16)
            tail = app.sample(10)
            return {"tree_mb": max(m for m, _ in tail), "tree_cpu": perf.avg([c for _, c in tail])}
        # CADEX_PROJECTS_FILE after the instance's own: the test's projects open.
        return perf.scenario("tree", "idle", perf.ROOT, run, extra_env={"CADEX_PROJECTS_FILE": projects})
    finally:
        subprocess.run(["rm", "-rf", base])
