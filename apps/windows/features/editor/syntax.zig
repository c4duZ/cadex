//! The core's syntax tree of one open text (cadex_editor_*, ADR 0006):
//! colored spans and foldable blocks, in UTF-8 bytes like the buffer, so
//! the offsets go both ways as they are.

const std = @import("std");
const cadex = @import("cadex");
const folding = @import("folding.zig");

pub const Span = struct { start: u32, end: u32, kind: u8 };

pub const Syntax = struct {
    document: ?*cadex.cadex_editor_document = null,

    /// Parses `text` with the language of `file_name`; `enabled` false (a
    /// file above 1 MB) is plain text, as the core would make it anyway.
    pub fn open(gpa: std.mem.Allocator, file_name: []const u8, text: []const u8, enabled: bool) Syntax {
        if (!enabled) return .{};
        const name = gpa.dupeZ(u8, file_name) catch return .{};
        defer gpa.free(name);
        var out: ?*cadex.cadex_editor_document = null;
        if (cadex.cadex_editor_open(name.ptr, text.ptr, text.len, cadex.CADEX_TEXT_UTF8, &out) != cadex.CADEX_OK) return .{};
        return .{ .document = out };
    }

    pub fn close(self: *Syntax) void {
        if (self.document) |d| cadex.cadex_editor_close(d);
        self.document = null;
    }

    /// "Zig", or null for plain text.
    pub fn language(self: *const Syntax) ?[]const u8 {
        const d = self.document orelse return null;
        const name = cadex.cadex_editor_language(d) orelse return null;
        return std.mem.span(name);
    }

    /// [start, old_end) became `value`; the core reparses only that.
    pub fn edit(self: *Syntax, start: usize, old_end: usize, value: []const u8) void {
        const d = self.document orelse return;
        var lo: u32 = 0;
        var hi: u32 = 0;
        _ = cadex.cadex_editor_edit(d, @intCast(start), @intCast(old_end), value.ptr, value.len, &lo, &hi);
    }

    /// The spans in [start, end), in order, copied into `arena`.
    pub fn spans(self: *const Syntax, arena: std.mem.Allocator, start: usize, end: usize) []const Span {
        const d = self.document orelse return &.{};
        var out: [*c]cadex.cadex_editor_span = null;
        var count: usize = 0;
        if (cadex.cadex_editor_highlights(d, @intCast(start), @intCast(end), &out, &count) != cadex.CADEX_OK or out == null) return &.{};
        defer cadex.cadex_free(out);
        const copy = arena.alloc(Span, count) catch return &.{};
        for (copy, 0..) |*s, i| s.* = .{ .start = out[i].start, .end = out[i].end, .kind = out[i].kind };
        return copy;
    }

    /// The foldable blocks of the whole text.
    pub fn folds(self: *const Syntax, gpa: std.mem.Allocator) []folding.Region {
        const d = self.document orelse return &.{};
        var out: [*c]cadex.cadex_editor_fold = null;
        var count: usize = 0;
        if (cadex.cadex_editor_folds(d, &out, &count) != cadex.CADEX_OK or out == null) return &.{};
        defer cadex.cadex_free(out);
        const copy = gpa.alloc(folding.Region, count) catch return &.{};
        for (copy, 0..) |*r, i| r.* = .{ .start = out[i].start_row, .end = out[i].end_row };
        return copy;
    }
};

test {
    @import("win32").refAllDeep(@This());
}
