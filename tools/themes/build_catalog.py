"""Builds the Cadex theme catalog from three sources (docs/spec/themes.md,
docs/adr/0017-base16-themes.md):

- the official palettes of open-source themes in official-palettes.json,
  each read from its project's own terminal files (sources inside);
- the theme presets of tweakcn (Apache-2.0), utils/theme-presets.ts at commit
  TWEAKCN_COMMIT, minus the ones cut as near duplicates (CUT);
- the base16 and base24 schemes of tinted-theming/schemes (MIT) at commit
  TINTED_COMMIT, minus ports of the official ones.

    python3 tools/themes/build_catalog.py path/to/theme-presets.ts path/to/schemes

writes apps/macos/features/themes/Resources/catalog.json. A theme whose
terminal text is not readable on its background is refused; interface
colors below the minimum contrast are moved in OKLCH lightness until they
pass. A theme too close to one already in is left out, unless official.
"""
import json
import math
import sys
from pathlib import Path

import tinted
import tweakcn
from colors import contrast, mix, readable, to_oklch

HERE = Path(__file__).resolve().parent
OUT = HERE.parent.parent / "apps/macos/features/themes/Resources/catalog.json"
TWEAKCN_COMMIT = "a3b47b37cba97dd637de517aab52c45ec0f83456"
TINTED_COMMIT = "3ac91137e879502c442ab89ba0f1a98077d0da9d"
# Near duplicates cut on 2026-10-19 with the owner, by color distance and a
# contact sheet: the official Catppuccin replaces tweakcn's.
CUT = {"catppuccin", "mono", "notebook", "pastel-dreams", "mocha-mousse", "clean-slate"}
DEFAULT = "caffeine"
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


def signature(family):
    """OKLab points of the colors that make a theme's look."""
    points = []
    for mode in ("dark", "light"):
        v = family.get(mode)
        if not v:
            continue
        colors = [v["terminal"]["background"], v["terminal"]["foreground"], v["interface"]["accent"]] + v["terminal"]["ansi"][1:7]
        for c in colors:
            L, C, H = to_oklch(c)
            points.append((L, C * math.cos(math.radians(H)), C * math.sin(math.radians(H))))
    return points


def too_close(a, b):
    if len(a) != len(b):
        return False
    return sum(math.dist(p, q) for p, q in zip(a, b)) / len(a) < NEAR


def build(tweakcn_path, schemes_path):
    descriptions = json.loads((HERE / "descriptions.json").read_text())
    candidates = []
    for theme in json.loads((HERE / "official-palettes.json").read_text())["themes"]:
        candidates.append({"id": theme["id"], "name": theme["name"], "description": descriptions[theme["id"]],
                           "source": "official", **{m: from_official(v) for m, v in theme["variants"].items()}})
    for key, (label, modes) in tweakcn.read(tweakcn_path).items():
        if key not in CUT:
            candidates.append({"id": key, "name": label, "description": descriptions[key], "source": "tweakcn",
                               **{m: tweakcn.variant(c) for m, c in modes.items() if c}})
    candidates += tinted.read(schemes_path)
    families, seen, refused = [], [], []
    for f in candidates:
        for mode in ("dark", "light"):
            if mode in f and not checked(f[mode]):
                refused.append(f"{f['id']} ({mode})")
                del f[mode]
        if "dark" not in f and "light" not in f:
            continue
        sig = signature(f)
        # Official variants stay even when close (Gruvbox hard, medium
        # and soft differ only in the background, by design).
        close = f["source"] != "official" and any(too_close(sig, s) for s in seen)
        if any(f["id"] == g["id"] for g in families) or close:
            continue
        families.append(f)
        seen.append(sig)
    families.sort(key=lambda f: (f["id"] != DEFAULT, f["name"].lower()))
    return families, refused


if __name__ == "__main__":
    catalog, refused = build(sys.argv[1], sys.argv[2])
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps({"tweakcnCommit": TWEAKCN_COMMIT, "tintedCommit": TINTED_COMMIT, "families": catalog},
                              separators=(",", ":"), ensure_ascii=False) + "\n")
    print(f"{len(catalog)} temas em {OUT}; recusados por contraste: {', '.join(refused) or 'nenhum'}")
