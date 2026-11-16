#!/usr/bin/env python3
"""Compares the words `cadex claude` knows (claude_args.zig) with the help of
the installed Claude Code (plan 22, phase C). A new subcommand would get the
session kit, and a new option with a value could hide one, so each new word
is a warning to look at; never a failure (the installed version is the
owner's, not the repository's). No `claude` installed: says nothing.

Run by `make manifests` (part of `make check`)."""

import os
import re
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SOURCE = os.path.join(HERE, "claude_args.zig")


def zig_list(text, name):
    """The strings of `const <name> = [_][]const u8{ ... };`."""
    match = re.search(r"(?:pub )?const %s = \[_\]\[\]const u8\{(.*?)\};" % name, text, re.S)
    return set(re.findall(r'"([^"]+)"', match.group(1))) if match else set()


def help_words(help_text):
    """The commands (aliases split at "|") and the options with a value:
    `<x>`, `<x...>` or `[x]` after the names."""
    commands, valued = set(), set()
    section = None
    for line in help_text.splitlines():
        if line.startswith("Commands:"):
            section = "commands"
            continue
        if line.startswith("Options:"):
            section = "options"
            continue
        if section == "commands":
            m = re.match(r"^  ([a-z][\w|-]*)", line)
            if m:
                commands.update(m.group(1).split("|"))
        elif section == "options":
            m = re.match(r"^  (-[^ ]*(?:, --?[\w-]+)*)( [<\[])?", line)
            if m and m.group(2):
                valued.update(n.strip() for n in m.group(1).split(","))
    return commands, valued


def main():
    claude = shutil.which("claude")
    if not claude:
        return 0
    try:
        out = subprocess.run([claude, "--help"], capture_output=True, text=True, timeout=20).stdout
    except (OSError, subprocess.SubprocessError):
        return 0
    with open(SOURCE, encoding="utf-8") as f:
        text = f.read()
    known_commands = zig_list(text, "subcommands")
    known_valued = zig_list(text, "one_value") | zig_list(text, "many_values") | zig_list(text, "maybe_value")
    commands, valued = help_words(out)
    for word in sorted(commands - known_commands):
        print("warning: claude has a subcommand cadex claude does not know: %s (claude_args.zig)" % word)
    for word in sorted(valued - known_valued):
        print("warning: claude has an option with a value cadex claude does not know: %s (claude_args.zig)" % word)
    return 0


if __name__ == "__main__":
    sys.exit(main())
