//! The text of a code view or a note: bytes, line starts, caret and
//! selection, editing and undo, in UTF-8 byte offsets always on code point
//! boundaries. Pure, so the editing rules are tested anywhere; view.zig
//! draws it and feeds it keys. Files with CRLF keep it: Enter inserts the
//! file's line end and the caret never stops between \r and \n
//! (docs/spec/editor.md, "Casos de borda").

const std = @import("std");
const history_mod = @import("history.zig");

pub const Kind = history_mod.Kind;

/// [start, old_end) of the old text became [start, new_end) of the new.
pub const Change = struct { start: usize, old_end: usize, new_end: usize };

/// Told of every change after it happened (the syntax tree follows it).
pub const Listener = struct {
    context: *anyopaque,
    changed: *const fn (context: *anyopaque, buffer: *const Buffer, change: Change) void,
};

pub const Motion = enum { left, right, word_left, word_right, line_start, line_end, doc_start, doc_end };

pub const Buffer = struct {
    gpa: std.mem.Allocator,
    bytes: std.ArrayList(u8) = .empty,
    /// Byte offset where each line starts; always at least one (0).
    starts: std.ArrayList(u32) = .empty,
    caret: usize = 0,
    /// The other end of the selection; equal to caret when none.
    anchor: usize = 0,
    history: history_mod.History = .{},
    listener: ?Listener = null,
    /// "\r\n" when the file's first line ends so; what Enter inserts.
    newline: []const u8 = "\n",
    /// Bumped on every change of the text, for caches.
    version: u64 = 0,

    pub fn init(gpa: std.mem.Allocator, value: []const u8) !Buffer {
        var self: Buffer = .{ .gpa = gpa };
        errdefer self.deinit();
        try self.setText(value);
        return self;
    }

    pub fn deinit(self: *Buffer) void {
        self.bytes.deinit(self.gpa);
        self.starts.deinit(self.gpa);
        self.history.deinit(self.gpa);
    }

    pub fn text(self: *const Buffer) []const u8 {
        return self.bytes.items;
    }

    /// The whole text replaced (a load, a reload from disk): no undo across
    /// it, the caret kept where it can be.
    pub fn setText(self: *Buffer, value: []const u8) !void {
        self.bytes.clearRetainingCapacity();
        try self.bytes.appendSlice(self.gpa, value);
        self.starts.clearRetainingCapacity();
        try self.starts.append(self.gpa, 0);
        try appendStarts(self.gpa, &self.starts, value, 0);
        self.history.clear(self.gpa);
        const first_end = std.mem.indexOfScalar(u8, value, '\n');
        self.newline = if (first_end) |e| (if (e > 0 and value[e - 1] == '\r') "\r\n" else "\n") else "\n";
        self.caret = self.snap(@min(self.caret, value.len));
        self.anchor = self.caret;
        self.version +%= 1;
    }

    // ---- Lines ----

    pub fn lineCount(self: *const Buffer) usize {
        return self.starts.items.len;
    }

    pub fn lineStart(self: *const Buffer, line: usize) usize {
        return self.starts.items[@min(line, self.starts.items.len - 1)];
    }

    /// Where line `line` ends, before its \n (and a \r before that).
    pub fn lineEnd(self: *const Buffer, line: usize) usize {
        const items = self.bytes.items;
        var end = if (line + 1 < self.starts.items.len) self.starts.items[line + 1] - 1 else items.len;
        if (end > self.lineStart(line) and items[end - 1] == '\r') end -= 1;
        return end;
    }

    /// The line holding byte `at`.
    pub fn lineOf(self: *const Buffer, at: usize) usize {
        const starts = self.starts.items;
        var lo: usize = 0;
        var hi: usize = starts.len;
        while (hi - lo > 1) {
            const mid = (lo + hi) / 2;
            if (starts[mid] <= at) lo = mid else hi = mid;
        }
        return lo;
    }

    // ---- Selection ----

    pub fn hasSelection(self: *const Buffer) bool {
        return self.caret != self.anchor;
    }

    pub fn selection(self: *const Buffer) struct { start: usize, end: usize } {
        return .{ .start = @min(self.caret, self.anchor), .end = @max(self.caret, self.anchor) };
    }

    pub fn selected(self: *const Buffer) []const u8 {
        const s = self.selection();
        return self.bytes.items[s.start..s.end];
    }

    pub fn selectAll(self: *Buffer) void {
        self.history.seal();
        self.anchor = 0;
        self.caret = self.bytes.items.len;
    }

    /// Puts the caret at `at` (a click); `extend` keeps the anchor.
    pub fn place(self: *Buffer, at: usize, extend: bool) void {
        self.history.seal();
        self.caret = self.snap(@min(at, self.bytes.items.len));
        if (!extend) self.anchor = self.caret;
    }

    /// Selects [start, end) with the caret at the end (a search match).
    pub fn selectRange(self: *Buffer, start: usize, end: usize) void {
        self.history.seal();
        self.anchor = self.snap(@min(start, self.bytes.items.len));
        self.caret = self.snap(@min(end, self.bytes.items.len));
    }

    pub fn selectWordAt(self: *Buffer, at: usize) void {
        const items = self.bytes.items;
        const from = @min(at, items.len);
        if (from < items.len and !isWordByte(items[from])) {
            // Not on a word: just that character.
            return self.selectRange(from, nextBoundary(items, from));
        }
        self.selectRange(wordStartBefore(items, nextBoundary(items, from)), wordEndAfter(items, from));
    }

    /// The whole line of `at` with its line end (a triple click).
    pub fn selectLineAt(self: *Buffer, at: usize) void {
        const line = self.lineOf(at);
        const end = if (line + 1 < self.lineCount()) self.lineStart(line + 1) else self.bytes.items.len;
        self.selectRange(self.lineStart(line), end);
    }

    /// Moves the caret; `extend` keeps the anchor (Shift held). Without it,
    /// left and right first collapse a selection to its side.
    pub fn move(self: *Buffer, motion: Motion, extend: bool) void {
        const items = self.bytes.items;
        self.history.seal();
        if (!extend and self.hasSelection() and (motion == .left or motion == .right)) {
            const s = self.selection();
            self.caret = if (motion == .left) s.start else s.end;
            self.anchor = self.caret;
            return;
        }
        const line = self.lineOf(self.caret);
        self.caret = switch (motion) {
            .left => prevBoundary(items, self.caret),
            .right => nextBoundary(items, self.caret),
            .word_left => wordStartBefore(items, self.caret),
            .word_right => wordEndAfter(items, self.caret),
            .line_start => self.smartHome(line),
            .line_end => self.lineEnd(line),
            .doc_start => 0,
            .doc_end => items.len,
        };
        if (!extend) self.anchor = self.caret;
    }

    /// Home goes to the first non-blank of the line, and from there to its
    /// very start, as code editors on Windows do.
    fn smartHome(self: *const Buffer, line: usize) usize {
        const start = self.lineStart(line);
        var first = start;
        while (first < self.lineEnd(line) and (self.bytes.items[first] == ' ' or self.bytes.items[first] == '\t')) first += 1;
        return if (self.caret == first) start else first;
    }

    // ---- Editing ----

    /// Replaces [start, end) with `value` and records it for undo.
    pub fn replace(self: *Buffer, start: usize, end: usize, value: []const u8, kind: Kind) !void {
        try self.history.record(self.gpa, start, self.bytes.items[start..end], value, self.caret, self.anchor, kind);
        try self.apply(start, end, value);
        self.caret = start + value.len;
        self.anchor = self.caret;
    }

    /// The replacement itself, for edits and undo alike.
    fn apply(self: *Buffer, start: usize, end: usize, value: []const u8) !void {
        try self.bytes.replaceRange(self.gpa, start, end - start, value);
        try self.updateStarts(start, end, value);
        self.version +%= 1;
        if (self.listener) |l| l.changed(l.context, self, .{ .start = start, .old_end = end, .new_end = start + value.len });
    }

    /// Line starts after [start, old_end) became `value`: the starts inside
    /// go, the new ones come in, the ones after shift.
    fn updateStarts(self: *Buffer, start: usize, old_end: usize, value: []const u8) !void {
        const starts = &self.starts;
        const first = self.lineOf(start) + 1;
        var past = first;
        while (past < starts.items.len and starts.items[past] <= old_end) past += 1;
        var fresh: std.ArrayList(u32) = .empty;
        defer fresh.deinit(self.gpa);
        try appendStarts(self.gpa, &fresh, value, start);
        try starts.replaceRange(self.gpa, first, past - first, fresh.items);
        const delta: i64 = @as(i64, @intCast(value.len)) - @as(i64, @intCast(old_end - start));
        for (starts.items[first + fresh.items.len ..]) |*s| s.* = @intCast(@as(i64, s.*) + delta);
    }

    /// Typing and pasting: replaces the selection. Line breaks become the
    /// file's own.
    pub fn insert(self: *Buffer, value: []const u8, kind: Kind) !void {
        const s = self.selection();
        if (std.mem.eql(u8, self.newline, "\r\n") and std.mem.indexOfScalar(u8, value, '\n') != null) {
            const converted = try toCrlf(self.gpa, value);
            defer self.gpa.free(converted);
            return self.replace(s.start, s.end, converted, kind);
        }
        try self.replace(s.start, s.end, value, if (s.start != s.end) .other else kind);
    }

    pub fn backspace(self: *Buffer, by_word: bool) !void {
        const s = self.selection();
        if (s.start != s.end) return self.replace(s.start, s.end, "", .other);
        const from = if (by_word) wordStartBefore(self.bytes.items, self.caret) else prevBoundary(self.bytes.items, self.caret);
        if (from != self.caret) try self.replace(from, self.caret, "", .deleting);
    }

    pub fn delete(self: *Buffer, by_word: bool) !void {
        const s = self.selection();
        if (s.start != s.end) return self.replace(s.start, s.end, "", .other);
        const to = if (by_word) wordEndAfter(self.bytes.items, self.caret) else nextBoundary(self.bytes.items, self.caret);
        if (to != self.caret) try self.replace(self.caret, to, "", .deleting);
    }

    /// False when there was nothing to undo.
    pub fn undo(self: *Buffer) !bool {
        const r = self.history.popUndo(self.gpa) orelse return false;
        try self.apply(r.start, r.start + r.inserted.len, r.removed);
        self.caret = self.snap(@min(r.caret_before, self.bytes.items.len));
        self.anchor = self.snap(@min(r.anchor_before, self.bytes.items.len));
        return true;
    }

    pub fn redo(self: *Buffer) !bool {
        const r = self.history.popRedo(self.gpa) orelse return false;
        try self.apply(r.start, r.start + r.removed.len, r.inserted);
        self.caret = r.start + r.inserted.len;
        self.anchor = self.caret;
        return true;
    }

    /// Never between the \r and \n of a CRLF.
    fn snap(self: *const Buffer, at: usize) usize {
        const items = self.bytes.items;
        if (at > 0 and at < items.len and items[at - 1] == '\r' and items[at] == '\n') return at - 1;
        return at;
    }
};

fn appendStarts(gpa: std.mem.Allocator, out: *std.ArrayList(u32), value: []const u8, base: usize) !void {
    var i: usize = 0;
    while (std.mem.indexOfScalarPos(u8, value, i, '\n')) |nl| : (i = nl + 1) {
        try out.append(gpa, @intCast(base + nl + 1));
    }
}

fn toCrlf(gpa: std.mem.Allocator, value: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    for (value, 0..) |b, i| {
        if (b == '\n' and (i == 0 or value[i - 1] != '\r')) try out.append(gpa, '\r');
        try out.append(gpa, b);
    }
    return out.toOwnedSlice(gpa);
}

pub fn isWordByte(b: u8) bool {
    return std.ascii.isAlphanumeric(b) or b == '_' or b >= 0x80;
}

pub fn prevBoundary(items: []const u8, from: usize) usize {
    if (from == 0) return 0;
    if (from >= 2 and items[from - 1] == '\n' and items[from - 2] == '\r') return from - 2;
    var i = from - 1;
    while (i > 0 and items[i] & 0xC0 == 0x80) i -= 1;
    return i;
}

pub fn nextBoundary(items: []const u8, from: usize) usize {
    if (from >= items.len) return items.len;
    if (items[from] == '\r' and from + 1 < items.len and items[from + 1] == '\n') return from + 2;
    var i = from + 1;
    while (i < items.len and items[i] & 0xC0 == 0x80) i += 1;
    return i;
}

pub fn wordStartBefore(items: []const u8, from: usize) usize {
    var i = from;
    while (i > 0 and !isWordByte(items[i - 1])) i -= 1;
    while (i > 0 and isWordByte(items[i - 1])) i -= 1;
    return i;
}

pub fn wordEndAfter(items: []const u8, from: usize) usize {
    var i = from;
    while (i < items.len and !isWordByte(items[i])) i += 1;
    while (i < items.len and isWordByte(items[i])) i += 1;
    return i;
}

test {
    _ = @import("buffer_test.zig");
}

test {
    @import("win32").refAllDeep(@This());
}
