"""Builds the Cadex theme catalog from two sources (docs/spec/themes.md):

- the theme presets of tweakcn (Apache-2.0), utils/theme-presets.ts at commit
  TWEAKCN_COMMIT, minus the ones cut as near duplicates (CUT);
- the official palettes of open-source themes in official-palettes.json,
  each read from its project's own terminal files (sources inside).

    python3 tools/themes/build_catalog.py path/to/theme-presets.ts

writes apps/macos/features/themes/Resources/catalog.json. tweakcn presets
carry no terminal colors: background, text and cursor come from the theme,
red from its "destructive" color, and the rest from a Cadex base palette.
"""
import json
import math
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
OUT = HERE.parent.parent / "apps/macos/features/themes/Resources/catalog.json"
TWEAKCN_COMMIT = "a3b47b37cba97dd637de517aab52c45ec0f83456"
# Near duplicates cut on 2026-10-19 with the owner, by color distance and a
# contact sheet: the official Catppuccin replaces tweakcn's.
CUT = {"catppuccin", "mono", "notebook", "pastel-dreams", "mocha-mousse", "clean-slate"}
DEFAULT = "caffeine"
BASE_ANSI = {
    True: ["#1e1e1e", "#e5636e", "#8cc570", "#e2c06b", "#6ca5f0", "#c27be0", "#5fc3c9", "#c8c8c8",
           "#5c5c5c", "#f07a84", "#a3d98a", "#f0d388", "#8dbbf7", "#d59aec", "#7dd6db", "#f2f2f2"],
    False: ["#1f1f1f", "#c4323f", "#3c8c2c", "#9c7a10", "#2f62c8", "#9b3fb8", "#1f8a92", "#bdbdbd",
            "#6b6b6b", "#d9505c", "#4fa63c", "#b8921e", "#4a7de0", "#b45bd0", "#2fa3ab", "#e6e6e6"],
}


def oklch_hex(text):
    """oklch(L C H) -> sRGB hex, with Björn Ottosson's OKLab matrices."""
    L, C, H = [float(x) for x in text[6:-1].split("/")[0].split()[:3]]
    a, b = C * math.cos(math.radians(H)), C * math.sin(math.radians(H))
    l_ = (L + 0.3963377774 * a + 0.2158037573 * b) ** 3
    m_ = (L - 0.1055613458 * a - 0.0638541728 * b) ** 3
    s_ = (L - 0.0894841775 * a - 1.2914855480 * b) ** 3
    rgb = (4.0767416621 * l_ - 3.3077115913 * m_ + 0.2309699292 * s_,
           -1.2684380046 * l_ + 2.6097574011 * m_ - 0.3413193965 * s_,
           -0.0041960863 * l_ - 0.7034186147 * m_ + 1.7076147010 * s_)
    enc = lambda c: 12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055
    return "#" + "".join(f"{round(min(max(enc(c), 0), 1) * 255):02x}" for c in rgb)


def mix(a, b, t):
    """a moved a fraction t toward b."""
    pa, pb = [int(a[i:i + 2], 16) for i in (1, 3, 5)], [int(b[i:i + 2], 16) for i in (1, 3, 5)]
    return "#" + "".join(f"{round(x + (y - x) * t):02x}" for x, y in zip(pa, pb))


def is_dark(hex_color):
    r, g, b = [int(hex_color[i:i + 2], 16) for i in (1, 3, 5)]
    return 0.2126 * r + 0.7152 * g + 0.0722 * b < 128


def read_tweakcn(path):
    src = Path(path).read_text()
    starts = [(m.group(1), m.group(2), m.start())
              for m in re.finditer(r'^  "?([a-z0-9-]+)"?: \{\n    label: "([^"]+)"', src, re.M)]
    presets = {}
    for i, (key, label, start) in enumerate(starts):
        end = starts[i + 1][2] if i + 1 < len(starts) else len(src)
        body = src[start:end]
        modes = {}
        for mode in ("light", "dark"):
            block = re.search(mode + r": \{(.*?)\n      \}", body, re.S)
            pairs = re.findall(r'"?([a-z0-9-]+)"?: "(#[0-9a-fA-F]{6}|oklch\([^)]*\))"', block.group(1)) if block else []
            modes[mode] = {k: (v if v.startswith("#") else oklch_hex(v)).lower() for k, v in pairs}
        presets[key] = (label, modes)
    return presets


def from_tweakcn(c):
    dark = is_dark(c["background"])
    return {
        "interface": {
            "chrome": c.get("muted", c["background"]), "panel": c["background"],
            "panelBorder": c.get("border", c["background"]),
            # The title bar's color with a little of the theme's primary: the
            # solid tweakcn "accent" painted the active tab amber or green,
            # and neutral gray made every theme look the same (owner's
            # feedback, both on 2026-10-19).
            "tabActive": mix(c.get("muted", c["background"]), c["primary"], 0.22),
            "field": mix(c.get("muted", c["background"]), c["foreground"], 0.06), "text": c["foreground"],
            "secondaryText": c.get("muted-foreground", c["foreground"]), "accent": c["primary"],
        },
        "terminal": {
            "background": c["background"], "foreground": c["foreground"], "cursor": c["primary"],
            "selection": mix(c["background"], c["primary"], 0.3),
            "ansi": [c.get("destructive", x) if i in (1, 9) else x for i, x in enumerate(BASE_ANSI[dark])],
        },
    }


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


def build(tweakcn_path):
    descriptions = json.loads((HERE / "descriptions.json").read_text())
    families = []
    for theme in json.loads((HERE / "official-palettes.json").read_text())["themes"]:
        families.append({"id": theme["id"], "name": theme["name"], "description": descriptions[theme["id"]],
                         "source": "official", **{m: from_official(v) for m, v in theme["variants"].items()}})
    for key, (label, modes) in read_tweakcn(tweakcn_path).items():
        if key in CUT:
            continue
        families.append({"id": key, "name": label, "description": descriptions[key], "source": "tweakcn",
                         **{m: from_tweakcn(c) for m, c in modes.items() if c}})
    families.sort(key=lambda f: (f["id"] != DEFAULT, f["name"].lower()))
    return families


if __name__ == "__main__":
    catalog = build(sys.argv[1])
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps({"tweakcnCommit": TWEAKCN_COMMIT, "families": catalog}, indent=1, ensure_ascii=False) + "\n")
    print(f"{len(catalog)} temas em {OUT}")
