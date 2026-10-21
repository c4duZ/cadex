"""The base16 and base24 schemes of tinted-theming/schemes (MIT), mapped to
Cadex's roles as docs/adr/0017-base16-themes.md decides: the terminal
colors follow tinted-theming's own terminal mapping, the interface takes
the roles base16 gives each shade."""
import re
from pathlib import Path

from colors import mix

# Themes the official palettes already bring, from their own projects:
# their base16 ports would be near copies (plan 15, phase A).
OFFICIAL_PORTS = ("catppuccin", "rose-pine", "tokyo-night", "tokyonight", "kanagawa", "gruvbox", "everforest", "nord",
                  "dracula", "solarized", "github", "ayu", "onedark", "one-light", "one-dark", "atom-one", "nightfox",
                  "dayfox", "dawnfox", "duskfox", "nordfox", "terafox", "carbonfox", "night-owl", "light-owl")
# Monokai Pro is a paid product (plan 15, "O que eu não quero").
REFUSED = ("monokai-pro",)
# base24's bright colors, in tinted-theming's fallback order to base16.
BRIGHT = {9: ("base12", "base08"), 10: ("base14", "base0B"), 11: ("base13", "base0A"),
          12: ("base16", "base0D"), 13: ("base17", "base0E"), 14: ("base15", "base0C")}
NORMAL = ["base00", "base08", "base0B", "base0A", "base0D", "base0E", "base0C", "base05"]


def parse(path):
    text = path.read_text()
    field = lambda key: (re.search(rf'^{key}:\s*"?([^"\n]*)"?', text, re.M) or [None, ""])[1].strip()
    palette = {k: "#" + v.lower() for k, v in re.findall(r'^\s+(base[0-9A-F]{2}):\s*"#?([0-9a-fA-F]{6})"', text, re.M)}
    return {"slug": path.stem, "name": field("name"), "author": field("author"), "variant": field("variant").strip('"'),
            "system": field("system") or path.parent.name, "palette": palette}


def author_name(author):
    """'Wimer Hazenberg (http://www.monokai.nl)' -> 'Wimer Hazenberg'."""
    name = re.sub(r"\(.*?\)|<.*?>|https?://\S+", "", author).strip(" ,;-")
    return name or "tinted-theming"


def variant(p):
    """One scheme as the catalog's dark or light version."""
    get = lambda k: p.get(k) or p["base00"]
    bg, fg = p["base00"], p["base05"]
    chrome = p["base01"] if p.get("base01", bg) != bg else mix(bg, fg, 0.06)
    accent = p["base0D"]
    ansi = [p[k] for k in NORMAL] + [p["base03"]] + [p.get(BRIGHT[i][0]) or p[BRIGHT[i][1]] for i in range(9, 15)] + [get("base07")]
    return {
        "interface": {
            "chrome": chrome, "panel": bg, "panelBorder": p["base02"], "tabActive": mix(chrome, accent, 0.22),
            "field": mix(chrome, fg, 0.06), "text": fg, "secondaryText": p["base04"], "accent": accent,
        },
        "terminal": {"background": bg, "foreground": fg, "cursor": fg, "selection": p["base02"], "ansi": ansi},
    }


def stem(slug):
    """'atelier-cave-light' and 'atelier-cave' share 'atelier-cave'."""
    return re.sub(r"-(dark|light|day|night)$", "", slug)


def read(root):
    """The schemes under a checkout of tinted-theming/schemes, base24 over
    base16 when both have one, grouped in dark and light pairs."""
    schemes = {}
    for system in ("base16", "base24"):
        for path in sorted((Path(root) / system).glob("*.yaml")):
            s = parse(path)
            if s["slug"].startswith(OFFICIAL_PORTS) or s["slug"].startswith(REFUSED) or "base0F" not in s["palette"]:
                continue
            schemes[s["slug"]] = s
    groups = {}
    for s in schemes.values():
        groups.setdefault(stem(s["slug"]), []).append(s)
    families = []
    for key, members in sorted(groups.items()):
        darks = [s for s in members if s["variant"] != "light"]
        lights = [s for s in members if s["variant"] == "light"]
        if len(darks) == 1 and len(lights) == 1:
            families.append(family(key, [darks[0], lights[0]]))
        else:
            families += [family(s["slug"], [s]) for s in members]
    return families


def family(key, members):
    names = [m["name"] for m in members]
    name = names[0] if len(names) == 1 else re.sub(r"\s+(Dark|Light|Day|Night)$", "", names[0], flags=re.I)
    author = author_name(members[0]["author"])
    entry = {"id": key, "name": name, "author": author, "source": members[0]["system"],
             "description": {"en": f"{members[0]['system']} scheme by {author}.", "pt": f"Esquema {members[0]['system']} de {author}."}}
    for m in members:
        entry["light" if m["variant"] == "light" else "dark"] = variant(m["palette"])
    return entry
