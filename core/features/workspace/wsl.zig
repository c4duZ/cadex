//! The WSL environment on Windows (docs/spec/workspace.md): the installed
//! distributions, and paths between the two sides, so a terminal in a
//! distro can move the tree and a Windows folder can open in a distro.
//! `C:\Users\ana` is `/mnt/c/Users/ana` inside; `/home/ana` of Ubuntu is
//! `\\wsl.localhost\Ubuntu\home\ana` outside. On the Mac there is none.

const std = @import("std");
const builtin = @import("builtin");
const process = @import("../../shared/process.zig");

/// The distributions `wsl.exe -l -q` lists, owned by the caller (each and
/// the list); empty without WSL or off Windows.
pub fn distros(gpa: std.mem.Allocator) ![][]u8 {
    if (builtin.os.tag != .windows) return gpa.alloc([]u8, 0);
    var r = process.run(gpa, &.{ "wsl.exe", "-l", "-q" }, .{ .timeout_ms = 10_000 }) catch return gpa.alloc([]u8, 0);
    defer r.deinit(gpa);
    if (!r.ok()) return gpa.alloc([]u8, 0);
    return parseList(gpa, r.stdout);
}

/// wsl.exe writes UTF-16LE (sometimes with a BOM), one name per line.
pub fn parseList(gpa: std.mem.Allocator, bytes: []const u8) ![][]u8 {
    var out: std.ArrayList([]u8) = .empty;
    errdefer {
        for (out.items) |d| gpa.free(d);
        out.deinit(gpa);
    }
    const units = try gpa.alloc(u16, bytes.len / 2);
    defer gpa.free(units);
    for (units, 0..) |*u, i| u.* = std.mem.readInt(u16, bytes[i * 2 ..][0..2], .little);
    const text = try std.unicode.wtf16LeToWtf8Alloc(gpa, units);
    defer gpa.free(text);
    var lines = std.mem.tokenizeAny(u8, text, "\r\n");
    while (lines.next()) |line| {
        const name = std.mem.trim(u8, std.mem.trimStart(u8, line, "\u{FEFF}"), " \t\x00");
        if (name.len == 0) continue;
        try out.append(gpa, try gpa.dupe(u8, name));
    }
    return out.toOwnedSlice(gpa);
}

/// A Windows path as the distro sees it, in `out`.
pub fn toLinux(path: []const u8, out: []u8) ?[]const u8 {
    const shares = [_][]const u8{ "\\\\wsl.localhost\\", "\\\\wsl$\\" };
    for (shares) |share| if (std.ascii.startsWithIgnoreCase(path, share)) {
        // \\wsl.localhost\Ubuntu\home\ana -> /home/ana
        const rest = path[share.len..];
        const cut = std.mem.indexOfAny(u8, rest, "\\/") orelse return copySlashed(out, "/");
        return copySlashed(out, rest[cut..]);
    };
    if (path.len >= 2 and std.ascii.isAlphabetic(path[0]) and path[1] == ':') {
        const head = std.fmt.bufPrint(out, "/mnt/{c}", .{std.ascii.toLower(path[0])}) catch return null;
        const tail = copySlashed(out[head.len..], path[2..]) orelse return null;
        return out[0 .. head.len + tail.len];
    }
    return null;
}

/// A path of `distro` as Windows sees it, in `out`.
pub fn toWindows(distro: []const u8, path: []const u8, out: []u8) ?[]const u8 {
    if (std.mem.startsWith(u8, path, "/mnt/") and path.len >= 6 and std.ascii.isAlphabetic(path[5]) and (path.len == 6 or path[6] == '/')) {
        const head = std.fmt.bufPrint(out, "{c}:", .{std.ascii.toUpper(path[5])}) catch return null;
        const rest = if (path.len == 6) "\\" else path[6..];
        const tail = copyBackslashed(out[head.len..], rest) orelse return null;
        return out[0 .. head.len + tail.len];
    }
    if (path.len == 0 or path[0] != '/') return null;
    const head = std.fmt.bufPrint(out, "\\\\wsl.localhost\\{s}", .{distro}) catch return null;
    const tail = copyBackslashed(out[head.len..], path) orelse return null;
    return out[0 .. head.len + tail.len];
}

fn copySlashed(out: []u8, text: []const u8) ?[]const u8 {
    if (text.len > out.len) return null;
    for (text, 0..) |b, i| out[i] = if (b == '\\') '/' else b;
    return out[0..text.len];
}

fn copyBackslashed(out: []u8, text: []const u8) ?[]const u8 {
    if (text.len > out.len) return null;
    for (text, 0..) |b, i| out[i] = if (b == '/') '\\' else b;
    return out[0..text.len];
}

const testing = std.testing;

test "the distro list in wsl.exe's UTF-16, BOM and blank lines included" {
    const raw = "\xff\xfeU\x00b\x00u\x00n\x00t\x00u\x00\r\x00\n\x00D\x00e\x00b\x00i\x00a\x00n\x00\r\x00\n\x00\r\x00\n\x00";
    const list = try parseList(testing.allocator, raw);
    defer {
        for (list) |d| testing.allocator.free(d);
        testing.allocator.free(list);
    }
    try testing.expectEqual(@as(usize, 2), list.len);
    try testing.expectEqualStrings("Ubuntu", list[0]);
    try testing.expectEqualStrings("Debian", list[1]);
}

test "paths cross between Windows and the distro" {
    var buf: [256]u8 = undefined;
    try testing.expectEqualStrings("/mnt/c/Users/ana/code", toLinux("C:\\Users\\ana\\code", &buf).?);
    try testing.expectEqualStrings("/home/ana", toLinux("\\\\wsl.localhost\\Ubuntu\\home\\ana", &buf).?);
    try testing.expectEqualStrings("C:\\Users\\ana", toWindows("Ubuntu", "/mnt/c/Users/ana", &buf).?);
    try testing.expectEqualStrings("\\\\wsl.localhost\\Ubuntu\\home\\ana", toWindows("Ubuntu", "/home/ana", &buf).?);
    try testing.expect(toWindows("Ubuntu", "relative", &buf) == null);
}
