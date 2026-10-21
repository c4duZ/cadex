"""The tweakcn presets (Apache-2.0), utils/theme-presets.ts. They carry no
terminal colors: each ANSI color is the preset's own color nearest in hue
(primary, chart, accent, destructive), or, when none is near, the hue
drawn with the preset's lightness and chroma (plan 15, phase A: before
this every tweakcn theme shared one ANSI palette and looked the same in
the terminal)."""
import re
from pathlib import Path

from colors import from_oklch, mix, oklch_text, readable, to_oklch, is_dark

# OKLCH hue of each ANSI color: red, green, yellow, blue, magenta, cyan.
HUES = {1: 25, 2: 145, 3: 90, 4: 255, 5: 325, 6: 200}
NEAR = 28  # degrees
SOURCES = ["destructive", "primary", "chart-1", "chart-2", "chart-3", "chart-4", "chart-5", "accent", "secondary", "ring"]


def read(path):
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
            modes[mode] = {k: (v if v.startswith("#") else oklch_text(v)).lower() for k, v in pairs}
        presets[key] = (label, modes)
    return presets


def hue_distance(a, b):
    d = abs(a - b) % 360
    return min(d, 360 - d)


def ansi(c):
    """The 16 colors for one mode of a preset."""
    bg, fg = c["background"], c["foreground"]
    dark = is_dark(bg)
    chromatic = [to_oklch(c[k]) for k in SOURCES if k in c and to_oklch(c[k])[1] > 0.05]
    chroma = sorted(x[1] for x in chromatic)[len(chromatic) // 2] if chromatic else 0.12
    chroma = min(max(chroma, 0.09), 0.17)
    base_l = 0.74 if dark else 0.52
    out = [None] * 16
    for slot, hue in HUES.items():
        near = [x for x in chromatic if hue_distance(x[2], hue) <= NEAR]
        L, C, H = min(near, key=lambda x: hue_distance(x[2], hue)) if near else (base_l, chroma, hue)
        normal = readable(from_oklch(L, C, H), bg, 3.0) or from_oklch(base_l, C, H)
        nl, nc, nh = to_oklch(normal)
        bright = from_oklch(min(nl + 0.07, 0.95) if dark else max(nl - 0.07, 0.25), nc, nh)
        out[slot], out[slot + 8] = normal, readable(bright, bg, 3.0) or normal
    out[0] = mix(bg, fg, 0.12) if dark else mix(fg, bg, 0.1)
    out[7] = mix(fg, bg, 0.18)
    out[8] = readable(c.get("muted-foreground", mix(fg, bg, 0.45)), bg, 3.0) or mix(fg, bg, 0.4)
    out[15] = fg
    if not dark:
        out[0], out[7], out[15] = fg, mix(bg, fg, 0.25), mix(bg, fg, 0.1)
    return out


def variant(c):
    muted = c.get("muted", c["background"])
    return {
        "interface": {
            "chrome": muted, "panel": c["background"], "panelBorder": c.get("border", c["background"]),
            # The title bar's color with a little of the theme's primary: the
            # solid tweakcn "accent" painted the active tab amber or green,
            # and neutral gray made every theme look the same (owner's
            # feedback, both on 2026-10-19).
            "tabActive": mix(muted, c["primary"], 0.22),
            "field": mix(muted, c["foreground"], 0.06), "text": c["foreground"],
            "secondaryText": c.get("muted-foreground", c["foreground"]), "accent": c["primary"],
        },
        "terminal": {
            "background": c["background"], "foreground": c["foreground"], "cursor": c["primary"],
            "selection": mix(c["background"], c["primary"], 0.3), "ansi": ansi(c),
        },
    }
