//! The core's Markdown index of the workspace (cadex_markdown_*): notes,
//! headings, the links of an unsaved text, backlinks, where a link goes.
//! Answers come as tab-separated lines; they are split into the caller's
//! arena (apps/macos/features/markdown/MarkdownIndex.swift).

const std = @import("std");
const cadex = @import("cadex");

pub const Heading = struct { level: u32, line: u32, anchor: []const u8, text: []const u8 };

pub const Link = struct {
    /// UTF-16 units in the text that was checked.
    start: u32,
    end: u32,
    /// 0 file, 1 wiki, 2 web.
    kind: u8,
    broken: bool,
    /// Absolute path, the URL of a web link, or empty (outside the workspace).
    target: []const u8,
    /// Line of the heading named, 0 if none.
    line: u32,

    pub fn isWeb(self: Link) bool {
        return self.kind == 2;
    }
};

pub const Place = struct { path: []const u8, line: u32 };

pub const Index = struct {
    handle: ?*cadex.cadex_markdown_index = null,

    /// Indexes the notes under `root` (absolute), reading in the background.
    pub fn open(self: *Index, gpa: std.mem.Allocator, root: []const u8) void {
        self.close();
        const z = gpa.dupeZ(u8, root) catch return;
        defer gpa.free(z);
        var out: ?*cadex.cadex_markdown_index = null;
        if (cadex.cadex_markdown_index_open(z.ptr, &out) == cadex.CADEX_OK) self.handle = out;
    }

    pub fn close(self: *Index) void {
        if (self.handle) |h| cadex.cadex_markdown_index_close(h);
        self.handle = null;
    }

    /// The first read of the workspace is done.
    pub fn ready(self: *const Index) bool {
        const h = self.handle orelse return false;
        return cadex.cadex_markdown_index_ready(h);
    }

    /// Paths of every note, relative to the root.
    pub fn notes(self: *const Index, arena: std.mem.Allocator) []const []const u8 {
        const h = self.handle orelse return &.{};
        var out: [*c]u8 = null;
        var len: usize = 0;
        const rows = split(arena, cadex.cadex_markdown_notes(h, &out, &len), out, len);
        const paths = arena.alloc([]const u8, rows.len) catch return &.{};
        for (rows, paths) |r, *p| p.* = r[0];
        return paths;
    }

    pub fn headings(self: *const Index, arena: std.mem.Allocator, path: []const u8) []const Heading {
        const h = self.handle orelse return &.{};
        const z = arena.dupeZ(u8, path) catch return &.{};
        var out: [*c]u8 = null;
        var len: usize = 0;
        const rows = split(arena, cadex.cadex_markdown_headings(h, z.ptr, &out, &len), out, len);
        var list: std.ArrayList(Heading) = .empty;
        for (rows) |f| {
            if (f.len < 4) continue;
            list.append(arena, .{ .level = number(f[0]), .line = number(f[1]), .anchor = f[2], .text = f[3] }) catch break;
        }
        return list.items;
    }

    /// The links of `text`, the unsaved content of the note at `path`.
    pub fn links(self: *const Index, arena: std.mem.Allocator, path: []const u8, text: []const u8) []const Link {
        const h = self.handle orelse return &.{};
        const z = arena.dupeZ(u8, path) catch return &.{};
        var out: [*c]u8 = null;
        var len: usize = 0;
        const rows = split(arena, cadex.cadex_markdown_links(h, z.ptr, text.ptr, text.len, &out, &len), out, len);
        var list: std.ArrayList(Link) = .empty;
        for (rows) |f| {
            if (f.len < 6) continue;
            list.append(arena, .{
                .start = number(f[0]),
                .end = number(f[1]),
                .kind = @intCast(@min(number(f[2]), 255)),
                .broken = std.mem.eql(u8, f[3], "1"),
                .target = f[4],
                .line = number(f[5]),
            }) catch break;
        }
        return list.items;
    }

    /// Notes linking to `path`, each at the line of its link.
    pub fn backlinks(self: *const Index, arena: std.mem.Allocator, path: []const u8) []const Place {
        const h = self.handle orelse return &.{};
        const z = arena.dupeZ(u8, path) catch return &.{};
        var out: [*c]u8 = null;
        var len: usize = 0;
        const rows = split(arena, cadex.cadex_markdown_backlinks(h, z.ptr, &out, &len), out, len);
        var list: std.ArrayList(Place) = .empty;
        for (rows) |f| {
            if (f.len < 2) continue;
            list.append(arena, .{ .path = f[0], .line = number(f[1]) }) catch break;
        }
        return list.items;
    }

    /// Where `destination`, written in the note at `path`, goes.
    pub fn resolve(self: *const Index, arena: std.mem.Allocator, path: []const u8, destination: []const u8, wiki: bool) ?Place {
        const h = self.handle orelse return null;
        const zp = arena.dupeZ(u8, path) catch return null;
        const zd = arena.dupeZ(u8, destination) catch return null;
        var out: [*c]u8 = null;
        var len: usize = 0;
        const rows = split(arena, cadex.cadex_markdown_resolve(h, zp.ptr, zd.ptr, wiki, &out, &len), out, len);
        if (rows.len == 0 or rows[0].len < 2) return null;
        return .{ .path = rows[0][0], .line = number(rows[0][1]) };
    }
};

fn number(field: []const u8) u32 {
    return std.fmt.parseInt(u32, std.mem.trim(u8, field, " \r"), 10) catch 0;
}

/// The core's answer as lines of fields, copied into `arena`; the core's
/// buffer is freed here.
fn split(arena: std.mem.Allocator, status: cadex.cadex_status, out: [*c]u8, len: usize) []const []const []const u8 {
    if (status != cadex.CADEX_OK or out == null) return &.{};
    defer cadex.cadex_free(out);
    return splitLines(arena, out[0..len]) catch &.{};
}

pub fn splitLines(arena: std.mem.Allocator, bytes: []const u8) ![]const []const []const u8 {
    const copy = try arena.dupe(u8, bytes);
    var rows: std.ArrayList([]const []const u8) = .empty;
    var lines = std.mem.tokenizeScalar(u8, copy, '\n');
    while (lines.next()) |line| {
        var fields: std.ArrayList([]const u8) = .empty;
        var it = std.mem.splitScalar(u8, line, '\t');
        while (it.next()) |f| try fields.append(arena, f);
        try rows.append(arena, fields.items);
    }
    return rows.items;
}

test "answers split into lines of fields, empty fields kept" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const rows = try splitLines(arena.allocator(), "1\t2\t\tx\nnext\n");
    try std.testing.expectEqual(@as(usize, 2), rows.len);
    try std.testing.expectEqual(@as(usize, 4), rows[0].len);
    try std.testing.expectEqualStrings("", rows[0][2]);
    try std.testing.expectEqualStrings("next", rows[1][0]);
}

test {
    @import("win32").refAllDeep(@This());
}
