//! The markdown feature's part of the C API (include/cadex.h). Answers are
//! lines of tab-separated fields: the app splits them, and the C API stays
//! a handful of calls instead of a struct per question.

const std = @import("std");
const status = @import("../../status.zig");
const workspace = @import("../workspace/workspace.zig");
const c_buffer = @import("../../shared/c_buffer.zig");
const html = @import("html.zig");
const Index = @import("index.zig").Index;
const queries = @import("queries.zig");

const gpa = std.heap.c_allocator;

fn bytes(ptr: ?[*]const u8, len: usize) ?[]const u8 {
    if (len == 0) return "";
    return (ptr orelse return null)[0..len];
}

pub export fn cadex_markdown_render(text: ?[*]const u8, len: usize, out: ?*?[*]u8, out_len: ?*usize) callconv(.c) status.Code {
    c_buffer.clearOut(out, out_len);
    const t = bytes(text, len) orelse return status.invalid_argument;
    const page = html.render(gpa, t) catch |err| return status.fromError(err);
    defer gpa.free(page);
    return c_buffer.handOut(page, out, out_len);
}

pub export fn cadex_markdown_index_open(root: ?[*:0]const u8, out: ?*?*Index) callconv(.c) status.Code {
    const result = out orelse return status.invalid_argument;
    result.* = null;
    const p = std.mem.span(root orelse return status.invalid_argument);
    result.* = Index.open(gpa, workspace.registry(), p) catch |err| return status.fromError(err);
    return status.ok;
}

pub export fn cadex_markdown_index_close(index: ?*Index) callconv(.c) void {
    if (index) |i| i.close();
}

pub export fn cadex_markdown_index_ready(index: ?*Index) callconv(.c) bool {
    const i = index orelse return false;
    return i.ready.load(.acquire);
}

/// Every note, one relative path per line.
pub export fn cadex_markdown_notes(index: ?*Index, out: ?*?[*]u8, out_len: ?*usize) callconv(.c) status.Code {
    c_buffer.clearOut(out, out_len);
    const i = index orelse return status.invalid_argument;
    var text: std.ArrayList(u8) = .empty;
    defer text.deinit(gpa);
    i.lock();
    for (i.notes.keys()) |rel| {
        text.appendSlice(gpa, rel) catch return unlockOom(i);
        text.append(gpa, '\n') catch return unlockOom(i);
    }
    i.unlock();
    return c_buffer.handOut(text.items, out, out_len);
}

fn unlockOom(i: *Index) status.Code {
    i.unlock();
    return status.out_of_memory;
}

/// The headings of a note: "level \t line \t anchor \t text" per line.
pub export fn cadex_markdown_headings(index: ?*Index, path: ?[*:0]const u8, out: ?*?[*]u8, out_len: ?*usize) callconv(.c) status.Code {
    c_buffer.clearOut(out, out_len);
    const i = index orelse return status.invalid_argument;
    const rel = i.relative(std.mem.span(path orelse return status.invalid_argument)) orelse return status.not_authorized;
    var text: std.ArrayList(u8) = .empty;
    defer text.deinit(gpa);
    i.lock();
    defer i.unlock();
    const note = i.notes.get(rel) orelse return status.not_found;
    for (note.headings) |h| {
        text.print(gpa, "{d}\t{d}\t{s}\t{s}\n", .{ h.level, h.row + 1, h.anchor, h.text }) catch return status.out_of_memory;
    }
    return c_buffer.handOut(text.items, out, out_len);
}

/// The links of `text` (the unsaved note at `path`): "start \t end \t kind
/// \t broken \t target \t line" per line; start and end in UTF-16 units,
/// kind 0 file / 1 wiki / 2 web, target absolute or empty, line of the
/// heading named (0 if none).
pub export fn cadex_markdown_links(index: ?*Index, path: ?[*:0]const u8, text: ?[*]const u8, len: usize, out: ?*?[*]u8, out_len: ?*usize) callconv(.c) status.Code {
    c_buffer.clearOut(out, out_len);
    const i = index orelse return status.invalid_argument;
    const rel = i.relative(std.mem.span(path orelse return status.invalid_argument)) orelse return status.not_authorized;
    const t = bytes(text, len) orelse return status.invalid_argument;
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const links = queries.checkLinks(arena.allocator(), i, rel, t) catch |err| return status.fromError(err);
    var lines: std.ArrayList(u8) = .empty;
    defer lines.deinit(gpa);
    var units: Utf16Offsets = .{ .text = t };
    for (links) |l| {
        lines.print(gpa, "{d}\t{d}\t{d}\t{d}\t", .{ units.at(l.start), units.at(l.end), @intFromEnum(l.kind), @intFromBool(l.broken) }) catch return status.out_of_memory;
        if (l.rel.len > 0) lines.print(gpa, "{s}/{s}", .{ i.root, l.rel }) catch return status.out_of_memory;
        lines.print(gpa, "\t{d}\n", .{if (l.row) |r| r + 1 else 0}) catch return status.out_of_memory;
    }
    return c_buffer.handOut(lines.items, out, out_len);
}

/// The notes pointing at `path`: "absolute path \t line" per line.
pub export fn cadex_markdown_backlinks(index: ?*Index, path: ?[*:0]const u8, out: ?*?[*]u8, out_len: ?*usize) callconv(.c) status.Code {
    c_buffer.clearOut(out, out_len);
    const i = index orelse return status.invalid_argument;
    const rel = i.relative(std.mem.span(path orelse return status.invalid_argument)) orelse return status.not_authorized;
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const list = queries.backlinks(arena.allocator(), i, rel) catch |err| return status.fromError(err);
    var lines: std.ArrayList(u8) = .empty;
    defer lines.deinit(gpa);
    for (list) |b| lines.print(gpa, "{s}/{s}\t{d}\n", .{ i.root, b.from, b.row + 1 }) catch return status.out_of_memory;
    return c_buffer.handOut(lines.items, out, out_len);
}

/// Where a destination written in `path` goes (a clicked link of the
/// rendered view): "absolute path \t line \t broken".
pub export fn cadex_markdown_resolve(index: ?*Index, path: ?[*:0]const u8, destination: ?[*:0]const u8, wiki: bool, out: ?*?[*]u8, out_len: ?*usize) callconv(.c) status.Code {
    c_buffer.clearOut(out, out_len);
    const i = index orelse return status.invalid_argument;
    const rel = i.relative(std.mem.span(path orelse return status.invalid_argument)) orelse return status.not_authorized;
    const dest = std.mem.span(destination orelse return status.invalid_argument);
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const l = queries.resolveDestination(arena.allocator(), i, rel, dest, wiki) catch |err| return status.fromError(err);
    if (l.rel.len == 0) return status.not_found;
    var line: std.ArrayList(u8) = .empty;
    defer line.deinit(gpa);
    line.print(gpa, "{s}/{s}\t{d}\t{d}", .{ i.root, l.rel, if (l.row) |r| r + 1 else 0, @intFromBool(l.broken) }) catch return status.out_of_memory;
    return c_buffer.handOut(line.items, out, out_len);
}

/// UTF-8 byte offsets to UTF-16 units, for offsets asked in rising order.
const Utf16Offsets = struct {
    text: []const u8,
    byte: usize = 0,
    units: usize = 0,

    fn at(self: *Utf16Offsets, target: usize) usize {
        if (target < self.byte) {
            self.byte = 0;
            self.units = 0;
        }
        while (self.byte < target and self.byte < self.text.len) {
            const lead = self.text[self.byte];
            const len: usize = if (lead < 0x80) 1 else if (lead >> 5 == 0b110) 2 else if (lead >> 4 == 0b1110) 3 else if (lead >> 3 == 0b11110) 4 else 1;
            self.units += if (len == 4) 2 else 1;
            self.byte += len;
        }
        return self.units;
    }
};

test "UTF-16 offsets of links after accents" {
    var o: Utf16Offsets = .{ .text = "é 😀 [x](a.md)" };
    try std.testing.expectEqual(@as(usize, 5), o.at(8));
}
