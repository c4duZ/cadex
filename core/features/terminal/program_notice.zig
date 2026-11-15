//! A program's desktop notification (OSC 777 `notify;title;body` and
//! OSC 9 `text`, parsed by libghostty-vt): handed to the app as two
//! NUL-terminated strings, cut to a size a notification shows. The app
//! posts it as a macOS notification (docs/spec/terminal.md; the owner's
//! choice of 2026-11-15: any program's, and the session kit leaves Claude
//! Code's preferredNotifChannel off, its stops already notify by hooks).

const std = @import("std");

pub const max_title = 256;
pub const max_body = 1024;

pub const Callback = *const fn (context: ?*anyopaque, title: [*:0]const u8, body: [*:0]const u8) callconv(.c) void;

/// Calls `callback` with copies of `title` and `body`, cut on a UTF-8
/// boundary and NUL-terminated; valid during the call.
pub fn forward(callback: Callback, context: ?*anyopaque, title: []const u8, body: []const u8) void {
    var t: [max_title + 1]u8 = undefined;
    var b: [max_body + 1]u8 = undefined;
    callback(context, terminate(&t, title), terminate(&b, body));
}

fn terminate(buf: []u8, text: []const u8) [*:0]const u8 {
    var n = @min(text.len, buf.len - 1);
    // Back off a cut inside a multibyte character.
    while (n > 0 and n < text.len and (text[n] & 0xC0) == 0x80) n -= 1;
    @memcpy(buf[0..n], text[0..n]);
    // A NUL inside would end the string early: it becomes a space.
    for (buf[0..n]) |*ch| if (ch.* == 0) {
        ch.* = ' ';
    };
    buf[n] = 0;
    return buf[0..n :0].ptr;
}

test "titles and bodies are cut on a character and end in NUL" {
    var buf: [5]u8 = undefined;
    try std.testing.expectEqualStrings("abc", std.mem.span(terminate(&buf, "abc")));
    // "açúcar": the cut at 4 bytes would split "ú".
    try std.testing.expectEqualStrings("aç", std.mem.span(terminate(&buf, "açúcar")));
    try std.testing.expectEqualStrings("a b", std.mem.span(terminate(&buf, "a\x00b")));
}
