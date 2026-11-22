#!/usr/bin/env python3
"""docs/guides/commands.md: every command of the Mac app with its title and default shortcut,
read from the Swift code (each `Command(id: ...)`), for whoever sets `shortcuts` in settings.json
by hand or through an agent (docs/guides/settings.md; the owner, 2026-11-22: Cadex configured by
agents). `--check` fails when the file is not what the code says, so it never goes stale.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCES = [ROOT / "apps/macos/app", ROOT / "apps/macos/features", ROOT / "apps/macos/shared"]
OUT = ROOT / "docs/guides/commands.md"

# `Command(id: "x", title: …)` and the edit commands' `.responder("x", T("Title", …), …)`.
COMMAND = re.compile(r'(?:Command\(\s*id:\s*|\.responder\(\s*)"([a-z][A-Za-z0-9.-]*)"')
TITLE = re.compile(r'(?:title:\s*|^,\s*)(?:T\(\s*)?"((?:[^"\\]|\\.)*)"')
SHORTCUT = re.compile(r'(?:defaultShortcut|shortcut):\s*"([^"]+)"')

HEADER = """# Os comandos do Cadex

Gerado por `tools/gen_commands.py` a partir do código (não edite à mão; `make manifests` confere).
Toda ação do Cadex é um destes comandos (`../adr/0005-every-action-is-a-command.md`). Use o id
para mudar um atalho na seção `shortcuts` do `settings.json` (`settings.md`, Atalhos): a combinação
aponta para o id, ou `null` para tirar um atalho padrão. O título é o que o ⌘K mostra em inglês.
Um `\\(n)` num atalho é um número (os de ⌘1 a ⌘9). Alguns comandos têm o id montado na hora (um por
tema, por conta, por item da barra de status) e não estão aqui: o ⌘K os mostra.

| id | título | atalho padrão |
|---|---|---|
"""


def commands():
    found = {}
    for base in SOURCES:
        for path in sorted(base.rglob("*.swift")):
            if "tests" in path.relative_to(ROOT).parts or ".build" in path.parts:
                continue
            text = path.read_text(encoding="utf-8")
            starts = [m for m in COMMAND.finditer(text)]
            for index, match in enumerate(starts):
                end = starts[index + 1].start() if index + 1 < len(starts) else len(text)
                body = text[match.end():min(end, match.end() + 1200)]
                title = TITLE.search(body)
                shortcut = SHORTCUT.search(body)
                found.setdefault(match.group(1), (title.group(1) if title else "", shortcut.group(1) if shortcut else ""))
    return found


def render():
    rows = []
    for cid, (title, shortcut) in sorted(commands().items()):
        title = title.replace("|", "\\|").replace("\\(", "(")
        rows.append(f"| `{cid}` | {title} | {'`' + shortcut + '`' if shortcut else ''} |")
    return HEADER + "\n".join(rows) + "\n"


def main():
    text = render()
    if "--check" in sys.argv:
        if not OUT.exists() or OUT.read_text(encoding="utf-8") != text:
            print("docs/guides/commands.md está velho: rode python3 tools/gen_commands.py")
            return 1
        return 0
    OUT.write_text(text, encoding="utf-8")
    print(f"{OUT.relative_to(ROOT)}: {text.count(chr(10)) - HEADER.count(chr(10))} comandos")
    return 0


if __name__ == "__main__":
    sys.exit(main())
