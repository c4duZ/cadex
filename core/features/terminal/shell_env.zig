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
/// the terminal's own.
pub fn sessionEnv(arena: std.mem.Allocator, parent: []const [*:0]const u8) !Envp {
    var list: std.ArrayList(?[*:0]const u8) = .empty;
    for (parent) |entry| {
        if (isOwned(std.mem.span(entry))) continue;
        try list.append(arena, entry);
    }
    for (added_vars) |entry| {
        try list.append(arena, (try arena.dupeZ(u8, entry)).ptr);
    }
    const envp = try list.toOwnedSliceSentinel(arena, null);
    return envp.ptr;
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
    const envp = try sessionEnv(arena.allocator(), &parent);

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
