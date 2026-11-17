"""How each color of the new frame follows the theme (docs/adr/0035-work-frame.md, revised
2026-11-17: the frame took its colors straight from the mockups and every theme looked like
Cadex Night). Each token is rebuilt from the theme's frame color (`chrome`) and text color
(`text`), the way it sits between Cadex Night's own:

- neutral f: mix(chrome, text, f): backgrounds, lines and grays;
- tint hue f: mix(chrome, hue, f): a background tinted toward a state color (chips, tints);
- ink hue g: mix(hue, text, g): a colored text (amber, green, red, link), lighter on dark
  themes and darker on light ones;
- the state colors, the text on fills and the translucent ones stay as they are: a color in
  the app means a state in every theme.

The recipe is the one closest to Cadex Night's value; with Cadex Night the tokens are used as
they are, so the mockups are matched exactly."""

ANCHOR_CHROME = "bg.chrome"
ANCHOR_TEXT = "text.primary"
HUES = ["state.working", "state.needs", "state.done", "state.failed", "state.review"]


def rgb(hex_color):
    h = hex_color.lstrip("#")
    return [int(h[i:i + 2], 16) for i in (0, 2, 4)]


def mix(a, b, f):
    return [x + (y - x) * f for x, y in zip(a, b)]


def fit(a, b, v):
    """The f of mix(a, b, f) closest to v, by least squares, and its worst channel error."""
    d = [y - x for x, y in zip(a, b)]
    den = sum(x * x for x in d)
    if den == 0:
        return 0, 999
    f = sum((w - x) * e for x, w, e in zip(a, v, d)) / den
    return f, max(abs(m - w) for m, w in zip(mix(a, b, f), v))


def fixed(name, value):
    return not value.startswith("#") or name.startswith("state.") or name.startswith("text.on")


def recipes(colors):
    """name -> ("neutral", f) | ("tint", hue, f) | ("ink", hue, g); fixed tokens are left out."""
    chrome, text = rgb(colors[ANCHOR_CHROME]), rgb(colors[ANCHOR_TEXT])
    out = {}
    for name, value in colors.items():
        if fixed(name, value):
            continue
        v = rgb(value)
        f, err = fit(chrome, text, v)
        best = (err, ("neutral", f))
        # A near gray stays neutral: a faint hue fitted by a hair would tint it in other themes.
        if err <= 4:
            out[name], out[name + "#error"] = best[1], best[0]
            continue
        for hue in HUES:
            h = rgb(colors[hue])
            tf, terr = fit(chrome, h, v)
            if terr < best[0]:
                best = (terr, ("tint", hue, tf))
            ig, ierr = fit(h, text, v)
            if ierr < best[0]:
                best = (ierr, ("ink", hue, ig))
        out[name] = best[1]
        out[name + "#error"] = best[0]
    return out


if __name__ == "__main__":
    import json
    import pathlib
    t = json.loads((pathlib.Path(__file__).resolve().parent.parent.parent / "docs/design/work-frame/tokens.json").read_text())
    r = recipes(t["color"])
    for k, v in r.items():
        if not k.endswith("#error"):
            print(f"{k:24} {v}  err {r[k + '#error']:.1f}")
