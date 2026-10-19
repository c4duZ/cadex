//! What the app asks the Markdown index (docs/spec/markdown.md): the links
//! of the text being edited, resolved and checked; who points at a note.

const std = @import("std");
const fs = @import("../../shared/fs.zig");
const Index = @import("index.zig").Index;
const outline = @import("outline.zig");
const resolve = @import("resolve.zig");

pub const CheckedLink = struct {
    start: u32,
    end: u32,
    kind: outline.LinkKind,
    broken: bool,
    /// Relative to the root; empty for web links and paths outside.
    rel: []const u8,
    /// 0-based row of the heading the link names, if any.
    row: ?u32,
};

/// The links of `text` (the unsaved text of note `from`, relative),
/// resolved against the index. Strings live in `a`.
pub fn checkLinks(a: std.mem.Allocator, index: *Index, from: []const u8, text: []const u8) ![]CheckedLink {
    var current = try outline.parse(a, text);
    defer current.deinit();
    index.lock();
    defer index.unlock();
    const notes = index.notesView();
    const out = try a.alloc(CheckedLink, current.links.len);
    for (current.links, out) |link, *o| {
        var buf: fs.Buffer = undefined;
        const t = resolve.resolve(index.root, from, link, notes, &current, &buf);
        o.* = .{ .start = link.start, .end = link.end, .kind = link.kind, .broken = t.broken, .rel = try a.dupe(u8, t.rel), .row = t.row };
    }
    return out;
}

pub const Backlink = struct { from: []const u8, row: u32 };

/// The notes with a link to `target` (relative), each link once.
pub fn backlinks(a: std.mem.Allocator, index: *Index, target: []const u8) ![]Backlink {
    index.lock();
    defer index.unlock();
    const notes = index.notesView();
    var list: std.ArrayList(Backlink) = .empty;
    for (index.notes.keys(), index.notes.values()) |from, note| {
        for (note.links) |link| {
            if (link.kind == .web) continue;
            var buf: fs.Buffer = undefined;
            const t = resolve.resolve(index.root, from, link, notes, note, &buf);
            if (std.mem.eql(u8, t.rel, target) and !std.mem.eql(u8, from, target)) {
                try list.append(a, .{ .from = try a.dupe(u8, from), .row = link.row });
            }
        }
    }
    std.mem.sort(Backlink, list.items, {}, struct {
        fn lessThan(_: void, x: Backlink, y: Backlink) bool {
            return switch (std.mem.order(u8, x.from, y.from)) {
                .lt => true,
                .gt => false,
                .eq => x.row < y.row,
            };
        }
    }.lessThan);
    return list.items;
}

/// Where a link written as `destination` in `from` goes: for the rendered
/// view's clicks (`cadex-wiki:Name`, `../a.md#x`).
pub fn resolveDestination(a: std.mem.Allocator, index: *Index, from: []const u8, destination: []const u8, wiki: bool) !CheckedLink {
    const text = if (wiki)
        try std.fmt.allocPrint(a, "[[{s}]]", .{destination})
    else
        try std.fmt.allocPrint(a, "[x]({s})", .{destination});
    const links = try checkLinks(a, index, from, text);
    if (links.len == 0) return error.NotFound;
    return links[0];
}
