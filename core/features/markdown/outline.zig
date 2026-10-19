//! The headings and links of one Markdown text, with where they are
//! (docs/spec/markdown.md). Read with the editor feature's tree-sitter
//! (block and inline grammars, through its entry point); `[[wiki]]` links,
//! which the grammar does not know, by a scan outside code.

const std = @import("std");
const editor = @import("../editor/editor.zig");
const anchor = @import("anchor.zig");
const ts = editor.ts;

pub const Heading = struct {
    level: u8,
    text: []const u8,
    anchor: []const u8,
    /// 0-based.
    row: u32,
};

pub const LinkKind = enum(u8) { file = 0, wiki = 1, web = 2 };

pub const Link = struct {
    kind: LinkKind,
    /// The path (file links, percent-decoded) or note name (wiki); empty
    /// for a link to a heading of the same file.
    target: []const u8,
    /// After `#`, as written; empty when none.
    fragment: []const u8,
    row: u32,
    /// Byte range of the whole link in the text.
    start: u32,
    end: u32,
};

pub const Outline = struct {
    arena: std.heap.ArenaAllocator,
    headings: []Heading,
    links: []Link,

    pub fn deinit(self: *Outline) void {
        self.arena.deinit();
    }

    pub fn hasAnchor(self: *const Outline, wanted: []const u8) bool {
        for (self.headings) |h| {
            if (std.ascii.eqlIgnoreCase(h.anchor, wanted)) return true;
        }
        return false;
    }
};

pub fn parse(gpa: std.mem.Allocator, text: []const u8) !Outline {
    var self: Outline = .{ .arena = .init(gpa), .headings = &.{}, .links = &.{} };
    errdefer self.arena.deinit();
    const a = self.arena.allocator();
    const doc = try editor.Document.open(gpa, "outline.md", text, .utf8);
    defer doc.close();
    var walk: Walk = .{ .a = a, .text = text };
    if (doc.tree) |tree| try walk.blocks(ts.ts_tree_root_node(tree));
    if (doc.inline_tree) |tree| try walk.inlines(ts.ts_tree_root_node(tree));
    try walk.wikiLinks();
    std.mem.sort(Link, walk.links.items, {}, struct {
        fn lessThan(_: void, x: Link, y: Link) bool {
            return x.start < y.start;
        }
    }.lessThan);
    var counter: anchor.Counter = .{};
    defer counter.deinit(gpa);
    for (walk.headings.items) |*h| {
        const id = try counter.next(gpa, h.text);
        defer gpa.free(id);
        h.anchor = try a.dupe(u8, id);
    }
    self.headings = walk.headings.items;
    self.links = walk.links.items;
    return self;
}

const Walk = struct {
    a: std.mem.Allocator,
    text: []const u8,
    headings: std.ArrayList(Heading) = .empty,
    links: std.ArrayList(Link) = .empty,
    /// Byte ranges of code (blocks and spans): no wiki links inside.
    code: std.ArrayList([2]u32) = .empty,
    /// [label] -> destination, for reference links.
    definitions: std.StringHashMapUnmanaged([]const u8) = .empty,
    pending_refs: std.ArrayList(struct { label: []const u8, start: u32, end: u32, row: u32 }) = .empty,

    fn nodeText(self: *Walk, node: ts.TSNode) []const u8 {
        return self.text[ts.ts_node_start_byte(node)..ts.ts_node_end_byte(node)];
    }

    fn blocks(self: *Walk, node: ts.TSNode) !void {
        const kind = std.mem.span(ts.ts_node_type(node));
        if (std.mem.eql(u8, kind, "atx_heading")) return self.atxHeading(node);
        if (std.mem.eql(u8, kind, "setext_heading")) return self.setextHeading(node);
        if (std.mem.eql(u8, kind, "fenced_code_block") or std.mem.eql(u8, kind, "indented_code_block")) {
            return self.code.append(self.a, .{ ts.ts_node_start_byte(node), ts.ts_node_end_byte(node) });
        }
        if (std.mem.eql(u8, kind, "link_reference_definition")) return self.definition(node);
        const n = ts.ts_node_child_count(node);
        for (0..n) |i| try self.blocks(ts.ts_node_child(node, @intCast(i)));
    }

    fn atxHeading(self: *Walk, node: ts.TSNode) !void {
        var level: u8 = 1;
        var content: []const u8 = "";
        const n = ts.ts_node_child_count(node);
        for (0..n) |i| {
            const child = ts.ts_node_child(node, @intCast(i));
            const kind = std.mem.span(ts.ts_node_type(child));
            if (std.mem.startsWith(u8, kind, "atx_h") and std.mem.endsWith(u8, kind, "_marker")) level = kind[5] - '0';
            if (std.mem.eql(u8, kind, "inline")) content = self.nodeText(child);
        }
        const trimmed = std.mem.trimEnd(u8, std.mem.trim(u8, content, " \t"), "# \t");
        try self.headings.append(self.a, .{ .level = level, .text = try plainHeading(self.a, trimmed), .anchor = "", .row = ts.ts_node_start_point(node).row });
    }

    fn setextHeading(self: *Walk, node: ts.TSNode) !void {
        var level: u8 = 1;
        var content: []const u8 = "";
        const n = ts.ts_node_child_count(node);
        for (0..n) |i| {
            const child = ts.ts_node_child(node, @intCast(i));
            const kind = std.mem.span(ts.ts_node_type(child));
            if (std.mem.eql(u8, kind, "setext_h2_underline")) level = 2;
            if (std.mem.eql(u8, kind, "paragraph")) content = self.nodeText(child);
        }
        try self.headings.append(self.a, .{ .level = level, .text = try plainHeading(self.a, std.mem.trim(u8, content, " \t\n")), .anchor = "", .row = ts.ts_node_start_point(node).row });
    }

    fn definition(self: *Walk, node: ts.TSNode) !void {
        var label: []const u8 = "";
        var dest: []const u8 = "";
        const n = ts.ts_node_child_count(node);
        for (0..n) |i| {
            const child = ts.ts_node_child(node, @intCast(i));
            const kind = std.mem.span(ts.ts_node_type(child));
            if (std.mem.eql(u8, kind, "link_label")) label = std.mem.trim(u8, self.nodeText(child), "[]");
            if (std.mem.eql(u8, kind, "link_destination")) dest = self.nodeText(child);
        }
        if (label.len == 0) return;
        const key = try std.ascii.allocLowerString(self.a, label);
        try self.definitions.put(self.a, key, dest);
    }

    fn inlines(self: *Walk, node: ts.TSNode) !void {
        const kind = std.mem.span(ts.ts_node_type(node));
        if (std.mem.eql(u8, kind, "code_span")) {
            return self.code.append(self.a, .{ ts.ts_node_start_byte(node), ts.ts_node_end_byte(node) });
        }
        if (std.mem.eql(u8, kind, "image")) return;
        if (std.mem.eql(u8, kind, "inline_link")) {
            var dest: []const u8 = "";
            const n = ts.ts_node_child_count(node);
            for (0..n) |i| {
                const child = ts.ts_node_child(node, @intCast(i));
                if (std.mem.eql(u8, std.mem.span(ts.ts_node_type(child)), "link_destination")) dest = self.nodeText(child);
            }
            return self.addDestination(dest, node);
        }
        if (std.mem.eql(u8, kind, "full_reference_link") or std.mem.eql(u8, kind, "collapsed_reference_link") or std.mem.eql(u8, kind, "shortcut_link")) {
            var label: []const u8 = "";
            const n = ts.ts_node_child_count(node);
            for (0..n) |i| {
                const child = ts.ts_node_child(node, @intCast(i));
                const ck = std.mem.span(ts.ts_node_type(child));
                if (std.mem.eql(u8, ck, "link_label") or (label.len == 0 and std.mem.eql(u8, ck, "link_text"))) label = std.mem.trim(u8, self.nodeText(child), "[]");
            }
            // A shortcut link inside [[...]] is a wiki link: the scan takes it.
            const s = ts.ts_node_start_byte(node);
            if (s > 0 and self.text[s - 1] == '[') return;
            try self.pending_refs.append(self.a, .{ .label = label, .start = s, .end = ts.ts_node_end_byte(node), .row = ts.ts_node_start_point(node).row });
            return;
        }
        const n = ts.ts_node_child_count(node);
        for (0..n) |i| try self.inlines(ts.ts_node_child(node, @intCast(i)));
    }

    fn addDestination(self: *Walk, raw: []const u8, node: ts.TSNode) !void {
        try self.add(raw, ts.ts_node_start_byte(node), ts.ts_node_end_byte(node), ts.ts_node_start_point(node).row);
    }

    fn add(self: *Walk, raw: []const u8, start: u32, end: u32, row: u32) !void {
        const dest = std.mem.trim(u8, std.mem.trim(u8, raw, " "), "<>");
        if (dest.len == 0) return;
        if (std.mem.indexOf(u8, dest, "://") != null or std.mem.startsWith(u8, dest, "mailto:")) {
            return self.links.append(self.a, .{ .kind = .web, .target = try self.a.dupe(u8, dest), .fragment = "", .row = row, .start = start, .end = end });
        }
        const hash = std.mem.indexOfScalar(u8, dest, '#');
        const path = if (hash) |h| dest[0..h] else dest;
        const fragment = if (hash) |h| dest[h + 1 ..] else "";
        try self.links.append(self.a, .{ .kind = .file, .target = try percentDecode(self.a, path), .fragment = try self.a.dupe(u8, fragment), .row = row, .start = start, .end = end });
    }

    /// `[[note]]`, `[[note#Heading]]`, `[[note|shown text]]`, on one line
    /// and outside code. Reference links resolve here too, now that every
    /// definition is known.
    fn wikiLinks(self: *Walk) !void {
        for (self.pending_refs.items) |r| {
            const key = try std.ascii.allocLowerString(self.a, r.label);
            if (self.definitions.get(key)) |dest| try self.add(dest, r.start, r.end, r.row);
        }
        var i: usize = 0;
        var row: u32 = 0;
        var counted: usize = 0;
        while (std.mem.indexOfPos(u8, self.text, i, "[[")) |open| {
            const close = std.mem.indexOfPos(u8, self.text, open + 2, "]]") orelse break;
            i = close + 2;
            const inside = self.text[open + 2 .. close];
            if (inside.len == 0 or std.mem.indexOfAny(u8, inside, "\n[") != null or self.inCode(@intCast(open))) continue;
            row += @intCast(std.mem.count(u8, self.text[counted..open], "\n"));
            counted = open;
            const name = if (std.mem.indexOfScalar(u8, inside, '|')) |bar| inside[0..bar] else inside;
            const hash = std.mem.indexOfScalar(u8, name, '#');
            try self.links.append(self.a, .{
                .kind = .wiki,
                .target = try self.a.dupe(u8, std.mem.trim(u8, if (hash) |h| name[0..h] else name, " ")),
                .fragment = try self.a.dupe(u8, if (hash) |h| name[h + 1 ..] else ""),
                .row = row,
                .start = @intCast(open),
                .end = @intCast(close + 2),
            });
        }
    }

    fn inCode(self: *Walk, at: u32) bool {
        for (self.code.items) |r| {
            if (at >= r[0] and at < r[1]) return true;
        }
        return false;
    }
};

/// The heading's text without inline markup characters.
fn plainHeading(a: std.mem.Allocator, text: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    for (text) |ch| {
        if (ch == '`' or ch == '*' or ch == '\t') continue;
        try out.append(a, ch);
    }
    return out.items;
}

/// A copy in `a` (the outline outlives the text it was read from).
fn percentDecode(a: std.mem.Allocator, s: []const u8) ![]const u8 {
    if (std.mem.indexOfScalar(u8, s, '%') == null) return a.dupe(u8, s);
    var out: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        if (s[i] == '%' and i + 2 < s.len) {
            if (std.fmt.parseInt(u8, s[i + 1 .. i + 3], 16)) |byte| {
                try out.append(a, byte);
                i += 2;
                continue;
            } else |_| {}
        }
        try out.append(a, s[i]);
    }
    return out.items;
}

const testing = std.testing;

test "headings, file links, references, wiki links and code left out" {
    var outline = try parse(testing.allocator,
        \\# Plano
        \\
        \\Veja [a spec](docs/spec/search.md#critérios-de-aceite), [ref][r] e [[Ideias|ideias]].
        \\
        \\Decisão Final
        \\-------------
        \\
        \\`[[não é link]]` e [web](https://example.com) e [aqui](#plano) e [espaço](minha%20nota.md)
        \\
        \\```
        \\[[também não]]
        \\```
        \\
        \\[r]: ../README.md
        \\
    );
    defer outline.deinit();
    try testing.expectEqual(@as(usize, 2), outline.headings.len);
    try testing.expectEqualStrings("plano", outline.headings[0].anchor);
    try testing.expectEqualStrings("decisão-final", outline.headings[1].anchor);
    try testing.expectEqual(@as(u8, 2), outline.headings[1].level);
    try testing.expectEqual(@as(u32, 4), outline.headings[1].row);

    const links = outline.links;
    try testing.expectEqual(@as(usize, 6), links.len);
    try testing.expectEqualStrings("docs/spec/search.md", links[0].target);
    try testing.expectEqualStrings("critérios-de-aceite", links[0].fragment);
    try testing.expectEqualStrings("../README.md", links[1].target);
    try testing.expectEqual(LinkKind.wiki, links[2].kind);
    try testing.expectEqualStrings("Ideias", links[2].target);
    try testing.expectEqual(LinkKind.web, links[3].kind);
    try testing.expectEqualStrings("", links[4].target);
    try testing.expectEqualStrings("plano", links[4].fragment);
    try testing.expectEqualStrings("minha nota.md", links[5].target);
    try testing.expectEqual(@as(u32, 7), links[5].row);
}
