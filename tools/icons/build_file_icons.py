"""Builds the file and folder icons of the explorer and the tabs from the
Material Icon Theme (MIT, docs/adr/0011-material-file-icons.md):

    python3 -I tools/icons/build_file_icons.py path/to/vscode-material-icon-theme

reads src/core/icons/fileIcons.ts and folderIcons.ts of a checkout at
COMMIT, keeps the icons in FILES and FOLDERS (the ones a developer's tree
shows; the whole pack is 906), and writes them as vector PDFs (the app runs
from macOS 13, which does not read SVG; svg_to_pdf.swift converts) with
map.json to apps/macos/shared/icons/Resources/FileIcons. Names and folders
not listed fall back to Phosphor in the app.
"""
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
OUT = HERE.parent.parent / "apps/macos/shared/icons/Resources/FileIcons"
COMMIT = "13025adc5ad10a5cc649528a2c1edec93069f1b9"

FILES = """
docker makefile git tune license certificate readme markdown changelog contributing todo claude
python python-misc go rust swift zig javascript typescript react react_ts json yaml toml xml html
css sass c cpp h hpp csharp java kotlin ruby php lua dart elixir haskell scala r julia perl
console powershell nodejs npm pnpm yarn bun deno lock settings editorconfig vscode vue svelte astro
tailwindcss vite next nuxt webpack babel eslint prettier jest vitest nix terraform kubernetes
prisma graphql database image svg video audio pdf zip log document key font exe http table
github-actions-workflow uv gradle cmake proto wasm jupyter apple
""".split()

FOLDERS = """
folder-src folder-test folder-docs folder-github folder-git folder-node folder-images
folder-config folder-scripts folder-lib folder-dist folder-app folder-components folder-public
folder-vscode folder-tools folder-core folder-api folder-android folder-ios folder-macos
folder-windows folder-docker folder-database folder-css folder-utils folder-helper folder-temp
folder-log folder-plugin folder-server folder-client folder-views folder-template folder-packages
folder-home folder-include folder-shared folder-features folder-claude folder-environment
folder-robot folder-rust folder-resource folder-assets folder-target folder-coverage folder-mock
folder-i18n folder-hook folder-middleware folder-routes folder-models folder-services
folder-controller folder-interfaces folder-types folder-layout folder-theme folder-fonts
folder-audio folder-video folder-secure folder-keys folder-benchmark folder-examples folder-cli
""".split()


def entries(source):
    """(icon, {field: [strings]}) for each `name: '...'` block of an icon list."""
    # Entries come on one line or on several; each runs to the next name.
    marks = list(re.finditer(r"\{\s*name: '([^']+)'", source))
    for i, mark in enumerate(marks):
        end = marks[i + 1].start() if i + 1 < len(marks) else len(source)
        icon, body = mark.group(1), source[mark.end():end]
        fields = {}
        for field in ("fileExtensions", "fileNames", "folderNames"):
            m = re.search(field + r": \[(.*?)\]", body, re.S)
            fields[field] = re.findall(r"'([^']+)'", m.group(1)) if m else []
        yield icon, fields


def build(repo):
    repo = Path(repo)
    files = (repo / "src/core/icons/fileIcons.ts").read_text()
    folders = (repo / "src/core/icons/folderIcons.ts").read_text()
    out = {"extensions": {}, "names": {}, "folders": {}}
    kept = set()
    for icon, f in entries(files):
        if icon not in FILES:
            continue
        for ext in f["fileExtensions"]:
            out["extensions"].setdefault(ext.lower(), icon)
        for name in f["fileNames"]:
            out["names"].setdefault(name.lower(), icon)
        kept.add(icon)
    # Only the "specific" folder theme, the pack's default one.
    specific = folders.split("name: 'classic'")[0]
    for icon, f in entries(specific):
        if icon not in FOLDERS:
            continue
        for name in f["folderNames"]:
            out["folders"].setdefault(name.lower(), icon)
        kept.add(icon)
    missing = sorted(set(FILES + FOLDERS) - kept)
    if missing:
        print("sem regra no pacote (ficam de fora):", " ".join(missing))
    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir(parents=True)
    for icon in sorted(kept):
        svg = repo / "icons" / (icon + ".svg")
        if not svg.exists():
            print("sem desenho:", icon)
            continue
        shutil.copy(svg, OUT / svg.name)
    subprocess.run(["swift", str(HERE / "svg_to_pdf.swift"), str(OUT)], check=True)
    shutil.copy(repo / "LICENSE", OUT.parent / "LICENSE-MaterialIconTheme.txt")
    (OUT / "map.json").write_text(json.dumps(out, indent=1, sort_keys=True) + "\n")
    size = sum(p.stat().st_size for p in OUT.iterdir())
    print(f"{len(kept)} ícones, {size // 1024} KB em {OUT}")


if __name__ == "__main__":
    build(sys.argv[1])
