//! The folder the app was opened with: `Cadex /some/folder` from a shell.
//! Opening by dragging onto the Dock icon reaches the app as an AppKit
//! event, not an argument, so the app handles that one itself.

const std = @import("std");
const paths = @import("paths.zig");

/// The first argument after the program name that names an existing
/// directory, canonical, in `out`. Relative arguments resolve against
/// `cwd`. Flags are skipped, and so is the value after the -NS... and
/// -Apple... flags that macOS and Xcode pass (-NSDocumentRevisionsDebugMode YES).
pub fn launchDirectory(args: []const []const u8, cwd: []const u8, out: *paths.Buffer) ?[]const u8 {
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (arg.len == 0) continue;
        if (arg[0] == '-') {
            if (takesValue(arg)) i += 1;
            continue;
        }
        if (resolveDirectory(arg, cwd, out)) |dir| return dir;
    }
    return null;
}

fn takesValue(flag: []const u8) bool {
    return std.mem.startsWith(u8, flag, "-NS") or std.mem.startsWith(u8, flag, "-Apple");
}

fn resolveDirectory(arg: []const u8, cwd: []const u8, out: *paths.Buffer) ?[]const u8 {
    var joined: paths.Buffer = undefined;
    const absolute = if (arg[0] == '/')
        arg
    else
        std.fmt.bufPrint(&joined, "{s}/{s}", .{ cwd, arg }) catch return null;
    const real = paths.canonicalize(absolute, out) catch return null;
    return if (paths.isDirectory(real)) real else null;
}

const testing = std.testing;

test "the first directory argument wins; flags and their values are skipped" {
    var buf: paths.Buffer = undefined;
    const args = [_][]const u8{ "Cadex", "-NSDocumentRevisionsDebugMode", "/usr", "-psn_0_123", "/tmp" };
    try testing.expectEqualStrings("/private/tmp", launchDirectory(&args, "/", &buf).?);
}

test "relative arguments resolve against the working directory" {
    var buf: paths.Buffer = undefined;
    const args = [_][]const u8{ "Cadex", "bin" };
    try testing.expectEqualStrings("/usr/bin", launchDirectory(&args, "/usr", &buf).?);
}

test "files and missing paths are not launch directories" {
    var buf: paths.Buffer = undefined;
    const args = [_][]const u8{ "Cadex", "/etc/hosts", "/no/such/dir" };
    try testing.expect(launchDirectory(&args, "/", &buf) == null);
    try testing.expect(launchDirectory(&.{"Cadex"}, "/", &buf) == null);
}
