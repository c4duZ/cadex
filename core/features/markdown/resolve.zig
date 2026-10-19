//! Where a link goes and whether it is broken (docs/spec/markdown.md):
//! paths relative to the file (or to the workspace root with a leading
//! `/`), notes by name for `[[wiki]]` (the nearest one wins), headings by
//! their GitHub anchor.

const std = @import("std");
const fs = @import("../../shared/fs.zig");
const outline = @import("outline.zig");

/// What the resolver needs from the index: the notes and their headings.
pub const Notes = struct {
    context: *anyopaque,
    /// Relative paths of every Markdown file.
    list: *const fn (context: *anyopaque) []const []const u8,
    /// The outline of a note by relative path, if indexed.
    get: *const fn (context: *anyopaque, rel: []const u8) ?*const outline.Outline,
};

pub const Target = struct {
    /// Relative to the root; empty when the link leaves the workspace or
    /// is not a file (web).
    rel: []const u8,
    /// 0-based row of the heading the fragment names, if found.
    row: ?u32,
    broken: bool,
};

/// Resolves `link` found in `from` (relative). The path in the result
/// lives in `buf` or in the index.
pub fn resolve(root: []const u8, from: []const u8, link: outline.Link, notes: Notes, current: ?*const outline.Outline, buf: []u8) Target {
    switch (link.kind) {
        .web => return .{ .rel = "", .row = null, .broken = false },
        .wiki => {
            const rel = nearestNote(from, link.target, notes) orelse return .{ .rel = "", .row = null, .broken = true };
            return withFragment(rel, link.fragment, notes, null);
        },
        .file => {
            if (link.target.len == 0) return withFragment(from, link.fragment, notes, current);
            const rel = normalize(from, link.target, buf) orelse return .{ .rel = "", .row = null, .broken = false };
            if (isMarkdown(rel)) {
                if (notes.get(notes.context, rel) == null) return .{ .rel = rel, .row = null, .broken = true };
                return withFragment(rel, link.fragment, notes, null);
            }
            return .{ .rel = rel, .row = null, .broken = !exists(root, rel) };
        },
    }
}

fn withFragment(rel: []const u8, fragment: []const u8, notes: Notes, current: ?*const outline.Outline) Target {
    const target = current orelse notes.get(notes.context, rel) orelse return .{ .rel = rel, .row = null, .broken = true };
    if (fragment.len == 0) return .{ .rel = rel, .row = null, .broken = false };
    for (target.headings) |h| {
        if (std.ascii.eqlIgnoreCase(h.anchor, fragment) or std.ascii.eqlIgnoreCase(h.text, fragment)) {
            return .{ .rel = rel, .row = h.row, .broken = false };
        }
    }
    return .{ .rel = rel, .row = null, .broken = true };
}

pub fn isMarkdown(path: []const u8) bool {
    return std.ascii.endsWithIgnoreCase(path, ".md") or std.ascii.endsWithIgnoreCase(path, ".markdown");
}

/// `target` from the folder of `from`, `.` and `..` applied; null when it
/// climbs out of the root.
pub fn normalize(from: []const u8, target: []const u8, buf: []u8) ?[]const u8 {
    var parts: [128][]const u8 = undefined;
    var n: usize = 0;
    if (target[0] != '/') {
        var dirs = std.mem.splitScalar(u8, std.fs.path.dirname(from) orelse "", '/');
        while (dirs.next()) |d| if (d.len > 0) {
            if (n == parts.len) return null;
            parts[n] = d;
            n += 1;
        };
    }
    var it = std.mem.splitScalar(u8, target, '/');
    while (it.next()) |p| {
        if (p.len == 0 or std.mem.eql(u8, p, ".")) continue;
        if (std.mem.eql(u8, p, "..")) {
            if (n == 0) return null;
            n -= 1;
            continue;
        }
        if (n == parts.len) return null;
        parts[n] = p;
        n += 1;
    }
    var w: std.Io.Writer = .fixed(buf);
    for (parts[0..n], 0..) |p, i| {
        if (i > 0) w.writeByte('/') catch return null;
        w.writeAll(p) catch return null;
    }
    return w.buffered();
}

/// The note named `name` (file name without .md, any case) closest to
/// `from`: the most folders in common, then the shortest path.
fn nearestNote(from: []const u8, name: []const u8, notes: Notes) ?[]const u8 {
    var best: ?[]const u8 = null;
    var best_shared: usize = 0;
    for (notes.list(notes.context)) |rel| {
        const base = std.fs.path.basename(rel);
        const dot = std.mem.lastIndexOfScalar(u8, base, '.') orelse base.len;
        if (!std.ascii.eqlIgnoreCase(base[0..dot], name)) continue;
        const shared = sharedFolders(from, rel);
        if (best == null or shared > best_shared or (shared == best_shared and rel.len < best.?.len)) {
            best = rel;
            best_shared = shared;
        }
    }
    return best;
}

fn sharedFolders(a: []const u8, b: []const u8) usize {
    var count: usize = 0;
    var ia = std.mem.splitScalar(u8, std.fs.path.dirname(a) orelse "", '/');
    var ib = std.mem.splitScalar(u8, std.fs.path.dirname(b) orelse "", '/');
    while (ia.next()) |x| {
        const y = ib.next() orelse break;
        if (x.len == 0 or !std.mem.eql(u8, x, y)) break;
        count += 1;
    }
    return count;
}

fn exists(root: []const u8, rel: []const u8) bool {
    var buf: fs.Buffer = undefined;
    return fs.info(std.fmt.bufPrint(&buf, "{s}/{s}", .{ root, rel }) catch return false, true) != null;
}

const testing = std.testing;

test "paths are normalized against the file's folder" {
    var buf: [256]u8 = undefined;
    try testing.expectEqualStrings("docs/spec/search.md", normalize("docs/plans/4.md", "../spec/search.md", &buf).?);
    try testing.expectEqualStrings("README.md", normalize("docs/a.md", "/README.md", &buf).?);
    try testing.expectEqualStrings("a/b.md", normalize("x.md", "./a/b.md", &buf).?);
    try testing.expect(normalize("x.md", "../../out.md", &buf) == null);
}
