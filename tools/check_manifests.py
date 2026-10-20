"""Fails when a CLAUDE.md or a plan in docs/plans breaks the repository rules.

Two checks, both cheap and both catching the usual way manifests rot:
- every CLAUDE.md has the four sections, in order;
- every path cited between backticks exists, resolved from the manifest's folder
  or from the repository root.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SECTIONS = ["O que eu quero", "O que eu não quero", "Como eu quero", "Como validar"]
SKIP_DIRS = {".git", "node_modules", ".zig-cache", "zig-out", ".build", "DerivedData"}

# A backtick token counts as a path when it has a slash or a file extension.
# `path:symbol` also checks that the symbol appears in the file.
PATH_TOKEN = re.compile(r"`([\w./-]+(?:/|\.[A-Za-z0-9]+))(?::([A-Za-z_]\w*))?`")


def manifests():
    for path in ROOT.rglob("CLAUDE.md"):
        if not SKIP_DIRS.intersection(path.relative_to(ROOT).parts):
            yield path
    # Plans follow the same four-section format (docs/plans/README.md).
    yield from (ROOT / "docs" / "plans").glob("*.md")


def section_errors(text):
    headings = re.findall(r"^## (.+?)\s*$", text, flags=re.MULTILINE)
    found = [h for h in headings if h in SECTIONS]
    if found != SECTIONS:
        return [f"seções esperadas {SECTIONS}, encontradas {found}"]
    return []


def resolve(manifest, cited):
    for base in (manifest.parent, ROOT):
        candidate = (base / cited).resolve()
        if candidate.exists():
            return candidate
    return None


def pointer_errors(manifest, text):
    errors = []
    for cited, symbol in PATH_TOKEN.findall(text):
        target = resolve(manifest, cited)
        if target is None:
            errors.append(f"caminho não existe: {cited}")
        elif symbol and symbol not in target.read_text(errors="ignore"):
            errors.append(f"símbolo {symbol} não encontrado em {cited}")
    return errors


def missing_manifests():
    """Every feature folder, in the core and in each app, has its CLAUDE.md
    (the root CLAUDE.md; explorer and search on Windows went without one
    until 2026-10-20)."""
    for features in [ROOT / "core" / "features", *(ROOT / "apps").glob("*/features")]:
        for folder in sorted(p for p in features.iterdir() if p.is_dir()):
            if not (folder / "CLAUDE.md").exists():
                yield folder.relative_to(ROOT)


def main():
    failures = 0
    for folder in missing_manifests():
        print(f"{folder}: feature sem CLAUDE.md")
        failures += 1
    for manifest in sorted(manifests()):
        text = manifest.read_text()
        for error in section_errors(text) + pointer_errors(manifest, text):
            print(f"{manifest.relative_to(ROOT)}: {error}")
            failures += 1
    if failures:
        print(f"{failures} problema(s) nos manifestos")
        return 1
    print("manifestos ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
