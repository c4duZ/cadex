//! The editor feature's part of the C API (include/cadex.h).

const std = @import("std");
const status = @import("../../status.zig");
const document = @import("document.zig");
const folds = @import("folds.zig");

const Document = document.Document;
/// Arrays handed to the app come from malloc, freed with cadex_free.
const gpa = std.heap.c_allocator;

fn bytes(ptr: ?*const anyopaque, len: usize) ?[]const u8 {
    if (len == 0) return "";
    const p: [*]const u8 = @ptrCast(ptr orelse return null);
    return p[0..len];
}

pub export fn cadex_editor_open(file_name: ?[*:0]const u8, text: ?*const anyopaque, len: usize, encoding: u8, out: ?*?*Document) callconv(.c) status.Code {
    const result = out orelse return status.invalid_argument;
    result.* = null;
    const name = std.mem.span(file_name orelse return status.invalid_argument);
    const t = bytes(text, len) orelse return status.invalid_argument;
    const enc = std.enums.fromInt(document.Encoding, encoding) orelse return status.invalid_argument;
    result.* = Document.open(gpa, name, t, enc) catch |err| return status.fromError(err);
    return status.ok;
}

pub export fn cadex_editor_close(doc: ?*Document) callconv(.c) void {
    if (doc) |d| d.close();
}

/// The language's name ("Zig"), or NULL for plain text.
pub export fn cadex_editor_language(doc: ?*Document) callconv(.c) ?[*:0]const u8 {
    const d = doc orelse return null;
    return if (d.language) |l| l.name.ptr else null;
}

pub export fn cadex_editor_edit(doc: ?*Document, start: u32, old_end: u32, text: ?*const anyopaque, len: usize, changed_start: ?*u32, changed_end: ?*u32) callconv(.c) status.Code {
    const d = doc orelse return status.invalid_argument;
    const t = bytes(text, len) orelse return status.invalid_argument;
    const changed = d.edit(start, old_end, t) catch |err| return status.fromError(err);
    if (changed_start) |p| p.* = changed.start;
    if (changed_end) |p| p.* = changed.end;
    return status.ok;
}

pub export fn cadex_editor_highlights(doc: ?*Document, start: u32, end: u32, out: ?*?[*]document.Span, count: ?*usize) callconv(.c) status.Code {
    const result = out orelse return status.invalid_argument;
    const n = count orelse return status.invalid_argument;
    result.* = null;
    n.* = 0;
    const d = doc orelse return status.invalid_argument;
    const spans = d.highlights(gpa, start, end) catch |err| return status.fromError(err);
    if (spans.len == 0) return status.ok;
    result.* = spans.ptr;
    n.* = spans.len;
    return status.ok;
}

pub export fn cadex_editor_folds(doc: ?*Document, out: ?*?[*]folds.Region, count: ?*usize) callconv(.c) status.Code {
    const result = out orelse return status.invalid_argument;
    const n = count orelse return status.invalid_argument;
    result.* = null;
    n.* = 0;
    const d = doc orelse return status.invalid_argument;
    const regions = d.foldRegions(gpa) catch |err| return status.fromError(err);
    if (regions.len == 0) return status.ok;
    result.* = regions.ptr;
    n.* = regions.len;
    return status.ok;
}

test "opens, edits, highlights and folds through the C API" {
    const source = "fn a() void {\n    return;\n}\n";
    var doc: ?*Document = null;
    try std.testing.expectEqual(status.ok, cadex_editor_open("a.zig", source.ptr, source.len, 0, &doc));
    defer cadex_editor_close(doc);
    try std.testing.expectEqualStrings("Zig", std.mem.span(cadex_editor_language(doc).?));
    var spans: ?[*]document.Span = null;
    var n: usize = 0;
    try std.testing.expectEqual(status.ok, cadex_editor_highlights(doc, 0, source.len, &spans, &n));
    defer std.c.free(spans);
    try std.testing.expect(n > 0);
    var regions: ?[*]folds.Region = null;
    try std.testing.expectEqual(status.ok, cadex_editor_folds(doc, &regions, &n));
    defer std.c.free(regions);
    try std.testing.expectEqual(@as(usize, 1), n);
    var lo: u32 = 0;
    var hi: u32 = 0;
    try std.testing.expectEqual(status.ok, cadex_editor_edit(doc, 0, 0, "// x\n", 5, &lo, &hi));
    try std.testing.expectEqual(@as(u32, 0), lo);
}
