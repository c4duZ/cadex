#!/usr/bin/env python3
"""The memory's search measured (plan 22 phase D): the repository's ADRs and
specs written as wiki pages, 30 questions a developer of Cadex would ask,
and where the right page lands with text search only (FTS5, the engine with
--no-embeddings) and with the hybrid search (the local model on).

    python3 tools/memory_eval.py <cadex-memory> <models folder>

<models folder> holds all-MiniLM-L6-v2/ (the engine's <data>/models); the
engines run in a temporary folder and leave nothing behind. Prints hit@1,
hit@3 and hit@5 for each mode and the rank of every question.
"""

import http.client
import json
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOKEN = "e" * 64
PROJECT = "cadex-eval"

# (question, the pages that answer it). Worded as asked, not as titled.
QUESTIONS = [
    ("por que não usamos Electron", ["adr/0001"]),
    ("como o Swift conversa com o núcleo", ["adr/0002"]),
    ("qual biblioteca interpreta as sequências de escape do terminal", ["adr/0003"]),
    ("podemos copiar código de outro app", ["adr/0004"]),
    ("how does the user run any action from the keyboard", ["adr/0005", "spec/command-palette"]),
    ("dá para editar código no editor", ["adr/0006", "spec/editor"]),
    ("como o usuário instala o app", ["adr/0007"]),
    ("which icon set do we use", ["adr/0008"]),
    ("qual motor de expressões regulares usamos", ["adr/0013", "adr/0009"]),
    ("como o markdown vira HTML", ["adr/0010", "spec/markdown"]),
    ("o app do Windows usa qual API gráfica", ["adr/0012"]),
    ("como funciona a tradução da interface", ["adr/0015"]),
    ("how does the app update itself", ["adr/0016", "spec/updates"]),
    ("de onde vêm os temas de cores", ["adr/0017", "spec/themes"]),
    ("como o dono escolhe um elemento da página para o agente", ["adr/0018", "spec/preview"]),
    ("o Cadex roda modelo de IA", ["adr/0019", "adr/0028"]),
    ("como abrir o Claude numa conta sem prompt", ["adr/0021"]),
    ("what keeps terminal sessions alive when the window closes", ["adr/0022", "spec/terminal"]),
    ("como responder um pedido de permissão do agente", ["adr/0023"]),
    ("o agente consegue abrir um arquivo ao lado do terminal", ["adr/0024", "spec/agent-tools"]),
    ("can the agent click buttons in the browser preview", ["adr/0025", "spec/preview"]),
    ("o agente pode usar outros apps do Mac", ["adr/0026", "spec/computer-use"]),
    ("como sabemos quais linhas o agente escreveu", ["adr/0027", "spec/review"]),
    ("onde fica a memória entre sessões", ["adr/0028", "spec/memory"]),
    ("keep the computer from sleeping while a build runs", ["spec/power"]),
    ("como trocar de branch e fazer commit", ["spec/source-control"]),
    ("ver o grafo de commits", ["spec/git-history"]),
    ("conectar num servidor remoto", ["spec/ssh"]),
    ("salvar um grupo de abas para usar depois", ["spec/spaces"]),
    ("criar uma worktree para cada tarefa", ["spec/worktrees"]),
]


class UnixHTTP(http.client.HTTPConnection):
    def __init__(self, path):
        super().__init__("localhost", timeout=120)
        self.path = path

    def connect(self):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(120)
        self.sock.connect(self.path)


def tool(sock, name, arguments):
    body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": "tools/call",
                       "params": {"name": name, "arguments": arguments}})
    conn = UnixHTTP(sock)
    conn.request("POST", "/mcp", body, {"X-Cadex-Token": TOKEN, "Content-Type": "application/json",
                                        "Accept": "application/json, text/event-stream"})
    answer = json.loads(conn.getresponse().read())
    result = answer.get("result") or {}
    text = (result.get("content") or [{}])[0].get("text", "")
    if "error" in answer or result.get("isError"):
        return None, text or json.dumps(answer.get("error"))
    return json.loads(text), None


def start(engine, folder, embeddings):
    os.makedirs(folder + "/sessions")
    with open(folder + "/sessions/k.token", "w") as f:
        f.write(TOKEN)
    args = [engine, "--socket", folder + "/m.sock", "--data-dir", folder + "/data",
            "--tokens-dir", folder + "/sessions", "--keep-alive"]
    if not embeddings:
        args.append("--no-embeddings")
    proc = subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                            env={**os.environ, "HOME": folder, "CADEX_MEMORY_LOG": "warn"})
    for _ in range(400):
        if os.path.exists(folder + "/m.sock"):
            return proc
        time.sleep(0.05)
    raise SystemExit("the engine did not start")


def pages():
    for kind in ("adr", "spec"):
        for name in sorted(os.listdir(f"{ROOT}/docs/{kind}")):
            if name.endswith(".md") and name != "README.md":
                yield f"{kind}/{name[:-3]}", open(f"{ROOT}/docs/{kind}/{name}").read()


def run(engine, models, embeddings):
    folder = tempfile.mkdtemp(prefix="cadex-eval-")
    try:
        if embeddings:
            shutil.copytree(models, folder + "/data/models")
        proc = start(engine, folder, embeddings)
        sock = folder + "/m.sock"
        scope = {"workspace": "default", "project": PROJECT}
        tool(sock, "memory_status", {})
        conn = UnixHTTP(sock)  # the project comes from a session in a folder named after it
        repo = folder + "/" + PROJECT
        os.makedirs(repo)
        subprocess.run(["git", "init", "-q"], cwd=repo, check=True)
        conn.request("POST", f"/hook?event=session-start&agent=claude-code&cwd={repo}&project_strategy=repo-root&ingest_key=e1",
                     json.dumps({"session_id": "eval", "cwd": repo}), {"X-Cadex-Token": TOKEN, "Content-Type": "application/json"})
        conn.getresponse().read()
        time.sleep(1)
        started = time.time()
        for path, body in pages():
            _, error = tool(sock, "memory_write_page", {**scope, "path": f"docs/{path}.md", "body": body})
            if error:
                raise SystemExit(f"{path}: {error}")
        write_s = time.time() - started
        ranks, query_ms = [], []
        for question, wanted in QUESTIONS:
            t = time.time()
            found, error = tool(sock, "memory_query", {**scope, "query": question, "limit": 10})
            query_ms.append((time.time() - t) * 1000)
            hits = [] if error else [h["path"] for h in found.get("hits", [])]
            rank = next((i + 1 for i, p in enumerate(hits) if any(p.startswith(f"docs/{w}") for w in wanted)), None)
            ranks.append((question, rank, error))
        proc.terminate()
        proc.wait(10)
        return ranks, write_s, sorted(query_ms)[len(query_ms) // 2]
    finally:
        shutil.rmtree(folder, ignore_errors=True)


def main():
    engine, models = sys.argv[1], sys.argv[2]
    results = {}
    for mode, embeddings in (("fts", False), ("hybrid", True)):
        results[mode] = run(engine, models, embeddings)
    for mode, (ranks, write_s, median_ms) in results.items():
        at = lambda k: sum(1 for _, r, _ in ranks if r and r <= k)
        errors = sum(1 for _, _, e in ranks if e)
        print(f"{mode:7} hit@1 {at(1):2}/30  hit@3 {at(3):2}/30  hit@5 {at(5):2}/30  "
              f"none {sum(1 for _, r, _ in ranks if not r):2}  errors {errors}  "
              f"write {write_s:.1f}s  query median {median_ms:.0f} ms")
    print()
    for i, (question, _) in enumerate(QUESTIONS):
        fts, hybrid = results["fts"][0][i], results["hybrid"][0][i]
        show = lambda r: str(r[1]) if r[1] else ("err" if r[2] else "-")
        print(f"{show(fts):>4} {show(hybrid):>4}  {question}")


if __name__ == "__main__":
    main()
