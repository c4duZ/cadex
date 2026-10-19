//! Handing bytes to the apps through out-parameters, the same way in every
//! feature's C API: a malloc'd copy the app frees with cadex_free.

const std = @import("std");
const status = @import("../status.zig");

const gpa = std.heap.c_allocator;

/// Copies `bytes` for the app. A null `out` skips the copy.
pub fn handOut(bytes: []const u8, out: ?*?[*]u8, out_len: ?*usize) status.Code {
    const ptr = out orelse return status.ok;
    // malloc(0) may return NULL, which reads as "no result": keep one byte.
    const copy = gpa.alloc(u8, @max(bytes.len, 1)) catch return status.out_of_memory;
    @memcpy(copy[0..bytes.len], bytes);
    ptr.* = copy.ptr;
    if (out_len) |len| len.* = bytes.len;
    return status.ok;
}

/// Sets the out-parameters to "nothing" before a call fills them.
pub fn clearOut(out: ?*?[*]u8, out_len: ?*usize) void {
    if (out) |ptr| ptr.* = null;
    if (out_len) |len| len.* = 0;
}

test "hands out a copy and an empty result that is still a buffer" {
    var out: ?[*]u8 = null;
    var len: usize = 9;
    try std.testing.expectEqual(status.ok, handOut("abc", &out, &len));
    try std.testing.expectEqualStrings("abc", out.?[0..len]);
    std.c.free(out);
    try std.testing.expectEqual(status.ok, handOut("", &out, &len));
    try std.testing.expect(out != null and len == 0);
    std.c.free(out);
    clearOut(&out, &len);
    try std.testing.expect(out == null);
}
