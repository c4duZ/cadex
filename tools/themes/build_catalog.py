"""Builds the Cadex theme catalog (docs/spec/themes.md, docs/adr/0017-base16-themes.md) from
the official palettes of open-source themes in official-palettes.json, each read from its
project's own terminal files (sources inside). The tweakcn presets and the base16/base24
schemes left on 2026-11-17: hundreds of near-alike themes the owner did not use.

    python3 tools/themes/build_catalog.py

writes apps/macos/features/themes/Resources/catalog.json. A theme whose terminal text is not
readable on its background is refused; interface colors below the minimum contrast are moved in
OKLCH lightness until they pass.
"""
import json
import sys
from pathlib import Path

from colors import contrast, mix, readable

HERE = Path(__file__).resolve().parent
OUT = HERE.parent.parent / "apps/macos/features/themes/Resources/catalog.json"
# WCAG ratios (plan 15: "contraste sempre conferido"). Terminal text is
# refused below its minimum: moving it would change the theme's look. 4.0,
# not AA's 4.5: the official Solarized Light is 4.1 (2026-10-20), and
# terminal.minimumContrast lets the user raise any theme.
TERMINAL_TEXT = 4.0
TEXT = 4.5
SECONDARY = 3.0
ACCENT = 2.0
# Mean OKLab distance under which two themes look the same (the cut of
# 2026-10-19 measured near duplicates around 0.02 to 0.03).
NEAR = 0.025


def from_official(v):
    ui = v["ui"]
    return {
        "interface": {
            "chrome": ui["surface"], "panel": v["background"], "panelBorder": ui["border"],
            "tabActive": mix(ui["surface"], ui["accent"], 0.22), "field": ui["surface"],
            "text": v["foreground"], "secondaryText": ui["muted"], "accent": ui["accent"],
        },
        "terminal": {"background": v["background"], "foreground": v["foreground"], "cursor": v["cursor"],
                     "selection": v["selection"], "ansi": v["ansi"]},
    }


def checked(variant):
    """The variant with its interface colors readable, or None."""
    ui, term = variant["interface"], variant["terminal"]
    if contrast(term["foreground"], term["background"]) < TERMINAL_TEXT:
        return None
    for key, ratio in (("text", TEXT), ("secondaryText", SECONDARY)):
        # Text sits on both: moved against one, then the other.
        fixed = readable(ui[key], ui["panel"], ratio)
        fixed = fixed and readable(fixed, ui["chrome"], ratio)
        if fixed is None or contrast(fixed, ui["panel"]) < ratio:
            return None
        ui[key] = fixed
    ui["accent"] = readable(ui["accent"], ui["chrome"], ACCENT) or ui["accent"]
    ui["tabActive"] = mix(ui["chrome"], ui["accent"], 0.22)
    return variant


def build():
    descriptions = json.loads((HERE / "descriptions.json").read_text())
    families, refused = [], []
    for theme in json.loads((HERE / "official-palettes.json").read_text())["themes"]:
        f = {"id": theme["id"], "name": theme["name"], "description": descriptions[theme["id"]],
             "source": "official", **{m: from_official(v) for m, v in theme["variants"].items()}}
        for mode in ("dark", "light"):
            if mode in f and not checked(f[mode]):
                refused.append(f"{f['id']} ({mode})")
                del f[mode]
        if "dark" in f or "light" in f:
            families.append(f)
    families.sort(key=lambda f: f["name"].lower())
    return families, refused


if __name__ == "__main__":
    catalog, refused = build()
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps({"families": catalog}, separators=(",", ":"), ensure_ascii=False) + "\n")
    print(f"{len(catalog)} temas em {OUT}; recusados por contraste: {', '.join(refused) or 'nenhum'}")
