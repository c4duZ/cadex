//! What a new session runs: which shell, with which arguments and
//! environment. Pure functions, so the rules are testable without spawning.

const std = @import("std");

/// Used when neither the settings nor $SHELL name a shell. zsh is the
/// macOS default since 10.15.
pub const fallback_shell = "/bin/zsh";

/// Variables the terminal owns. The user's values are dropped so a Cadex
/// session started from another terminal does not claim to be that terminal.
const owned_vars = [_][]const u8{ "TERM", "COLORTERM", "TERM_PROGRAM", "TERM_PROGRAM_VERSION" };

pub const added_vars = [_][]const u8{
    "TERM=xterm-256color",
    "COLORTERM=truecolor",
    "TERM_PROGRAM=Cadex",
};

pub const Argv = [*:null]const ?[*:0]const u8;
pub const Envp = [*:null]const ?[*:0]const u8;

/// The configured shell wins, then $SHELL, then the fallback.
pub fn resolveShell(configured: ?[]const u8, env_shell: ?[]const u8) []const u8 {
    if (configured) |s| if (s.len > 0) return s;
    if (env_shell) |s| if (s.len > 0) return s;
    return fallback_shell;
}

/// argv for a login shell: argv[0] is the shell name prefixed with "-",
/// the convention every POSIX shell reads as "load the login profile".
/// That is what makes PATH and the user's prompt match Terminal.app.
pub fn loginArgv(arena: std.mem.Allocator, shell_path: []const u8) !Argv {
    const name = std.fs.path.basename(shell_path);
    const argv0 = try std.fmt.allocPrintSentinel(arena, "-{s}", .{name}, 0);
    const argv = try arena.allocSentinel(?[*:0]const u8, 1, null);
    argv[0] = argv0.ptr;
    return argv.ptr;
}

/// The parent's environment minus the variables the terminal owns, plus
/// the terminal's own, plus the zsh integration when the shell is zsh.
pub fn sessionEnv(arena: std.mem.Allocator, parent: []const [*:0]const u8, shell_path: []const u8) !Envp {
    const zsh_dir = zshIntegration(parent, shell_path);
    var list: std.ArrayList(?[*:0]const u8) = .empty;
    var user_zdotdir: ?[]const u8 = null;
    for (parent) |entry| {
        const text = std.mem.span(entry);
        if (isOwned(text) or isAgentMarker(text)) continue;
        if (valueOf(text, "CADEX_USER_ZDOTDIR") != null) continue;
        const own_zdotdir = valueOf(text, "ZDOTDIR");
        if (zsh_dir != null and own_zdotdir != null) {
            user_zdotdir = own_zdotdir;
            continue;
        }
        try list.append(arena, entry);
    }
    for (added_vars) |entry| {
        try list.append(arena, (try arena.dupeZ(u8, entry)).ptr);
    }
    if (zsh_dir) |dir| {
        try list.append(arena, (try std.fmt.allocPrintSentinel(arena, "ZDOTDIR={s}", .{dir}, 0)).ptr);
        if (user_zdotdir) |own| try list.append(arena, (try std.fmt.allocPrintSentinel(arena, "CADEX_USER_ZDOTDIR={s}", .{own}, 0)).ptr);
    }
    const envp = try list.toOwnedSliceSentinel(arena, null);
    return envp.ptr;
}

/// The folder of Cadex's zsh startup files (CADEX_ZSH_INTEGRATION, which
/// the app puts in its own environment at launch), when the shell is zsh.
/// A tab's PATH cannot carry Cadex's `claude`: the login shell's
/// path_helper and the owner's .zshrc reorder it, so zsh starts from a
/// ZDOTDIR of Cadex's that gives the owner's back and defines a `claude`
/// function (the owner, 2026-11-15; the technique Ghostty and iTerm use).
/// bash and fish are left as they are.
pub fn zshIntegration(parent: []const [*:0]const u8, shell_path: []const u8) ?[]const u8 {
    if (!std.mem.eql(u8, std.fs.path.basename(shell_path), "zsh")) return null;
    for (parent) |entry| {
        const dir = valueOf(std.mem.span(entry), "CADEX_ZSH_INTEGRATION") orelse continue;
        return if (dir.len > 0) dir else null;
    }
    return null;
}

/// The value of `name` when `entry` is `name=value`.
fn valueOf(entry: []const u8, name: []const u8) ?[]const u8 {
    if (entry.len <= name.len or entry[name.len] != '=' or !std.mem.startsWith(u8, entry, name)) return null;
    return entry[name.len + 1 ..];
}

/// What a Claude Code session leaves to its children (CLAUDECODE, CLAUDE_CODE_*, and the account
/// it runs in, CLAUDE_CONFIG_DIR): a Cadex opened from a Claude Code session passed them to every
/// tab, and a `claude` typed there saw CLAUDE_CODE_CHILD_SESSION and kept no transcript, and ran in
/// that session's account whatever the title bar chose (the owner, 2026-11-18). A tab is a terminal
/// of its own: the account of a typed `claude` is the app's (the kit) or the one the owner's own
/// startup files export, which run after this.
pub fn isAgentMarker(entry: []const u8) bool {
    const eq = std.mem.indexOfScalar(u8, entry, '=') orelse return false;
    const name = entry[0..eq];
    return std.mem.eql(u8, name, "CLAUDECODE") or std.mem.eql(u8, name, "CLAUDE_CONFIG_DIR") or
        std.mem.startsWith(u8, name, "CLAUDE_CODE_");
}

pub fn isOwned(entry: []const u8) bool {
    const eq = std.mem.indexOfScalar(u8, entry, '=') orelse return false;
    const name = entry[0..eq];
    for (owned_vars) |owned| {
        if (std.mem.eql(u8, name, owned)) return true;
    }
    return false;
}

const testing = std.testing;

test "the configured shell wins over $SHELL and the fallback" {
    try testing.expectEqualStrings("/opt/homebrew/bin/fish", resolveShell("/opt/homebrew/bin/fish", "/bin/bash"));
    try testing.expectEqualStrings("/bin/bash", resolveShell("", "/bin/bash"));
    try testing.expectEqualStrings(fallback_shell, resolveShell(null, null));
}

test "argv starts a login shell" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const argv = try loginArgv(arena.allocator(), "/bin/zsh");
    try testing.expectEqualStrings("-zsh", std.mem.span(argv[0].?));
    try testing.expect(argv[1] == null);
}

test "environment replaces the terminal variables and keeps the rest" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const parent = [_][*:0]const u8{ "HOME=/Users/cadu", "TERM=xterm-ghostty", "TERM_PROGRAM=iTerm.app", "PATH=/usr/bin" };
    const envp = try sessionEnv(arena.allocator(), &parent, "/bin/bash");

    var got: std.ArrayList([]const u8) = .empty;
    var i: usize = 0;
    while (envp[i]) |entry| : (i += 1) try got.append(arena.allocator(), std.mem.span(entry));

    const expected = [_][]const u8{
        "HOME=/Users/cadu",     "PATH=/usr/bin",       "TERM=xterm-256color",
        "COLORTERM=truecolor", "TERM_PROGRAM=Cadex",
    };
    try testing.expectEqual(expected.len, got.items.len);
    for (expected, got.items) |want, have| try testing.expectEqualStrings(want, have);
}

fn envList(arena: std.mem.Allocator, envp: Envp) ![]const []const u8 {
    var got: std.ArrayList([]const u8) = .empty;
    var i: usize = 0;
    while (envp[i]) |entry| : (i += 1) try got.append(arena, std.mem.span(entry));
    return got.items;
}

fn has(list: []const []const u8, want: []const u8) bool {
    for (list) |entry| if (std.mem.eql(u8, entry, want)) return true;
    return false;
}

fn hasName(list: []const []const u8, name: []const u8) bool {
    for (list) |entry| if (valueOf(entry, name) != null) return true;
    return false;
}

test "zsh starts from Cadex's ZDOTDIR and keeps the owner's to give back" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const parent = [_][*:0]const u8{ "HOME=/Users/c", "CADEX_ZSH_INTEGRATION=/App/zsh", "ZDOTDIR=/Users/c/.config/zsh", "CADEX_USER_ZDOTDIR=/stale" };
    const got = try envList(a, try sessionEnv(a, &parent, "/bin/zsh"));
    try testing.expect(has(got, "ZDOTDIR=/App/zsh"));
    try testing.expect(has(got, "CADEX_USER_ZDOTDIR=/Users/c/.config/zsh"));
    try testing.expect(!has(got, "ZDOTDIR=/Users/c/.config/zsh") and !has(got, "CADEX_USER_ZDOTDIR=/stale"));
    try testing.expect(has(got, "CADEX_ZSH_INTEGRATION=/App/zsh") and has(got, "HOME=/Users/c"));

    // No ZDOTDIR of the owner's: none to give back, zsh then uses $HOME.
    const plain = [_][*:0]const u8{ "HOME=/Users/c", "CADEX_ZSH_INTEGRATION=/App/zsh" };
    const zsh = try envList(a, try sessionEnv(a, &plain, "/opt/homebrew/bin/zsh"));
    try testing.expect(has(zsh, "ZDOTDIR=/App/zsh") and !hasName(zsh, "CADEX_USER_ZDOTDIR"));
}

test "bash, fish and a zsh without the integration folder are left as they are" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const parent = [_][*:0]const u8{ "CADEX_ZSH_INTEGRATION=/App/zsh", "ZDOTDIR=/own" };
    for ([_][]const u8{ "/bin/bash", "/opt/homebrew/bin/fish" }) |shell| {
        const got = try envList(a, try sessionEnv(a, &parent, shell));
        try testing.expect(has(got, "ZDOTDIR=/own") and !hasName(got, "CADEX_USER_ZDOTDIR"));
    }
    const without = [_][*:0]const u8{ "ZDOTDIR=/own", "CADEX_ZSH_INTEGRATION=" };
    const zsh = try envList(a, try sessionEnv(a, &without, "/bin/zsh"));
    try testing.expect(has(zsh, "ZDOTDIR=/own") and !hasName(zsh, "CADEX_USER_ZDOTDIR"));
    try testing.expect(zshIntegration(&parent, "/bin/zshx") == null);
}

test "a tab never inherits a Claude Code session's marks nor its account" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const parent = [_][*:0]const u8{ "HOME=/Users/c", "CLAUDECODE=1", "CLAUDE_CODE_CHILD_SESSION=1", "CLAUDE_CODE_ENTRYPOINT=cli", "CLAUDE_CONFIG_DIR=/Users/c/.claude-x", "CLAUDE_CODEX=keep" };
    const got = try envList(a, try sessionEnv(a, &parent, "/bin/bash"));
    try testing.expect(!hasName(got, "CLAUDECODE") and !hasName(got, "CLAUDE_CODE_CHILD_SESSION") and !hasName(got, "CLAUDE_CODE_ENTRYPOINT"));
    try testing.expect(!hasName(got, "CLAUDE_CONFIG_DIR"));
    try testing.expect(has(got, "CLAUDE_CODEX=keep") and has(got, "HOME=/Users/c"));
}
