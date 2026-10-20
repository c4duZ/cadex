//! The editing rules of buffer.zig: lines, motions, typing, deleting, undo.

const std = @import("std");
const Buffer = @import("buffer.zig").Buffer;
const Change = @import("buffer.zig").Change;

const testing = std.testing;
const gpa = testing.allocator;

test "lines start after each newline and end before CR" {
    var b = try Buffer.init(gpa, "ab\r\ncd\r\n\r\nend");
    defer b.deinit();
    try testing.expectEqual(@as(usize, 4), b.lineCount());
    try testing.expectEqual(@as(usize, 2), b.lineEnd(0));
    try testing.expectEqual(@as(usize, 4), b.lineStart(1));
    try testing.expectEqual(@as(usize, 8), b.lineEnd(2));
    try testing.expectEqual(@as(usize, 2), b.lineOf(9));
    try testing.expectEqual(@as(usize, 3), b.lineOf(b.text().len));
    try testing.expectEqualStrings("\r\n", b.newline);
}

test "an empty text has one line" {
    var b = try Buffer.init(gpa, "");
    defer b.deinit();
    try testing.expectEqual(@as(usize, 1), b.lineCount());
    try testing.expectEqual(@as(usize, 0), b.lineEnd(0));
}

test "inserting and deleting keep the line starts right" {
    var b = try Buffer.init(gpa, "one\ntwo\nthree");
    defer b.deinit();
    b.place(4, false);
    try b.insert("x\ny", .other);
    try testing.expectEqualStrings("one\nx\nytwo\nthree", b.text());
    try testing.expectEqual(@as(usize, 4), b.lineCount());
    try testing.expectEqual(@as(usize, 6), b.lineStart(2));
    try testing.expectEqual(@as(usize, 11), b.lineStart(3));
    b.selectRange(2, 7);
    try b.backspace(false);
    try testing.expectEqualStrings("ontwo\nthree", b.text());
    try testing.expectEqual(@as(usize, 2), b.lineCount());
    try testing.expectEqual(@as(usize, 6), b.lineStart(1));
}

test "motions keep to code points, words and CRLF" {
    var b = try Buffer.init(gpa, "olá mundo\r\nfim");
    defer b.deinit();
    b.place(4, false); // after "olá"
    b.move(.left, false);
    try testing.expectEqual(@as(usize, 2), b.caret);
    b.move(.word_right, false);
    try testing.expectEqual(@as(usize, 4), b.caret);
    b.move(.word_right, false);
    try testing.expectEqual(@as(usize, 10), b.caret);
    b.move(.right, false);
    try testing.expectEqual(@as(usize, 12), b.caret);
    b.move(.left, false);
    try testing.expectEqual(@as(usize, 10), b.caret);
    b.place(11, false); // between \r and \n
    try testing.expectEqual(@as(usize, 10), b.caret);
    b.move(.word_left, false);
    try testing.expectEqual(@as(usize, 5), b.caret);
    b.move(.doc_end, true);
    try testing.expectEqualStrings("mundo\r\nfim", b.selected());
}

test "home goes to the first non-blank, then the start" {
    var b = try Buffer.init(gpa, "    code();");
    defer b.deinit();
    b.place(8, false);
    b.move(.line_start, false);
    try testing.expectEqual(@as(usize, 4), b.caret);
    b.move(.line_start, false);
    try testing.expectEqual(@as(usize, 0), b.caret);
    b.move(.line_end, false);
    try testing.expectEqual(@as(usize, 11), b.caret);
}

test "a selection collapses to its side; word and line selections" {
    var b = try Buffer.init(gpa, "abc def\nxyz");
    defer b.deinit();
    b.selectAll();
    b.move(.left, false);
    try testing.expectEqual(@as(usize, 0), b.caret);
    b.selectWordAt(5);
    try testing.expectEqualStrings("def", b.selected());
    b.selectLineAt(2);
    try testing.expectEqualStrings("abc def\n", b.selected());
    b.selectWordAt(3);
    try testing.expectEqualStrings(" ", b.selected());
}

test "typing undoes a word at a time and redo puts it back" {
    var b = try Buffer.init(gpa, "");
    defer b.deinit();
    for ("hello world") |ch| try b.insert(&.{ch}, .typing);
    try testing.expect(try b.undo());
    try testing.expectEqualStrings("hello", b.text());
    try testing.expect(try b.undo());
    try testing.expectEqualStrings("", b.text());
    try testing.expect(!try b.undo());
    try testing.expect(try b.redo());
    try testing.expectEqualStrings("hello", b.text());
    try testing.expectEqual(@as(usize, 5), b.caret);
    try testing.expect(try b.redo());
    try testing.expectEqualStrings("hello world", b.text());
}

test "moving the caret starts a new undo step; a new edit drops redo" {
    var b = try Buffer.init(gpa, "");
    defer b.deinit();
    try b.insert("a", .typing);
    b.place(0, false);
    try b.insert("b", .typing);
    try testing.expectEqualStrings("ba", b.text());
    try testing.expect(try b.undo());
    try testing.expectEqualStrings("a", b.text());
    try b.insert("c", .typing);
    try testing.expect(!try b.redo());
}

test "backspaces join and undo restores the selection" {
    var b = try Buffer.init(gpa, "abcdef");
    defer b.deinit();
    b.place(6, false);
    try b.backspace(false);
    try b.backspace(false);
    try testing.expectEqualStrings("abcd", b.text());
    try testing.expect(try b.undo());
    try testing.expectEqualStrings("abcdef", b.text());
    try testing.expectEqual(@as(usize, 6), b.caret);
    b.selectRange(1, 3);
    try b.insert("X", .typing);
    try testing.expectEqualStrings("aXdef", b.text());
    try testing.expect(try b.undo());
    try testing.expectEqualStrings("bc", b.selected());
}

test "word deletes and a CRLF file keeps CRLF" {
    var b = try Buffer.init(gpa, "foo bar\r\n");
    defer b.deinit();
    b.place(7, false);
    try b.backspace(true);
    try testing.expectEqualStrings("foo \r\n", b.text());
    b.place(0, false);
    try b.delete(true);
    try testing.expectEqualStrings(" \r\n", b.text());
    b.place(1, false);
    try b.insert("a\nb", .other);
    try testing.expectEqualStrings(" a\r\nb\r\n", b.text());
    try testing.expectEqual(@as(usize, 3), b.lineCount());
    b.place(4, false);
    try b.backspace(false);
    try testing.expectEqualStrings(" ab\r\n", b.text());
}

test "the listener hears every change, undo included" {
    const Spy = struct {
        changes: std.ArrayList(Change) = .empty,
        fn changed(context: *anyopaque, _: *const Buffer, change: Change) void {
            const self: *@This() = @ptrCast(@alignCast(context));
            self.changes.append(gpa, change) catch {};
        }
    };
    var spy: Spy = .{};
    defer spy.changes.deinit(gpa);
    var b = try Buffer.init(gpa, "abc");
    defer b.deinit();
    b.listener = .{ .context = &spy, .changed = Spy.changed };
    b.place(1, false);
    try b.insert("XY", .other);
    _ = try b.undo();
    try testing.expectEqual(@as(usize, 2), spy.changes.items.len);
    try testing.expectEqual(Change{ .start = 1, .old_end = 1, .new_end = 3 }, spy.changes.items[0]);
    try testing.expectEqual(Change{ .start = 1, .old_end = 3, .new_end = 1 }, spy.changes.items[1]);
}

test "setText keeps the caret inside and forgets the history" {
    var b = try Buffer.init(gpa, "long text here");
    defer b.deinit();
    b.place(12, false);
    try b.insert("!", .typing);
    try b.setText("short");
    try testing.expectEqual(@as(usize, 5), b.caret);
    try testing.expect(!try b.undo());
}
