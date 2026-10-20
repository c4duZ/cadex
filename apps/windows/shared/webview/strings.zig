//! Strings across WebView2: it takes UTF-16 and hands back UTF-16 it
//! allocated with CoTaskMemAlloc, which the caller frees with CoTaskMemFree.

const std = @import("std");
const w = @import("win32");
const c = w.c;

/// UTF-8 to a NUL-terminated UTF-16 copy (bad bytes become U+FFFD).
pub fn wide(gpa: std.mem.Allocator, text: []const u8) ![:0]u16 {
    return std.unicode.wtf8ToWtf16LeAllocZ(gpa, text) catch {
        // Not even WTF-8 (a stray byte): go through the lossy converter.
        const buf = try gpa.alloc(u16, text.len + 1);
        defer gpa.free(buf);
        const got = @import("gfx").utf16(buf, text);
        return gpa.dupeZ(u16, got);
    };
}

/// A string WebView2 returned (LPWSTR) as UTF-8 owned by `gpa`; frees it.
pub fn take(gpa: std.mem.Allocator, value: c.LPWSTR) ?[]u8 {
    const raw = value orelse return null;
    defer c.CoTaskMemFree(raw);
    const len = std.mem.len(@as([*:0]u16, @ptrCast(raw)));
    return std.unicode.wtf16LeToWtf8Alloc(gpa, @as([*]u16, @ptrCast(raw))[0..len]) catch null;
}

test "round trip through UTF-16" {
    const gpa = std.testing.allocator;
    const w16 = try wide(gpa, "olá https://x");
    defer gpa.free(w16);
    try std.testing.expectEqual(@as(usize, 13), w16.len);
    try std.testing.expectEqual(@as(u16, 0xE1), w16[2]);
}

test {
    @import("win32").refAllDeep(@This());
}
