"""Builds the logos that tell which AI provider an account is (Agents ›
Accounts, the usage item; docs/adr/0020-provider-logos.md) from Lobe Icons
(MIT), the one-color versions (Gemini from Simple Icons, CC0: Lobe's would
not convert, 2026-10-21), so they take the theme's color like the
Phosphor icons:

    python3 -I tools/icons/build_provider_logos.py

downloads each SVG of VERSION from jsDelivr and writes it as a vector PDF
(the app runs from macOS 13, which does not read SVG; svg_to_pdf.swift
converts) to apps/macos/shared/icons/Resources/ProviderLogos. The logos are
the providers' trademarks, used only to name the account they belong to.
"""
import subprocess
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
OUT = HERE.parent.parent / "apps/macos/shared/icons/Resources/ProviderLogos"
VERSION = "1.97.0"
SIMPLE_ICONS = "16.35.0"
LOGOS = {
    name: f"https://cdn.jsdelivr.net/npm/@lobehub/icons-static-svg@{VERSION}/icons/{name}.svg"
    for name in ["claude", "openai", "codex", "githubcopilot", "cursor"]
}
LOGOS["gemini"] = f"https://cdn.jsdelivr.net/npm/simple-icons@{SIMPLE_ICONS}/icons/googlegemini.svg"


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, url in LOGOS.items():
        with urllib.request.urlopen(url, timeout=30) as response:
            (OUT / f"{name}.svg").write_bytes(response.read())
    subprocess.run(["swift", str(HERE / "svg_to_pdf.swift"), str(OUT)], check=True)
    print(f"{len(LOGOS)} logos in {OUT}")


if __name__ == "__main__":
    main()
