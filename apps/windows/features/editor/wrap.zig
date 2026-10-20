//! Long lines break at the width of the pane, with no horizontal scroll
//! (docs/spec/editor.md, "Ver"). The text is monospaced, so a row is a
//! number of columns: a code point takes one, a wide one (CJK, emoji) two,
//! a combining mark none, a tab up to the next stop of 4. Pure: columns,
//! rows and the text a row draws are tested here.

const std = @import("std");

pub const tab_width = 4;

/// Bytes [start, end) of the text shown on one row.
pub const Segment = struct { start: u32, end: u32 };

pub const Decoded = struct { cp: u21, len: u3 };

/// The code point at `i`; a bad byte is U+FFFD, one byte long.
pub fn decode(text: []const u8, i: usize) Decoded {
    const len = std.unicode.utf8ByteSequenceLength(text[i]) catch return .{ .cp = 0xFFFD, .len = 1 };
    if (i + len > text.len) return .{ .cp = 0xFFFD, .len = 1 };
    const cp = std.unicode.utf8Decode(text[i..][0..len]) catch return .{ .cp = 0xFFFD, .len = 1 };
    return .{ .cp = cp, .len = len };
}

/// Columns a code point takes (not a tab).
pub fn cpWidth(cp: u21) usize {
    if (cp >= 0x300 and cp <= 0x36F) return 0;
    if (cp == 0x200B or cp == 0x200D or (cp >= 0xFE00 and cp <= 0xFE0F)) return 0;
    if ((cp >= 0x1100 and cp <= 0x115F) or (cp >= 0x2E80 and cp <= 0xA4CF) or (cp >= 0xAC00 and cp <= 0xD7A3) or
        (cp >= 0xF900 and cp <= 0xFAFF) or (cp >= 0xFE30 and cp <= 0xFE4F) or (cp >= 0xFF00 and cp <= 0xFF60) or
        (cp >= 0xFFE0 and cp <= 0xFFE6) or (cp >= 0x1F300 and cp <= 0x1F64F) or (cp >= 0x1F900 and cp <= 0x1F9FF) or
        (cp >= 0x20000 and cp <= 0x3FFFD)) return 2;
    return 1;
}

/// The columns the code point takes when it starts at column `col`.
pub fn advance(cp: u21, col: usize) usize {
    if (cp == '\t') return tab_width - col % tab_width;
    if (cp == '\r') return 0;
    return cpWidth(cp);
}

/// Splits the line [start, end) (without its line end) into rows of at
/// most `cols` columns, breaking after a space when the row has one. An
/// empty line is one empty row; `cols` 0 is no wrapping.
pub fn splitLine(gpa: std.mem.Allocator, text: []const u8, start: usize, end: usize, cols: usize, out: *std.ArrayList(Segment)) !void {
    if (cols == 0) return out.append(gpa, .{ .start = @intCast(start), .end = @intCast(end) });
    var row_start = start;
    var col: usize = 0;
    var i = start;
    var after_space: ?usize = null;
    while (i < end) {
        const d = decode(text, i);
        const a = advance(d.cp, col);
        if (col + a > cols and i > row_start) {
            const brk = if (after_space) |s| (if (s > row_start) s else i) else i;
            try out.append(gpa, .{ .start = @intCast(row_start), .end = @intCast(brk) });
            row_start = brk;
            i = brk;
            col = 0;
            after_space = null;
            continue;
        }
        col += a;
        i += d.len;
        if (d.cp == ' ' or d.cp == '\t') after_space = i;
    }
    try out.append(gpa, .{ .start = @intCast(row_start), .end = @intCast(end) });
}

/// The column of byte `at` on the row that starts at `row_start`.
pub fn columnOf(text: []const u8, row_start: usize, at: usize) usize {
    var col: usize = 0;
    var i = row_start;
    while (i < at and i < text.len) {
        const d = decode(text, i);
        col += advance(d.cp, col);
        i += d.len;
    }
    return col;
}

/// The byte of the row [row_start, row_end) nearest to column `col` (a
/// click at x / cell width, a move up or down).
pub fn byteAt(text: []const u8, row_start: usize, row_end: usize, col: f32) usize {
    var at_col: usize = 0;
    var i = row_start;
    while (i < row_end) {
        const d = decode(text, i);
        if (d.cp == '\r') break;
        const a = advance(d.cp, at_col);
        if (@as(f32, @floatFromInt(at_col)) + @as(f32, @floatFromInt(a)) / 2 > col) return i;
        at_col += a;
        i += d.len;
    }
    return i;
}

/// The row's text as drawn: tabs as spaces to their stop, CR left out.
/// `map` gets, for each byte from row_start to row_end (inclusive), where
/// it lands in `out`, so colored ranges of the text find their place.
pub fn display(gpa: std.mem.Allocator, text: []const u8, row_start: usize, row_end: usize, out: *std.ArrayList(u8), map: *std.ArrayList(u32)) !void {
    var col: usize = 0;
    var i = row_start;
    while (i < row_end) {
        const d = decode(text, i);
        for (0..d.len) |_| try map.append(gpa, @intCast(out.items.len));
        switch (d.cp) {
            '\t' => {
                const a = advance('\t', col);
                try out.appendNTimes(gpa, ' ', a);
                col += a;
            },
            '\r' => {},
            else => {
                if (d.cp == 0xFFFD and d.len == 1) {
                    try out.appendSlice(gpa, "\u{FFFD}");
                } else {
                    try out.appendSlice(gpa, text[i..][0..d.len]);
                }
                col += cpWidth(d.cp);
            },
        }
        i += d.len;
    }
    try map.append(gpa, @intCast(out.items.len));
}

const testing = std.testing;

test "rows break after a space, or anywhere in a long word" {
    var out: std.ArrayList(Segment) = .empty;
    defer out.deinit(testing.allocator);
    const text = "one two three";
    try splitLine(testing.allocator, text, 0, text.len, 8, &out);
    try testing.expectEqual(@as(usize, 2), out.items.len);
    try testing.expectEqualStrings("one two ", text[out.items[0].start..out.items[0].end]);
    try testing.expectEqualStrings("three", text[out.items[1].start..out.items[1].end]);
    out.clearRetainingCapacity();
    try splitLine(testing.allocator, "abcdefghij", 0, 10, 4, &out);
    try testing.expectEqual(@as(usize, 3), out.items.len);
    try testing.expectEqual(@as(u32, 8), out.items[2].start);
    out.clearRetainingCapacity();
    try splitLine(testing.allocator, "", 0, 0, 4, &out);
    try testing.expectEqual(@as(usize, 1), out.items.len);
}

test "tabs go to the next stop and wide characters take two columns" {
    try testing.expectEqual(@as(usize, 4), columnOf("\tx", 0, 1));
    try testing.expectEqual(@as(usize, 4), columnOf("ab\tx", 0, 3));
    try testing.expectEqual(@as(usize, 2), columnOf("日x", 0, 3));
    try testing.expectEqual(@as(usize, 1), columnOf("é", 0, 2));
    try testing.expectEqual(@as(usize, 3), byteAt("ab\tcd", 0, 5, 3.4));
    try testing.expectEqual(@as(usize, 2), byteAt("ab\tcd", 0, 5, 2.1));
    try testing.expectEqual(@as(usize, 5), byteAt("ab\tcd", 0, 5, 40));
}

test "the drawn text expands tabs and maps every byte" {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(testing.allocator);
    var map: std.ArrayList(u32) = .empty;
    defer map.deinit(testing.allocator);
    try display(testing.allocator, "a\tbé\r", 0, 6, &out, &map);
    try testing.expectEqualStrings("a   bé", out.items);
    try testing.expectEqual(@as(usize, 7), map.items.len);
    try testing.expectEqual(@as(u32, 4), map.items[2]);
    try testing.expectEqual(@as(u32, 5), map.items[3]);
    try testing.expectEqual(@as(u32, 7), map.items[6]);
}

test {
    @import("win32").refAllDeep(@This());
}
