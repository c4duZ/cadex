//! Uses the terminal C API the way the apps do, through the exported
//! functions, to lock the contract in include/cadex.h.

const std = @import("std");
const testing = std.testing;
const api = @import("c_api.zig");
const status = @import("../../status.zig");

extern "c" fn usleep(microseconds: c_uint) c_int;

fn options() api.Options {
    return .{
        .cols = 80,
        .rows = 24,
        .cwd = null,
        .shell = "/bin/sh",
        .context = null,
        .on_output = null,
        .on_exit = null,
    };
}

test "open, write, read the text back and close through the C API" {
    testing.log_level = .err;
    var session: ?*@import("session.zig").Session = null;
    var o = options();
    try testing.expectEqual(status.ok, api.cadex_terminal_open(&o, &session));
    defer api.cadex_terminal_close(session);

    const input = "echo c-api-$((1+1))\n";
    try testing.expectEqual(status.ok, api.cadex_terminal_write(session, input.ptr, input.len));
    try testing.expectEqual(status.ok, api.cadex_terminal_resize(session, 100, 30, 8, 16));

    var found = false;
    var attempts: u32 = 0;
    while (!found and attempts < 250) : (attempts += 1) {
        var ptr: ?[*]u8 = null;
        var len: usize = 0;
        try testing.expectEqual(status.ok, api.cadex_terminal_copy_text(session, &ptr, &len));
        if (ptr) |p| found = std.mem.indexOf(u8, p[0..len], "c-api-2") != null;
        status.cadex_free(ptr);
        if (!found) _ = usleep(20 * 1000);
    }
    try testing.expect(found);
}

test "rejects invalid arguments instead of crashing" {
    var session: ?*@import("session.zig").Session = null;
    try testing.expectEqual(status.invalid_argument, api.cadex_terminal_open(null, &session));

    var zero = options();
    zero.cols = 0;
    try testing.expectEqual(status.invalid_argument, api.cadex_terminal_open(&zero, &session));
    try testing.expectEqual(status.invalid_argument, api.cadex_terminal_write(null, "x", 1));
    try testing.expectEqual(status.invalid_argument, api.cadex_terminal_resize(null, 80, 24, 0, 0));
    try testing.expect(!api.cadex_terminal_has_foreground_process(null));
    api.cadex_terminal_close(null);
}

test "keys go through the core's encoder" {
    testing.log_level = .err;
    var session: ?*@import("session.zig").Session = null;
    var o = options();
    try testing.expectEqual(status.ok, api.cadex_terminal_open(&o, &session));
    defer api.cadex_terminal_close(session);

    const up: u16 = 11;
    const ctrl: u8 = 1 << 1;
    try testing.expectEqual(status.ok, api.cadex_terminal_key(session, up, 0, null, 0, 0));
    try testing.expectEqual(status.ok, api.cadex_terminal_key(session, 0, ctrl, "c", 1, 'c'));
    try testing.expectEqual(status.invalid_argument, api.cadex_terminal_key(session, 999, 0, null, 0, 0));
    try testing.expectEqual(status.invalid_argument, api.cadex_terminal_key(session, 0, 0, null, 3, 0));
    try testing.expectEqual(status.invalid_argument, api.cadex_terminal_key(null, up, 0, null, 0, 0));
}

test "selection and scrolling through the C API" {
    testing.log_level = .err;
    var session: ?*@import("session.zig").Session = null;
    var o = options();
    try testing.expectEqual(status.ok, api.cadex_terminal_open(&o, &session));
    defer api.cadex_terminal_close(session);

    // Nothing selected: copying gives nothing.
    var ptr: ?[*]u8 = null;
    var len: usize = 0;
    try testing.expectEqual(status.ok, api.cadex_terminal_copy_selection(session, &ptr, &len));
    try testing.expect(ptr == null and len == 0);

    // Wait for the prompt, then select everything and copy it.
    const input = "echo sel-$((2+2))\n";
    try testing.expectEqual(status.ok, api.cadex_terminal_write(session, input.ptr, input.len));
    var found = false;
    var attempts: u32 = 0;
    while (!found and attempts < 250) : (attempts += 1) {
        _ = usleep(20 * 1000);
        try testing.expectEqual(status.ok, api.cadex_terminal_select_all(session));
        try testing.expectEqual(status.ok, api.cadex_terminal_copy_selection(session, &ptr, &len));
        if (ptr) |p| found = std.mem.indexOf(u8, p[0..len], "sel-4") != null;
        status.cadex_free(ptr);
    }
    try testing.expect(found);
    try testing.expect(api.cadex_terminal_has_selection(session));

    // Typing drops the selection.
    try testing.expectEqual(status.ok, api.cadex_terminal_write(session, " ", 1));
    try testing.expect(!api.cadex_terminal_has_selection(session));

    try testing.expectEqual(status.ok, api.cadex_terminal_scroll(session, -5));
    try testing.expectEqual(status.ok, api.cadex_terminal_scroll_to(session, api.scroll_bottom));
    try testing.expectEqual(status.invalid_argument, api.cadex_terminal_scroll_to(session, 9));
    try testing.expectEqual(status.invalid_argument, api.cadex_terminal_select_press(session, null, 1, false));
    try testing.expect(!api.cadex_terminal_has_selection(null));
}

test "paste and path quoting through the C API" {
    const paths = [_]?[*:0]const u8{ "/tmp/a b.txt", "/tmp/c" };
    var ptr: ?[*]u8 = null;
    var len: usize = 0;
    try testing.expectEqual(status.ok, api.cadex_terminal_quote_paths(&paths, paths.len, &ptr, &len));
    defer status.cadex_free(ptr);
    try testing.expectEqualStrings("'/tmp/a b.txt' /tmp/c", ptr.?[0..len]);

    var none: ?[*]u8 = null;
    try testing.expectEqual(status.ok, api.cadex_terminal_quote_paths(null, 0, &none, &len));
    try testing.expect(none == null and len == 0);

    testing.log_level = .err;
    var session: ?*@import("session.zig").Session = null;
    var o = options();
    try testing.expectEqual(status.ok, api.cadex_terminal_open(&o, &session));
    defer api.cadex_terminal_close(session);
    // /bin/sh has no bracketed paste: several lines are not safe.
    try testing.expect(!api.cadex_terminal_paste_is_safe(session, "a\nb", 3));
    try testing.expect(api.cadex_terminal_paste_is_safe(session, "a b", 3));
    try testing.expectEqual(status.ok, api.cadex_terminal_paste(session, "echo x", 6));
    try testing.expectEqual(status.invalid_argument, api.cadex_terminal_paste(null, "x", 1));
}
