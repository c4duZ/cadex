//! Undo and redo of a Buffer (buffer.zig): each record is one replacement
//! (what was there, what went in), and typing or deleting in a row joins
//! one record, as Windows text boxes undo a word at a time. Pure.

const std = @import("std");

pub const Kind = enum {
    /// Typed characters: joined while the caret goes on from the last one.
    typing,
    /// Backspace and Delete: joined while they keep at the same place.
    deleting,
    /// Paste, cut, a suggestion, Enter: always a record of its own.
    other,
};

pub const Record = struct {
    start: usize,
    removed: []u8,
    inserted: []u8,
    /// Where the caret and the anchor were before, for undo to put back.
    caret_before: usize,
    anchor_before: usize,
    kind: Kind,

    fn free(self: Record, gpa: std.mem.Allocator) void {
        gpa.free(self.removed);
        gpa.free(self.inserted);
    }
};

/// The most records kept; the oldest go first.
const max_records = 1000;

pub const History = struct {
    undo_list: std.ArrayList(Record) = .empty,
    redo_list: std.ArrayList(Record) = .empty,
    /// The next edit starts a new record (the caret moved, a save, an undo).
    sealed: bool = true,

    pub fn deinit(self: *History, gpa: std.mem.Allocator) void {
        for (self.undo_list.items) |r| r.free(gpa);
        for (self.redo_list.items) |r| r.free(gpa);
        self.undo_list.deinit(gpa);
        self.redo_list.deinit(gpa);
    }

    pub fn clear(self: *History, gpa: std.mem.Allocator) void {
        self.deinit(gpa);
        self.* = .{};
    }

    pub fn seal(self: *History) void {
        self.sealed = true;
    }

    /// Notes that [start, start + removed.len) became `inserted`.
    pub fn record(self: *History, gpa: std.mem.Allocator, start: usize, removed: []const u8, inserted: []const u8, caret_before: usize, anchor_before: usize, kind: Kind) !void {
        for (self.redo_list.items) |r| r.free(gpa);
        self.redo_list.clearRetainingCapacity();
        if (!self.sealed and self.join(gpa, start, removed, inserted, kind)) return;
        const owned_removed = try gpa.dupe(u8, removed);
        errdefer gpa.free(owned_removed);
        const owned_inserted = try gpa.dupe(u8, inserted);
        errdefer gpa.free(owned_inserted);
        if (self.undo_list.items.len >= max_records) self.undo_list.orderedRemove(0).free(gpa);
        try self.undo_list.append(gpa, .{
            .start = start,
            .removed = owned_removed,
            .inserted = owned_inserted,
            .caret_before = caret_before,
            .anchor_before = anchor_before,
            .kind = kind,
        });
        self.sealed = kind == .other;
    }

    /// Adds the edit to the last record when it continues it; true when it did.
    fn join(self: *History, gpa: std.mem.Allocator, start: usize, removed: []const u8, inserted: []const u8, kind: Kind) bool {
        if (self.undo_list.items.len == 0) return false;
        const last = &self.undo_list.items[self.undo_list.items.len - 1];
        if (last.kind != kind) return false;
        switch (kind) {
            .typing => {
                if (removed.len != 0 or start != last.start + last.inserted.len) return false;
                // A space after a word starts the next record: undo goes back a word.
                const prev = last.inserted[last.inserted.len - 1];
                if (inserted.len > 0 and isSpace(inserted[0]) and !isSpace(prev)) return false;
                const grown = gpa.realloc(last.inserted, last.inserted.len + inserted.len) catch return false;
                @memcpy(grown[last.inserted.len..], inserted);
                last.inserted = grown;
                return true;
            },
            .deleting => {
                if (inserted.len != 0 or last.inserted.len != 0) return false;
                if (start + removed.len == last.start) {
                    // Backspace: the removed text goes before.
                    const grown = gpa.alloc(u8, removed.len + last.removed.len) catch return false;
                    @memcpy(grown[0..removed.len], removed);
                    @memcpy(grown[removed.len..], last.removed);
                    gpa.free(last.removed);
                    last.removed = grown;
                    last.start = start;
                    return true;
                }
                if (start == last.start) {
                    // Delete: the removed text goes after.
                    const grown = gpa.realloc(last.removed, last.removed.len + removed.len) catch return false;
                    @memcpy(grown[last.removed.len..], removed);
                    last.removed = grown;
                    return true;
                }
                return false;
            },
            .other => return false,
        }
    }

    /// The record to undo, moved to the redo list; the caller applies it.
    pub fn popUndo(self: *History, gpa: std.mem.Allocator) ?Record {
        const r = self.undo_list.pop() orelse return null;
        self.sealed = true;
        self.redo_list.append(gpa, r) catch {
            r.free(gpa);
            return null;
        };
        return r;
    }

    pub fn popRedo(self: *History, gpa: std.mem.Allocator) ?Record {
        const r = self.redo_list.pop() orelse return null;
        self.sealed = true;
        self.undo_list.append(gpa, r) catch {
            r.free(gpa);
            return null;
        };
        return r;
    }
};

fn isSpace(b: u8) bool {
    return b == ' ' or b == '\t' or b == '\n' or b == '\r';
}

test "typing joins until a space after a word" {
    const gpa = std.testing.allocator;
    var h: History = .{};
    defer h.deinit(gpa);
    try h.record(gpa, 0, "", "a", 0, 0, .typing);
    try h.record(gpa, 1, "", "b", 1, 1, .typing);
    try h.record(gpa, 2, "", " ", 2, 2, .typing);
    try std.testing.expectEqual(@as(usize, 2), h.undo_list.items.len);
    try std.testing.expectEqualStrings("ab", h.undo_list.items[0].inserted);
    h.seal();
    try h.record(gpa, 3, "", "c", 3, 3, .typing);
    try std.testing.expectEqual(@as(usize, 3), h.undo_list.items.len);
}

test "backspaces join backwards, deletes forwards" {
    const gpa = std.testing.allocator;
    var h: History = .{};
    defer h.deinit(gpa);
    try h.record(gpa, 4, "d", "", 5, 5, .deleting);
    try h.record(gpa, 3, "c", "", 4, 4, .deleting);
    try std.testing.expectEqualStrings("cd", h.undo_list.items[0].removed);
    try std.testing.expectEqual(@as(usize, 3), h.undo_list.items[0].start);
    try h.record(gpa, 3, "x", "", 3, 3, .deleting);
    try std.testing.expectEqualStrings("cdx", h.undo_list.items[0].removed);
}

test {
    @import("win32").refAllDeep(@This());
}
