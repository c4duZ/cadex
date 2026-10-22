#!/usr/bin/env python3
"""Every command of the Mac app exists in the Windows app (ADR 0005: the
same ids on both, so settings.json and the habits carry over).

The Mac's ids are the feature-prefixed string literals of its Swift code
(Command(id:), the explorer's tables, the responder actions); the Windows
ones, every such literal of its Zig code. A literal that is a name of the
interface and not a command goes in NOT_COMMANDS.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
PREFIXES = "tab|pane|explorer|workspace|search|editor|markdown|terminal|git|history|diff|preview|media|space|edit|palette|settings|app|window|view|theme|power|sidebar|statusBar|agents|ssh"
LITERAL = re.compile(r'"((?:%s)\.[a-z0-9-]+)"' % PREFIXES)
# Names of views and keys in the Mac's code, not commands (2026-10-20).
# power.mode, sidebar.items and statusBar.left/right are settings.json keys, read by name in SettingsFile.swift.
NOT_COMMANDS = {"tabs.paneHeaders", "explorer.cell", "explorer.git-mark", "terminal.ansi", "terminal.cursor", "power.mode", "sidebar.items", "statusBar.left", "statusBar.right", "agents.sessions", "agents.accountNames", "agents.hiddenAccounts", "agents.accounts", "ssh.ping", "agents.hiddenLogins", "agents.launchSkipPermissions"}
# Mac-only for now: the in-app updater (docs/adr/0016-in-app-updates.md) comes
# to Windows later. Windows-only ones (workspace.environment) need no entry.
# The pasted-image tags (docs/spec/terminal.md, Ver a imagem colada) also
# start on the Mac, 2026-10-20. The preview's element picker needs a content
# world WebView2 lacks (docs/adr/0018-element-picker.md). The sidebar's icons
# (plan 17) start on the Mac, 2026-10-21; so do the pane headers and
# pane.zoom (issue #1, 2026-10-22).
MAC_ONLY = {"app.check-for-updates", "app.install-update", "app.skip-update",
            "terminal.open-pasted-image-beside", "terminal.open-pasted-image-in-tab",
            "preview.pick-element", "preview.stop-picking",
            "sidebar.customize", "sidebar.toggle-page", "git.show-history", "history.show-in-tab",
            "statusBar.customize", "statusBar.toggle-item", "statusBar.activity-monitor", "agents.show", "agents.test-notifications", "agents.show-accounts", "agents.refresh-usage", "ssh.connect", "ssh.test-again", "agents.open-account", "agents.customize-accounts",
            "pane.zoom"}


def literals(folder, suffix):
    found = set()
    for path in (ROOT / folder).rglob("*" + suffix):
        if "/tests/" in path.as_posix() or ".build" in path.parts:
            continue
        found.update(LITERAL.findall(path.read_text(encoding="utf-8", errors="replace")))
    return found


def main():
    mac = literals("apps/macos", ".swift") - NOT_COMMANDS - MAC_ONLY
    windows = literals("apps/windows", ".zig")
    missing = sorted(mac - windows)
    for command in missing:
        print(f"comando do Mac sem par no Windows: {command}")
    if missing:
        print(f"{len(missing)} comando(s) faltando no Windows")
        return 1
    print(f"paridade de comandos ok ({len(mac)} do Mac)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
