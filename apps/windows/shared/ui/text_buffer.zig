//! The text of a one-line field and its caret and selection, in UTF-8 byte
//! offsets always on code point boundaries. Pure, so the editing rules are
//! tested anywhere; text_field.zig draws it and feeds it keys.

const std = @import("std");

pub const TextBuffer = struct {
    bytes: std.ArrayList(u8) = .empty,
    caret: usize = 0,
    /// The other end of the selection; equal to caret when none.
    anchor: usize = 0,

    pub fn deinit(self: *TextBuffer, gpa: std.mem.Allocator) void {
        self.bytes.deinit(gpa);
    }

    pub fn text(self: *const TextBuffer) []const u8 {
        return self.bytes.items;
    }

    pub fn set(self: *TextBuffer, gpa: std.mem.Allocator, value: []const u8) !void {
        self.bytes.clearRetainingCapacity();
        try self.bytes.appendSlice(gpa, value);
        self.caret = value.len;
        self.anchor = value.len;
    }

    pub fn hasSelection(self: *const TextBuffer) bool {
        return self.caret != self.anchor;
    }

    pub fn selection(self: *const TextBuffer) struct { start: usize, end: usize } {
        return .{ .start = @min(self.caret, self.anchor), .end = @max(self.caret, self.anchor) };
    }

    pub fn selected(self: *const TextBuffer) []const u8 {
        const s = self.selection();
        return self.bytes.items[s.start..s.end];
    }

    pub fn selectAll(self: *TextBuffer) void {
        self.anchor = 0;
        self.caret = self.bytes.items.len;
    }

    fn deleteSelection(self: *TextBuffer) void {
        const s = self.selection();
        self.bytes.replaceRangeAssumeCapacity(s.start, s.end - s.start, &.{});
        self.caret = s.start;
        self.anchor = s.start;
    }

    /// Replaces the selection with `value` (typing, pasting). Line breaks
    /// become spaces: the field has one line.
    pub fn insert(self: *TextBuffer, gpa: std.mem.Allocator, value: []const u8) !void {
        self.deleteSelection();
        try self.bytes.insertSlice(gpa, self.caret, value);
        for (self.bytes.items[self.caret..][0..value.len]) |*b| {
            if (b.* == '\n' or b.* == '\r' or b.* == '\t') b.* = ' ';
        }
        self.caret += value.len;
        self.anchor = self.caret;
    }

    pub fn backspace(self: *TextBuffer, by_word: bool) void {
        if (self.hasSelection()) return self.deleteSelection();
        self.anchor = if (by_word) self.wordStartBefore(self.caret) else prevBoundary(self.bytes.items, self.caret);
        self.deleteSelection();
    }

    pub fn delete(self: *TextBuffer, by_word: bool) void {
        if (self.hasSelection()) return self.deleteSelection();
        self.anchor = if (by_word) self.wordEndAfter(self.caret) else nextBoundary(self.bytes.items, self.caret);
        self.deleteSelection();
    }

    pub const Motion = enum { left, right, word_left, word_right, home, end };

    /// Moves the caret; `extend` keeps the anchor (Shift held). Without
    /// it, left and right first collapse a selection to its side.
    pub fn move(self: *TextBuffer, motion: Motion, extend: bool) void {
        const items = self.bytes.items;
        if (!extend and self.hasSelection() and (motion == .left or motion == .right)) {
            const s = self.selection();
            self.caret = if (motion == .left) s.start else s.end;
            self.anchor = self.caret;
            return;
        }
        self.caret = switch (motion) {
            .left => prevBoundary(items, self.caret),
            .right => nextBoundary(items, self.caret),
            .word_left => self.wordStartBefore(self.caret),
            .word_right => self.wordEndAfter(self.caret),
            .home => 0,
            .end => items.len,
        };
        if (!extend) self.anchor = self.caret;
    }

    /// Puts the caret at `at` (a click), or selects the word there (double).
    pub fn place(self: *TextBuffer, at: usize, extend: bool) void {
        self.caret = @min(at, self.bytes.items.len);
        if (!extend) self.anchor = self.caret;
    }

    pub fn selectWordAt(self: *TextBuffer, at: usize) void {
        self.anchor = self.wordStartBefore(nextBoundary(self.bytes.items, at));
        self.caret = self.wordEndAfter(self.anchor);
    }

    fn isWordByte(b: u8) bool {
        return std.ascii.isAlphanumeric(b) or b == '_' or b >= 0x80;
    }

    fn wordStartBefore(self: *const TextBuffer, from: usize) usize {
        const items = self.bytes.items;
        var i = from;
        while (i > 0 and !isWordByte(items[i - 1])) i -= 1;
        while (i > 0 and isWordByte(items[i - 1])) i -= 1;
        return i;
    }

    fn wordEndAfter(self: *const TextBuffer, from: usize) usize {
        const items = self.bytes.items;
        var i = from;
        while (i < items.len and !isWordByte(items[i])) i += 1;
        while (i < items.len and isWordByte(items[i])) i += 1;
        return i;
    }
};

fn prevBoundary(items: []const u8, from: usize) usize {
    if (from == 0) return 0;
    var i = from - 1;
    while (i > 0 and items[i] & 0xC0 == 0x80) i -= 1;
    return i;
}

fn nextBoundary(items: []const u8, from: usize) usize {
    if (from >= items.len) return items.len;
    var i = from + 1;
    while (i < items.len and items[i] & 0xC0 == 0x80) i += 1;
    return i;
}

const testing = std.testing;

test "typing, moving and deleting keep to code points" {
    var b: TextBuffer = .{};
    defer b.deinit(testing.allocator);
    try b.insert(testing.allocator, "olá mundo");
    b.move(.left, false);
    b.move(.word_left, false);
    try testing.expectEqual(@as(usize, 5), b.caret);
    b.backspace(false);
    b.backspace(false);
    try testing.expectEqualStrings("olmundo", b.text());
    b.move(.home, false);
    b.move(.word_right, true);
    try testing.expectEqualStrings("olmundo", b.selected());
    try b.insert(testing.allocator, "a\nb");
    try testing.expectEqualStrings("a b", b.text());
}

test "a selection collapses to its side and words select whole" {
    var b: TextBuffer = .{};
    defer b.deinit(testing.allocator);
    try b.set(testing.allocator, "abc def");
    b.selectAll();
    b.move(.left, false);
    try testing.expectEqual(@as(usize, 0), b.caret);
    b.selectWordAt(5);
    try testing.expectEqualStrings("def", b.selected());
    b.delete(false);
    try testing.expectEqualStrings("abc ", b.text());
}

test {
    @import("std").testing.refAllDecls(@This());
}
