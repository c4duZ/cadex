#!/usr/bin/env python3
"""The mockups of the new frame and their tokens agree, both ways
(docs/adr/0035-work-frame.md, plan 25; the owner, 2026-11-17: "os planos
realmente levem os tokens exatos que a gente viu no mockup").

1. Every value a mockup uses (color, font size and weight, line height,
   tracking, radius, shadow, stroke, opacity, gap/padding/margin) is a token
   of docs/design/work-frame/tokens.json.
2. Every primitive token appears in some mockup: no token without a mockup.
3. Every name a component refers to is a primitive token.
4. Every component is implemented by some plan of the new frame (the plan
   says "Tokens: components.<name>, …"), and every component a plan cites
   exists: the plans carry the exact tokens of the mockups.
5. Every mockup has its section in screens.md (the written description of
   the screen) and is listed by some plan ("Telas: X.dc.html, …"); no plan
   or section names a mockup that does not exist.

Skipped: the <helmet> of each file (the canvas background), the files listed
in excluded.files, and what sits between <!-- tokens:off: why --> and
<!-- tokens:on --> (example content: Claude Code as it looks today, a site
inside the preview, the macOS window buttons).
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
FOLDER = ROOT / "docs/design/work-frame"
DECL = re.compile(r"([a-z-]+)\s*:\s*([^;\"'{}<>]+?)\s*(?=;|\"|'|$)", re.M)
COLOR = re.compile(r"#[0-9A-Fa-f]{6}\b|#[0-9A-Fa-f]{3}\b|rgba\([^)]*\)")
SPACING = {"gap", "padding", "margin", "margin-top", "margin-bottom", "margin-left",
           "margin-right", "padding-top", "padding-left", "padding-right", "padding-bottom",
           "row-gap", "column-gap"}
SKIP_KEYS = {"about", "opening", "regions", "files", "mono"}


def norm_color(c):
    c = c.strip()
    return c.upper() if c.startswith("#") else c.replace(" ", "").lower()


def px(v):
    return float(v[:-2]) if v.endswith("px") else float(v)


def mockup_text(path, excluded):
    if path.name in excluded:
        return ""
    s = path.read_text()
    s = re.sub(r"<helmet>.*?</helmet>", "", s, flags=re.S)
    return re.sub(r"<!-- tokens:off:.*?<!-- tokens:on -->", "", s, flags=re.S)


def resolve_shadow(value, colors):
    return re.sub(r"\{([^}]+)\}", lambda m: colors[m.group(1)], value)


def collect(text):
    """(property, value) pairs, leaving out values built in script (`${…}`, `+`)."""
    for m in DECL.finditer(text):
        k, v = m.group(1), m.group(2).strip()
        if "$" in v or "+" in v or "{" in v or v == "":
            continue
        yield k, v


def check(tokens, texts):
    colors = {k: norm_color(v) for k, v in tokens["color"].items()}
    color_values = set(colors.values())
    shadows = {k: re.sub(r"\s+", " ", resolve_shadow(v, tokens["color"])).lower()
               for k, v in tokens["shadow"].items()}
    allowed = {
        "font-size": {float(v) for v in tokens["fontSize"].values()},
        "font-weight": {float(v) for v in tokens["fontWeight"].values()},
        "line-height": {float(v) for v in tokens["lineHeight"].values()},
        "letter-spacing": set(tokens["tracking"].values()),
        "opacity": {float(v) for v in tokens["opacity"].values()},
    }
    radii = {str(v) for v in tokens["radius"].values()}
    strokes = {float(v) for v in tokens["stroke"].values()}
    space = {float(v) for v in tokens["space"]}
    problems, used = [], {"color": set(), "shadow": set(), "radius": set(), "fontSize": set(),
                          "fontWeight": set(), "lineHeight": set(), "tracking": set()}
    for name, text in texts.items():
        for c in COLOR.findall(text):
            n = norm_color(c)
            if n not in color_values:
                problems.append(f"{name}: cor sem token: {c}")
            used["color"].add(n)
        for k, v in collect(text):
            where = f"{name}: {k}: {v}"
            try:
                if k in allowed:
                    val = v if k == "letter-spacing" else float(v.replace("px", ""))
                    if val not in allowed[k]:
                        problems.append(f"{where}: sem token")
                    group = {"font-size": "fontSize", "font-weight": "fontWeight", "line-height": "lineHeight",
                             "letter-spacing": "tracking"}.get(k)
                    if group:
                        used[group].add(val)
                elif k == "border-radius":
                    r = v if v.endswith("%") else str(int(px(v)) if px(v).is_integer() else px(v))
                    if r not in radii:
                        problems.append(f"{where}: raio sem token")
                    used["radius"].add(r)
                elif k == "box-shadow":
                    sv = re.sub(r"\s+", " ", v).lower()
                    if sv not in shadows.values():
                        problems.append(f"{where}: sombra sem token")
                    used["shadow"].add(sv)
                elif k in SPACING:
                    for part in v.split():
                        if part != "auto" and px(part) not in space:
                            problems.append(f"{where}: espaço sem token ({part})")
                elif k.startswith("border") and "solid" in v:
                    w = v.split()[0]
                    if px(w) not in strokes:
                        problems.append(f"{where}: espessura sem token")
            except ValueError:
                problems.append(f"{where}: valor que o conferidor não lê")
    for k, n in colors.items():
        if n not in used["color"] and not k.startswith("shadow.") and not k.startswith("halo."):
            problems.append(f"tokens.json: color.{k} ({n}) não aparece em nenhum mockup")
    for k, sv in shadows.items():
        if sv not in used["shadow"]:
            problems.append(f"tokens.json: shadow.{k} não aparece em nenhum mockup")
    for k, v in tokens["radius"].items():
        if str(v) not in used["radius"]:
            problems.append(f"tokens.json: radius.{k} ({v}) não aparece em nenhum mockup")
    for group, key in (("fontSize", "fontSize"), ("fontWeight", "fontWeight"), ("lineHeight", "lineHeight")):
        for k, v in tokens[group].items():
            if float(v) not in used[key]:
                problems.append(f"tokens.json: {group}.{k} ({v}) não aparece em nenhum mockup")
    return problems + check_components(tokens) + check_plans(tokens)


PLANS = ["25-work-frame.md", "26-frame.md", "27-projects-tree.md", "28-dressed-terminal.md",
         "29-entrances.md", "30-overview.md"]


def check_plans(tokens, plans_dir=ROOT / "docs/plans"):
    cited = {}
    for name in PLANS:
        path = plans_dir / name
        text = path.read_text() if path.exists() else ""
        for c in re.findall(r"components\.([a-zA-Z]+)", text):
            cited.setdefault(c, []).append(name)
    problems = [f"docs/plans/{p}: cita components.{c}, que não existe em tokens.json"
                for c, ps in cited.items() if c not in tokens["components"] for p in ps]
    problems += [f"tokens.json: components.{c} não está em nenhum plano da moldura (25 a 30)"
                 for c in tokens["components"] if c not in cited]
    return problems + check_screens(plans_dir)


def check_screens(plans_dir):
    mockups = {p.name for p in FOLDER.glob("*.dc.html")}
    described = set(re.findall(r"^### ([A-Za-z]+\.dc\.html)", (FOLDER / "screens.md").read_text(), re.M))
    listed = set()
    for name in PLANS:
        path = plans_dir / name
        for line in (path.read_text() if path.exists() else "").splitlines():
            if line.lstrip("- ").startswith("Telas:"):
                listed |= set(re.findall(r"[A-Za-z]+\.dc\.html", line))
    problems = [f"screens.md: {m} sem descrição" for m in sorted(mockups - described)]
    problems += [f"screens.md: descreve {m}, que não existe" for m in sorted(described - mockups)]
    problems += [f"{m} não está na linha Telas: de nenhum plano da moldura" for m in sorted(mockups - listed)]
    problems += [f"um plano cita {m}, que não existe" for m in sorted(listed - mockups)]
    return problems


def check_components(tokens):
    names = set()
    for group in ("color", "fontSize", "fontWeight", "lineHeight", "tracking", "radius", "stroke", "opacity", "shadow"):
        names |= set(tokens[group])
    problems = []

    def walk(node, path):
        if isinstance(node, dict):
            for k, v in node.items():
                if k not in SKIP_KEYS:
                    walk(v, f"{path}.{k}")
        elif isinstance(node, list):
            for i, v in enumerate(node):
                walk(v, f"{path}[{i}]")
        elif isinstance(node, str) and re.fullmatch(r"[a-zA-Z]+(\.[a-zA-Z0-9]+)?", node):
            if node not in names:
                problems.append(f"tokens.json: {path} cita '{node}', que não é token")
    walk(tokens["components"], "components")
    return problems


def main():
    tokens = json.loads((FOLDER / "tokens.json").read_text())
    excluded = set(tokens["excluded"]["files"])
    texts = {p.name: mockup_text(p, excluded) for p in sorted(FOLDER.glob("*.dc.html"))}
    problems = check(tokens, texts)
    for p in problems:
        print(p)
    if problems:
        print(f"{len(problems)} problema(s) entre os mockups e tokens.json")
        sys.exit(1)


if __name__ == "__main__":
    main()
