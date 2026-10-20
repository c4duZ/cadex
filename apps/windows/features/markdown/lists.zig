//! Enter in a list item starts the next one (`- `, `1. ` counting on,
//! `- [ ] ` for tasks); Enter on an empty item ends the list. Pure.

const std = @import("std");

pub const Continuation = union(enum) {
    /// Insert this after the line break.
    next: struct { prefix_len: usize, marker: [32]u8, marker_len: usize },
    /// The item is empty: take its marker away instead.
    end: usize,
};

/// What Enter does at the end of `line` (the caret's line up to the caret).
pub fn continuation(line: []const u8) ?Continuation {
    var i: usize = 0;
    while (i < line.len and (line[i] == ' ' or line[i] == '\t')) i += 1;
    const indent = line[0..i];
    var marker_end = i;
    var number: ?u64 = null;
    if (i < line.len and (line[i] == '-' or line[i] == '*' or line[i] == '+')) {
        marker_end = i + 1;
    } else {
        while (marker_end < line.len and std.ascii.isDigit(line[marker_end])) marker_end += 1;
        if (marker_end == i or marker_end - i > 9 or marker_end >= line.len or (line[marker_end] != '.' and line[marker_end] != ')')) return null;
        number = std.fmt.parseInt(u64, line[i..marker_end], 10) catch return null;
        marker_end += 1;
    }
    if (marker_end >= line.len or line[marker_end] != ' ') return null;
    var prefix_end = marker_end + 1;
    var task = false;
    if (line.len >= prefix_end + 4 and line[prefix_end] == '[' and line[prefix_end + 2] == ']' and line[prefix_end + 3] == ' ' and
        (line[prefix_end + 1] == ' ' or line[prefix_end + 1] == 'x' or line[prefix_end + 1] == 'X'))
    {
        task = true;
        prefix_end += 4;
    }
    if (std.mem.trim(u8, line[prefix_end..], " \t").len == 0) return .{ .end = prefix_end };
    var out: Continuation = .{ .next = .{ .prefix_len = prefix_end, .marker = undefined, .marker_len = 0 } };
    var w = std.Io.Writer.fixed(&out.next.marker);
    w.writeAll(indent) catch return null;
    if (number) |n| {
        w.print("{d}{c} ", .{ n + 1, line[marker_end - 1] }) catch return null;
    } else {
        w.print("{c} ", .{line[i]}) catch return null;
    }
    if (task) w.writeAll("[ ] ") catch return null;
    out.next.marker_len = w.end;
    return out;
}

const testing = std.testing;

fn nextOf(line: []const u8) []const u8 {
    const c = continuation(line).?;
    return c.next.marker[0..c.next.marker_len];
}

test "items continue, numbers count on, tasks start unchecked" {
    try testing.expectEqualStrings("- ", nextOf("- one"));
    try testing.expectEqualStrings("  * ", nextOf("  * two"));
    try testing.expectEqualStrings("3. ", nextOf("2. three"));
    try testing.expectEqualStrings("10) ", nextOf("9) nine"));
    try testing.expectEqualStrings("- [ ] ", nextOf("- [x] done"));
    try testing.expect(continuation("plain text") == null);
    try testing.expect(continuation("-not a list") == null);
    try testing.expect(continuation("2024 was") == null);
}

test "an empty item ends the list" {
    try testing.expectEqual(@as(usize, 2), continuation("- ").?.end);
    try testing.expectEqual(@as(usize, 6), continuation("- [ ] ").?.end);
    try testing.expectEqual(@as(usize, 5), continuation("  1. ").?.end);
}

test {
    @import("win32").refAllDeep(@This());
}
