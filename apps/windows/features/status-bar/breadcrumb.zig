//! The pieces of a folder as the status bar shows them (docs/spec/status-bar.md):
//! "Home › Cadu › Trabalho › cadex", the user's folder as "Home", and each
//! piece's full path for its menu. Pure, so the rules are tested anywhere.

const std = @import("std");

pub const Piece = struct { name: []const u8, path: []const u8 };

/// Splits `folder` (C:\Users\ana\code or \\server\share\x) into pieces,
/// in `arena`. Under `home` the first piece is "Home".
pub fn pieces(arena: std.mem.Allocator, folder: []const u8, home: ?[]const u8) ![]Piece {
    var out: std.ArrayList(Piece) = .empty;
    var rest = folder;
    if (home) |h| {
        const trimmed = std.mem.trimEnd(u8, h, "\\/");
        if (trimmed.len > 0 and std.ascii.startsWithIgnoreCase(folder, trimmed) and (folder.len == trimmed.len or isSep(folder[trimmed.len]))) {
            try out.append(arena, .{ .name = "Home", .path = folder[0..trimmed.len] });
            rest = folder[trimmed.len..];
        }
    }
    if (out.items.len == 0) {
        // The drive ("C:") or the share ("\\server\share") is the first piece.
        const root_end = rootEnd(folder);
        if (root_end > 0) {
            try out.append(arena, .{ .name = std.mem.trimEnd(u8, folder[0..root_end], "\\/"), .path = folder[0..root_end] });
            rest = folder[root_end..];
        }
    }
    var it = std.mem.tokenizeAny(u8, rest, "\\/");
    while (it.next()) |name| {
        const end = @intFromPtr(name.ptr) - @intFromPtr(folder.ptr) + name.len;
        try out.append(arena, .{ .name = name, .path = folder[0..end] });
    }
    return out.items;
}

fn isSep(b: u8) bool {
    return b == '\\' or b == '/';
}

fn rootEnd(folder: []const u8) usize {
    if (folder.len >= 2 and folder[1] == ':') return if (folder.len >= 3 and isSep(folder[2])) 3 else 2;
    if (std.mem.startsWith(u8, folder, "\\\\")) {
        var seps: usize = 0;
        for (folder[2..], 2..) |b, i| if (isSep(b)) {
            seps += 1;
            if (seps == 2) return i + 1;
        };
        return folder.len;
    }
    if (folder.len > 0 and isSep(folder[0])) return 1;
    return 0;
}

const testing = std.testing;

test "home becomes Home and the rest are its folders" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const got = try pieces(arena.allocator(), "C:\\Users\\ana\\code\\cadex", "C:\\Users\\ana");
    try testing.expectEqual(@as(usize, 3), got.len);
    try testing.expectEqualStrings("Home", got[0].name);
    try testing.expectEqualStrings("cadex", got[2].name);
    try testing.expectEqualStrings("C:\\Users\\ana\\code", got[1].path);
}

test "outside home the drive leads" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const got = try pieces(arena.allocator(), "D:\\work\\x", "C:\\Users\\ana");
    try testing.expectEqualStrings("D:", got[0].name);
    try testing.expectEqualStrings("x", got[2].name);
}
