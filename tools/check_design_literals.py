#!/usr/bin/env python3
"""The new frame's files use the mockups' tokens, never typed values
(docs/adr/0035-work-frame.md, plan 25 phase C): in each file of FRAME_FILES,
no color in hex or by components, no radius, font size, padding or height
written as a number. Values come from DesignTokens (generated from
docs/design/work-frame/tokens.json by tools/design/build_tokens.py).

FRAME_FILES grows plan by plan, as each file is written or rewritten for the
new frame (plans 25 to 30); by the end of plan 30 it covers the whole shell.
A bare 0 or 1 (an index, an identity, the hairline of an edge) is fine; a line that must hold one anyway ends with `// token-exempt: why`.
`--self-test` checks the rules against made-up lines.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
# Written for the new frame, relative to the repository (plan that added it).
FRAME_FILES = [
    "apps/macos/shared/state-glyph/StateGlyph.swift",  # plano 25
    "apps/macos/shared/state-glyph/StateGlyphView.swift",  # plano 25
    "apps/macos/features/tabs/TabAgentTitle.swift",  # plano 25
    "apps/macos/app/TitleBarView.swift",  # plano 26
    "apps/macos/app/TitleBarButton.swift",  # plano 26
    "apps/macos/app/TitleBarSearch.swift",  # plano 26
    "apps/macos/features/tabs/TabBarView.swift",  # plano 26
    "apps/macos/features/tabs/TabBarDrag.swift",  # plano 26
    "apps/macos/app/StatusBarItems.swift",  # plano 26
    "apps/macos/features/status-bar/StatusBarView.swift",  # plano 26
    "apps/macos/features/status-bar/StatusItem.swift",  # plano 26
    "apps/macos/features/agents/AgentUsageStrip.swift",  # plano 26
]
# A design value: any number but a bare 0 or 1 (those are counts, identities and the hairline
# of an edge, not mockup values; review of 2026-11-17).
DESIGN = r"(?:[2-9]|\d{2,}|\d*\.\d+|1\.\d+)"
RULES = [
    (re.compile(r"#(?:[0-9A-Fa-f]{8}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{3})(?![0-9A-Za-z])"), "cor em hex"),
    (re.compile(r"\b0x(?:[0-9A-Fa-f]{8}|[0-9A-Fa-f]{6})\b"), "cor em hex"),
    (re.compile(r"\b(?:NSColor|CGColor|UIColor)\((?:srgbRed|red|calibratedRed|deviceRed|white|calibratedWhite|"
                r"genericGamma22White|hue|calibratedHue|deviceHue|displayP3Red|gray|genericGrayGamma2_2Gray|"
                r"srgbRed|cyan)\s*:"), "cor por componentes"),
    (re.compile(r"cornerRadius\s*[:=]\s*" + DESIGN), "raio digitado"),
    (re.compile(r"UILooks\.(?:font|monospaced|monospacedDigits)\(\s*" + DESIGN), "tamanho de fonte digitado"),
    (re.compile(r"\b(?:systemFont|monospacedSystemFont|monospacedDigitSystemFont|boldSystemFont)\(ofSize:\s*" + DESIGN),
     "tamanho de fonte digitado"),
    (re.compile(r"UILooks\.(?:pt|rowHeight)\(\s*" + DESIGN), "medida digitada"),
    (re.compile(r"NSEdgeInsets\([^)]*:\s*" + DESIGN), "espaço digitado"),
    (re.compile(r"\b(?:spacing|edgeInsets|lineWidth|borderWidth)\s*[:=]\s*" + DESIGN), "espaço ou espessura digitados"),
    (re.compile(r"\bNSSize\((?:width|height):\s*" + DESIGN), "medida digitada"),
]


def problems_in(lines, name):
    found = []
    for n, line in enumerate(lines, 1):
        code = line.split("//")[0] if "token-exempt:" not in line else ""
        for rule, what in RULES:
            if rule.search(code):
                found.append(f"{name}:{n}: {what}: {line.strip()}")
    return found


def self_test():
    bad = ['let c = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)', 'layer.cornerRadius = 10',
           'label.font = UILooks.font(13, weight: .semibold)', 'let w = UILooks.pt(292)', 'x.color = "#121316"',
           'stack.spacing = 8', 'NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)', 'let c = 0x121316FF',
           'x.color = "#121316CC"', 'x.color = "#fff"', 'NSColor(hue: 0.5, saturation: 1, brightness: 1, alpha: 1)',
           'CGColor(red: 1, green: 0, blue: 0, alpha: 1)', 'box(cornerRadius: 10)', 'NSStackView(spacing: 8)',
           'UILooks.pt(.5)', 'NSSize(width: 292, height: 44)', 'layer.borderWidth = 1.5']
    good = ['layer.cornerRadius = UILooks.pt(DesignTokens.Pane.radius)',
            'label.font = UILooks.font(DesignTokens.FontSize.body, weight: DesignTokens.FontWeight.semibold)',
            'let first = items[0]', 'stack.spacing = 0', 'view.alphaValue = 1', 'NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)',
            'let hair = UILooks.pt(1)', 'layer.borderWidth = 1', 'NSSize(width: 0, height: 0)',
            'let odd = UILooks.pt(3) // token-exempt: the hairline under the macOS buttons']
    got_bad = problems_in(bad, "bad")
    got_good = problems_in(good, "good")
    if len(got_bad) != len(bad) or got_good:
        print("check_design_literals --self-test falhou:", got_bad, got_good)
        sys.exit(1)


def main():
    if "--self-test" in sys.argv:
        self_test()
        return
    problems = []
    for rel in FRAME_FILES:
        path = ROOT / rel
        if not path.exists():
            problems.append(f"{rel}: está na lista da moldura nova e não existe")
            continue
        problems += problems_in(path.read_text().splitlines(), rel)
    for p in problems:
        print(p)
    if problems:
        print(f"{len(problems)} valor(es) digitado(s) na moldura nova: use DesignTokens")
        sys.exit(1)


if __name__ == "__main__":
    main()
