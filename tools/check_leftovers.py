#!/usr/bin/env python3
"""Nothing of the old shell stays behind (docs/adr/0035-work-frame.md, plan
25; the owner, 2026-11-17: "a gente tem que tomar cuidado para não deixar
cascas do que é hoje para trás").

docs/design/work-frame/inventory.md lists every piece of today's shell with
its fate and the plan that removes it. A row whose state is `saiu` (gone)
must really be gone:
- `arquivo`: no path between backticks in the row exists;
- `comando`: no id between backticks appears as a string literal in
  apps/macos/, core/ or tools/ (this file and the inventory aside);
- `chave`: no key between backticks appears in apps/macos/, except on a line
  marked `// migração 0035`;
- `gancho`: no variable between backticks appears in apps/macos/ nor in
  tools/perf/;
- `spec` and `trecho`: the text between quotes in the row does not appear in
  the file between backticks.
`--self-test` runs the checks against a made-up tree.
"""
import pathlib
import re
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
INVENTORY = "docs/design/work-frame/inventory.md"
KINDS = {"arquivo", "comando", "chave", "gancho", "spec", "trecho"}
STATES = {"fica", "muda", "sai", "saiu"}
SKIP_DIRS = {".build", ".zig-cache", "zig-out", "target", "node_modules", ".git", ".claude"}


def rows(text):
    """(line number, kind, piece, state, plan) of every table row of a known kind."""
    for n, line in enumerate(text.splitlines(), 1):
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) == 5 and cells[0] in KINDS:
            yield n, cells[0], cells[1], cells[2], cells[4]


def files_under(root, parts, suffixes=None):
    for part in parts:
        base = root / part
        if not base.exists():
            continue
        for p in base.rglob("*"):
            if p.is_file() and not (set(p.relative_to(root).parts) & SKIP_DIRS):
                if suffixes is None or p.suffix in suffixes:
                    yield p


def found(root, needle, parts, skip=(), allow_marker=None):
    """Files (relative) where `needle` appears, leaving out `skip` and marked lines."""
    hits = []
    for p in files_under(root, parts, {".swift", ".zig", ".py", ".rs", ".sh", ".json"}):
        rel = str(p.relative_to(root))
        if rel in skip:
            continue
        try:
            text = p.read_text()
        except UnicodeDecodeError:
            continue
        for line in text.splitlines():
            if needle in line and not (allow_marker and allow_marker in line):
                hits.append(rel)
                break
    return hits


def check(root):
    inventory = root / INVENTORY
    text = inventory.read_text()
    me = str(pathlib.Path(__file__).resolve().relative_to(ROOT)) if root == ROOT else "tools/check_leftovers.py"
    skip = {INVENTORY, me}
    problems = []
    for n, kind, piece, state, plan in rows(text):
        where = f"{INVENTORY}:{n}"
        if state not in STATES:
            problems.append(f"{where}: estado '{state}' (use {', '.join(sorted(STATES))})")
            continue
        if state != "saiu":
            continue
        ticks = re.findall(r"`([^`]+)`", piece)
        quotes = re.findall(r'"([^"]+)"', piece)
        if not ticks:
            problems.append(f"{where}: linha 'saiu' sem nada entre crases para conferir")
            continue
        if kind == "arquivo":
            problems += [f"{where}: ainda existe: {t}" for t in ticks if (root / t).exists()]
        elif kind == "comando":
            for t in ticks:
                problems += [f"{where}: o comando {t} ainda aparece em {h}"
                             for h in found(root, f'"{t}"', ["apps/macos", "core", "tools"], skip)]
        elif kind == "chave":
            for t in ticks:
                problems += [f"{where}: a chave {t} ainda aparece em {h}"
                             for h in found(root, t, ["apps/macos"], skip, "// migração 0035")]
        elif kind == "gancho":
            for t in ticks:
                problems += [f"{where}: o gancho {t} ainda aparece em {h}"
                             for h in found(root, t, ["apps/macos", "tools/perf"], skip)]
        else:
            if not quotes:
                problems.append(f"{where}: linha 'saiu' de {kind} sem o texto entre aspas")
                continue
            for t in ticks:
                target = root / t
                body = target.read_text() if target.exists() else ""
                problems += [f"{where}: \"{q}\" ainda está em {t}" for q in quotes if q in body]
    return problems


def self_test():
    with tempfile.TemporaryDirectory() as d:
        root = pathlib.Path(d)
        (root / "docs/design/work-frame").mkdir(parents=True)
        (root / "apps/macos/app").mkdir(parents=True)
        (root / "tools/perf").mkdir(parents=True)
        (root / "docs/spec").mkdir(parents=True)
        (root / "apps/macos/app/Old.swift").write_text("let x = 1\n")
        (root / "apps/macos/app/Commands.swift").write_text('Command(id: "old.cmd")\nlet k = "old.key" // migração 0035\nlet j = "other.key"\n')
        (root / "tools/perf/run.py").write_text('env["CADEX_PERF_OLD"] = "1"\n')
        (root / "docs/spec/a.md").write_text("a fileira de ícones some\n")
        table = "| tipo | peça | estado | destino | plano |\n|---|---|---|---|---|\n"
        bad = table + "\n".join([
            "| arquivo | `apps/macos/app/Old.swift` | saiu | x | 26 |",
            "| comando | `old.cmd` | saiu | x | 26 |",
            "| chave | `old.key` | saiu | x | 26 |",
            "| chave | `other.key` | saiu | x | 26 |",
            "| gancho | `CADEX_PERF_OLD` | saiu | x | 26 |",
            "| spec | \"fileira de ícones\" em `docs/spec/a.md` | saiu | x | 26 |",
            "| arquivo | `apps/macos/app/Gone.swift` | saiu | x | 26 |",
            "| arquivo | `apps/macos/app/Old.swift` | talvez | x | 26 |",
        ]) + "\n"
        (root / INVENTORY).write_text(bad)
        got = check(root)
        expect = ["ainda existe: apps/macos/app/Old.swift", "o comando old.cmd", "a chave other.key",
                  "o gancho CADEX_PERF_OLD", "\"fileira de ícones\" ainda está", "estado 'talvez'"]
        missing = [e for e in expect if not any(e in g for g in got)]
        wrong = [g for g in got if "old.key" in g or "Gone.swift" in g]
        if missing or wrong or len(got) != len(expect):
            print("check_leftovers --self-test falhou:", missing, wrong, got)
            sys.exit(1)


def main():
    if "--self-test" in sys.argv:
        self_test()
        return
    problems = check(ROOT)
    for p in problems:
        print(p)
    if problems:
        print(f"{len(problems)} peça(s) da casca velha ainda no código")
        sys.exit(1)


if __name__ == "__main__":
    main()
