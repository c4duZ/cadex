//! What `cadex claude <args…>` does with the words typed after `claude` in
//! a Cadex zsh tab (plan 22, phase C): an interactive session gets the
//! session kit; everything else (print mode, version, help, every
//! subcommand) runs the real `claude` exactly as typed.
//!
//! The words follow Claude Code 2.1.325's own parser (`claude --help`, read
//! 2026-11-16): the subcommand is the first word that is not an option,
//! skipping the value of the options that take one (`claude --model haiku
//! mcp list` is `mcp`). An option's value may come after `=`; a variadic
//! option (`--add-dir a b`) eats words up to the next option; an optional
//! one (`--resume [id]`) eats the next word unless it starts with "-".
//! `claude_args_check.py` (in `make check`) compares these lists with the installed `claude`.

const std = @import("std");

/// `claude --help`'s commands plus the hidden ones the proof of concept
/// found (2026-11-15): daemon, design-login, import-conversations, project,
/// remote-control/rc/bridge, sandbox, workspace-trust, worktree-hook.
pub const subcommands = [_][]const u8{
    "agents",       "attach",          "auth",                 "auto-mode",    "daemon",      "design-login",
    "doctor",       "gateway",         "import",               "import-conversations", "install", "logs",
    "mcp",          "plugin",          "plugins",              "project",      "purge",       "remote-control",
    "rc",           "bridge",          "respawn",              "rm",           "sandbox",     "setup-token",
    "stop",         "kill",            "ultrareview",          "update",       "upgrade",     "workspace-trust",
    "worktree-hook",
};

/// Options that run no interactive session, or one the kit must not touch
/// yet: print, version, help; `--bg` and `--remote-control` until a
/// decision of their own (plan 22); `--cloud` and `--desktop` open the
/// session elsewhere.
const pass_through = [_][]const u8{
    "-p",           "--print", "-v",      "--version", "-h", "--help", "--bg", "--background",
    "--remote-control", "--cloud", "--desktop",
};

/// Options with one value (`<x>` in the help), plus hidden ones seen in
/// Claude Code's own messages (the --bare help names the -file prompts).
const one_value = [_][]const u8{
    "--agent",            "--agents",          "--append-system-prompt", "--autocompact",  "--debug-file",
    "--effort",           "--environment",     "--fallback-model",       "--input-format", "--json-schema",
    "--max-budget-usd",   "--model",           "-n",                     "--name",         "--output-format",
    "--permission-mode",  "--permission-prompts", "--plugin-dir",        "--plugin-url",   "--remote-control-session-name-prefix",
    "--session-id",       "--setting-sources", "--settings",             "--system-prompt", "--system-prompt-snapshot",
    "--system-prompt-file", "--append-system-prompt-file", "--permission-prompt-tool", "--max-turns", "--max-thinking-tokens",
    "--resume-session-at",
};

/// `<x...>` in the help: every word up to the next option.
const many_values = [_][]const u8{
    "--add-dir", "--allowedTools", "--allowed-tools", "--betas", "--disallowedTools", "--disallowed-tools",
    "--file",    "--mcp-config",   "--tools",
};

/// `[x]` in the help: the next word, unless it is an option.
const maybe_value = [_][]const u8{
    "--cloud", "-d", "--debug", "--from-pr", "--prompt-suggestions", "--remote-control", "-r", "--resume", "--teleport", "-w", "--worktree",
};

pub const Kind = enum { flag, one, many, maybe };

pub fn kindOf(option: []const u8) Kind {
    if (contains(&one_value, option)) return .one;
    if (contains(&many_values, option)) return .many;
    if (contains(&maybe_value, option)) return .maybe;
    return .flag;
}

pub fn isSubcommand(word: []const u8) bool {
    return contains(&subcommands, word);
}

fn contains(list: []const []const u8, word: []const u8) bool {
    for (list) |item| if (std.mem.eql(u8, item, word)) return true;
    return false;
}

pub const Plan = union(enum) {
    /// Run the real `claude` with the words as typed.
    pass_through,
    /// An interactive session: the words without any `--settings`, and the
    /// value of the last one (two `--settings` do not add up: only the last
    /// counts, tested 2026-11-15), which the app merges with the kit's.
    kit: struct { words: []const []const u8, user_settings: ?[]const u8 },

    pub fn deinit(self: Plan, gpa: std.mem.Allocator) void {
        if (self == .kit) gpa.free(self.kit.words);
    }
};

pub fn plan(gpa: std.mem.Allocator, words: []const []const u8) !Plan {
    var kept: std.ArrayList([]const u8) = .empty;
    defer kept.deinit(gpa);
    var user_settings: ?[]const u8 = null;
    var first_word = true;
    var i: usize = 0;
    while (i < words.len) {
        const word = words[i];
        if (std.mem.eql(u8, word, "--")) {
            // After "--" every word is the prompt.
            try kept.appendSlice(gpa, words[i..]);
            break;
        }
        if (word.len < 2 or word[0] != '-') {
            if (first_word and isSubcommand(word)) return .pass_through;
            first_word = false;
            try kept.append(gpa, word);
            i += 1;
            continue;
        }
        const eq = std.mem.indexOfScalar(u8, word, '=');
        const name = if (std.mem.startsWith(u8, word, "--")) word[0 .. eq orelse word.len] else word;
        if (std.mem.startsWith(u8, word, "--")) {
            if (contains(&pass_through, name)) return .pass_through;
            if (std.mem.eql(u8, name, "--settings")) {
                if (eq) |at| {
                    user_settings = word[at + 1 ..];
                    i += 1;
                    continue;
                }
                if (i + 1 < words.len) {
                    user_settings = words[i + 1];
                    i += 2;
                    continue;
                }
            }
        } else if (shortPassesThrough(word)) return .pass_through;
        const taken = if (eq != null and word[1] == '-') 0 else valueWords(words, i);
        try kept.appendSlice(gpa, words[i .. i + 1 + taken]);
        i += 1 + taken;
    }
    return .{ .kit = .{ .words = try kept.toOwnedSlice(gpa), .user_settings = user_settings } };
}

/// `-p`, or `-p` among combined short flags (`-cp`), before any letter
/// whose value takes the rest of the word (`-nprinter` names the session).
fn shortPassesThrough(word: []const u8) bool {
    for (word[1..]) |letter| {
        if (letter == 'p' or letter == 'v' or letter == 'h') return true;
        if (kindOf(&[_]u8{ '-', letter }) != .flag) return false;
    }
    return false;
}

/// How many words after `words[at]` are its value.
fn valueWords(words: []const []const u8, at: usize) usize {
    const word = words[at];
    const kind = if (word[1] == '-') kindOf(word) else shortKind(word) orelse return 0;
    const next = words[at + 1 ..];
    return switch (kind) {
        .flag => 0,
        .one => @min(next.len, 1),
        .maybe => if (next.len > 0 and !isOption(next[0])) 1 else 0,
        .many => blk: {
            var n: usize = 0;
            while (n < next.len and !isOption(next[n])) n += 1;
            break :blk n;
        },
    };
}

/// The kind of the last letter of `-abc`, when the value is not glued to
/// it (`-nname` carries it in the word: null).
fn shortKind(word: []const u8) ?Kind {
    for (word[1..], 1..) |letter, at| {
        const kind = kindOf(&[_]u8{ '-', letter });
        if (kind == .flag) continue;
        return if (at == word.len - 1) kind else null;
    }
    return .flag;
}

fn isOption(word: []const u8) bool {
    return word.len > 1 and word[0] == '-';
}

const testing = std.testing;

fn expectPass(words: []const []const u8) !void {
    const p = try plan(testing.allocator, words);
    defer p.deinit(testing.allocator);
    try testing.expect(p == .pass_through);
}

fn expectKit(words: []const []const u8, kept: []const []const u8, settings: ?[]const u8) !void {
    const p = try plan(testing.allocator, words);
    defer p.deinit(testing.allocator);
    try testing.expect(p == .kit);
    try testing.expectEqual(kept.len, p.kit.words.len);
    for (kept, p.kit.words) |want, have| try testing.expectEqualStrings(want, have);
    if (settings) |s| try testing.expectEqualStrings(s, p.kit.user_settings.?) else try testing.expect(p.kit.user_settings == null);
}

test "print, version, help, --bg and every subcommand run claude as typed" {
    try expectPass(&.{"-p"});
    try expectPass(&.{ "-p", "say hi" });
    try expectPass(&.{ "--print", "--model", "haiku", "x" });
    try expectPass(&.{"--version"});
    try expectPass(&.{"-v"});
    try expectPass(&.{"-h"});
    try expectPass(&.{"--help"});
    try expectPass(&.{ "--bg", "fix it" });
    try expectPass(&.{ "--remote-control", "name" });
    try expectPass(&.{ "-cp", "x" });
    try expectPass(&.{ "mcp", "list" });
    try expectPass(&.{ "--model", "haiku", "mcp", "list" });
    try expectPass(&.{ "--model=haiku", "mcp", "list" });
    try expectPass(&.{ "-c", "doctor" });
    try expectPass(&.{ "-n", "x", "update" });
    try expectPass(&.{"remote-control"});
    try expectPass(&.{ "\"fix the bug\"", "--print" });
}

test "an interactive session gets the kit, the words kept as typed" {
    try expectKit(&.{}, &.{}, null);
    try expectKit(&.{"fix the bug"}, &.{"fix the bug"}, null);
    try expectKit(&.{ "--resume", "abc" }, &.{ "--resume", "abc" }, null);
    // The resume id is a value, not a subcommand: `claude -r mcp` resumes "mcp".
    try expectKit(&.{ "-r", "mcp" }, &.{ "-r", "mcp" }, null);
    try expectKit(&.{ "-c", "--model", "opus" }, &.{ "-c", "--model", "opus" }, null);
    // A prompt that happens to be a subcommand's word, after the prompt.
    try expectKit(&.{ "explain", "mcp" }, &.{ "explain", "mcp" }, null);
    // A variadic option eats its words up to the next option.
    try expectKit(&.{ "--add-dir", "a", "mcp", "--model", "x" }, &.{ "--add-dir", "a", "mcp", "--model", "x" }, null);
    // -nprinter: the name is glued, the "p" is not print.
    try expectKit(&.{"-nprinter"}, &.{"-nprinter"}, null);
    try expectKit(&.{ "--", "-p" }, &.{ "--", "-p" }, null);
}

test "the owner's --settings leaves the words; the last one counts" {
    try expectKit(&.{ "--settings", "x.json" }, &.{}, "x.json");
    try expectKit(&.{ "--settings", "a.json", "-c", "--settings={\"a\":1}" }, &.{"-c"}, "{\"a\":1}");
    try expectKit(&.{ "--model", "haiku", "--settings", "x.json", "go" }, &.{ "--model", "haiku", "go" }, "x.json");
    // No value after it: left for claude to complain about.
    try expectKit(&.{"--settings"}, &.{"--settings"}, null);
}
