//! What the text before the caret asks to complete (docs/spec/markdown.md,
//! "Editar"): a path after `](`, a heading after `](file#`, a note after
//! `[[`; the path written from one note to another; and the byte offsets
//! of the core's UTF-16 link ranges. Pure (the Mac's CompletionTrigger).

const std = @import("std");

pub const Trigger = struct {
    what: What,
    /// The part typed so far, replaced by the choice (bytes of the text).
    start: usize,
    end: usize,
    query: []const u8,
    /// For a heading: the file before `#` (empty: this note).
    file: []const u8 = "",

    pub const What = enum { path, heading, note };
};

/// Looks back on the caret's line only, at most this far.
const look_back = 300;

pub fn detect(text: []const u8, caret: usize) ?Trigger {
    if (caret > text.len) return null;
    const line_start = if (std.mem.lastIndexOfScalar(u8, text[0..caret], '\n')) |nl| nl + 1 else 0;
    const from = @max(line_start, caret -| look_back);
    const before = text[from..caret];
    const link = std.mem.lastIndexOf(u8, before, "](");
    const wiki = std.mem.lastIndexOf(u8, before, "[[");
    if (wiki) |wi| if (link == null or wi > link.?) {
        const typed = before[wi + 2 ..];
        if (std.mem.indexOfScalar(u8, typed, ']') != null) return null;
        return .{ .what = .note, .start = from + wi + 2, .end = caret, .query = typed };
    };
    const li = link orelse return null;
    const typed = before[li + 2 ..];
    if (std.mem.indexOfAny(u8, typed, ") ") != null) return null;
    const start = from + li + 2;
    if (std.mem.indexOfScalar(u8, typed, '#')) |hash| {
        return .{ .what = .heading, .start = start + hash + 1, .end = caret, .query = typed[hash + 1 ..], .file = typed[0..hash] };
    }
    return .{ .what = .path, .start = start, .end = caret, .query = typed };
}

/// `target` (relative to the root, with /) as written from the note
/// `from` (relative too): ../spec/search.md.
pub fn relativePath(arena: std.mem.Allocator, target: []const u8, from: []const u8) ![]const u8 {
    var from_dirs: std.ArrayList([]const u8) = .empty;
    var parts: std.ArrayList([]const u8) = .empty;
    var it = std.mem.tokenizeScalar(u8, from, '/');
    while (it.next()) |p| try from_dirs.append(arena, p);
    _ = from_dirs.pop();
    it = std.mem.tokenizeScalar(u8, target, '/');
    while (it.next()) |p| try parts.append(arena, p);
    var shared: usize = 0;
    while (shared < from_dirs.items.len and shared + 1 < parts.items.len and std.mem.eql(u8, from_dirs.items[shared], parts.items[shared])) shared += 1;
    var out: std.ArrayList(u8) = .empty;
    for (shared..from_dirs.items.len) |_| try out.appendSlice(arena, "../");
    for (parts.items[shared..], 0..) |p, i| {
        if (i > 0) try out.append(arena, '/');
        try out.appendSlice(arena, p);
    }
    return out.items;
}

/// `a/./b/../c.md` -> `a/c.md`.
pub fn normalize(arena: std.mem.Allocator, path: []const u8) ![]const u8 {
    var parts: std.ArrayList([]const u8) = .empty;
    var it = std.mem.tokenizeScalar(u8, path, '/');
    while (it.next()) |p| {
        if (std.mem.eql(u8, p, ".")) continue;
        if (std.mem.eql(u8, p, "..")) {
            _ = parts.pop();
        } else try parts.append(arena, p);
    }
    return std.mem.join(arena, "/", parts.items);
}

/// The byte offset of each UTF-16 position of `text`, going forward:
/// positions asked in order cost one pass over the text.
pub const Utf16Walker = struct {
    text: []const u8,
    byte: usize = 0,
    unit: u32 = 0,

    pub fn byteAt(self: *Utf16Walker, unit: u32) usize {
        if (unit < self.unit) {
            self.byte = 0;
            self.unit = 0;
        }
        while (self.unit < unit and self.byte < self.text.len) {
            const len = std.unicode.utf8ByteSequenceLength(self.text[self.byte]) catch 1;
            self.unit += if (len == 4) 2 else 1;
            self.byte = @min(self.byte + len, self.text.len);
        }
        return self.byte;
    }
};

const testing = std.testing;

test "the trigger follows ](, ](file# and [[ on the caret's line" {
    const path = detect("see [x](docs/sp", 15).?;
    try testing.expectEqual(Trigger.What.path, path.what);
    try testing.expectEqualStrings("docs/sp", path.query);
    try testing.expectEqual(@as(usize, 8), path.start);
    const heading = detect("[x](a.md#dec", 12).?;
    try testing.expectEqual(Trigger.What.heading, heading.what);
    try testing.expectEqualStrings("a.md", heading.file);
    try testing.expectEqualStrings("dec", heading.query);
    try testing.expectEqual(@as(usize, 9), heading.start);
    const note = detect("a [[No", 6).?;
    try testing.expectEqual(Trigger.What.note, note.what);
    try testing.expectEqualStrings("No", note.query);
    try testing.expect(detect("[[done]] after", 14) == null);
    try testing.expect(detect("[x](a.md) after", 15) == null);
    try testing.expect(detect("[x](\nnext", 9) == null);
}

test "paths are written relative to the note" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try testing.expectEqualStrings("../spec/search.md", try relativePath(a, "docs/spec/search.md", "docs/adr/0001.md"));
    try testing.expectEqualStrings("b.md", try relativePath(a, "docs/b.md", "docs/a.md"));
    try testing.expectEqualStrings("docs/b.md", try relativePath(a, "docs/b.md", "README.md"));
    try testing.expectEqualStrings("a/c.md", try normalize(a, "a/./b/../c.md"));
}

test "UTF-16 positions map to bytes" {
    var walker: Utf16Walker = .{ .text = "aé😀b" };
    try testing.expectEqual(@as(usize, 1), walker.byteAt(1));
    try testing.expectEqual(@as(usize, 3), walker.byteAt(2));
    try testing.expectEqual(@as(usize, 7), walker.byteAt(4));
    try testing.expectEqual(@as(usize, 1), walker.byteAt(1));
}

test {
    @import("win32").refAllDeep(@This());
}
