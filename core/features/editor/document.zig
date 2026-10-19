//! One open file for the editor: its text, its syntax tree, and the
//! incremental reparse after each edit (docs/spec/editor.md). Offsets are
//! in units of the encoding: bytes for UTF-8, code units for UTF-16, the
//! encoding of the app's text view, so it needs no conversion.

const std = @import("std");
const ts = @import("ts.zig").c;
const languages = @import("languages.zig");
const query = @import("query.zig");
const highlight = @import("highlight.zig");
const folds = @import("folds.zig");

pub const Encoding = enum(u8) { utf8 = 0, utf16 = 1 };

/// Above this many bytes a file shows without colors or folds.
pub const max_highlight_bytes = 1024 * 1024;

pub const Span = extern struct { start: u32, end: u32, kind: highlight.Kind };

pub const Document = struct {
    gpa: std.mem.Allocator,
    encoding: Encoding,
    /// The text in its encoding (UTF-16 little-endian when utf16).
    text: std.ArrayList(u8) = .empty,
    language: ?*const languages.Language,
    parser: ?*ts.TSParser = null,
    tree: ?*ts.TSTree = null,
    /// Markdown only: the inline grammar over the paragraphs' text.
    inline_parser: ?*ts.TSParser = null,
    inline_tree: ?*ts.TSTree = null,

    /// Parses `text` with the language of `file_name` (none above the size
    /// limit or for unknown names: plain text).
    pub fn open(gpa: std.mem.Allocator, file_name: []const u8, text: []const u8, encoding: Encoding) !*Document {
        const self = try gpa.create(Document);
        errdefer gpa.destroy(self);
        // The limit is about the file (UTF-8 bytes); UTF-16 doubles ASCII.
        const size = if (encoding == .utf16) text.len / 2 else text.len;
        const language = if (size > max_highlight_bytes) null else languages.forFileName(file_name);
        self.* = .{ .gpa = gpa, .encoding = encoding, .language = language };
        errdefer self.text.deinit(gpa);
        try self.text.appendSlice(gpa, text);
        if (language) |lang| {
            self.parser = ts.ts_parser_new();
            _ = ts.ts_parser_set_language(self.parser, lang.grammar());
            if (lang.id == .markdown) {
                self.inline_parser = ts.ts_parser_new();
                _ = ts.ts_parser_set_language(self.inline_parser, languages.get(.markdown_inline).grammar());
            }
            self.reparse(null);
        }
        return self;
    }

    pub fn close(self: *Document) void {
        if (self.tree) |t| ts.ts_tree_delete(t);
        if (self.inline_tree) |t| ts.ts_tree_delete(t);
        if (self.parser) |p| ts.ts_parser_delete(p);
        if (self.inline_parser) |p| ts.ts_parser_delete(p);
        self.text.deinit(self.gpa);
        self.gpa.destroy(self);
    }

    fn unit(self: *const Document) u32 {
        return if (self.encoding == .utf16) 2 else 1;
    }

    fn tsEncoding(self: *const Document) ts.TSInputEncoding {
        return if (self.encoding == .utf16) ts.TSInputEncodingUTF16LE else ts.TSInputEncodingUTF8;
    }

    fn reparse(self: *Document, old: ?*ts.TSTree) void {
        const parser = self.parser orelse return;
        const items = self.text.items;
        self.tree = ts.ts_parser_parse_string_encoding(parser, old, items.ptr, @intCast(items.len), self.tsEncoding());
        if (self.inline_parser != null) self.reparseInline();
    }

    /// The inline grammar runs over the block tree's `inline` nodes only.
    fn reparseInline(self: *Document) void {
        if (self.inline_tree) |t| ts.ts_tree_delete(t);
        self.inline_tree = null;
        var ranges: std.ArrayList(ts.TSRange) = .empty;
        defer ranges.deinit(self.gpa);
        collectInline(self.gpa, ts.ts_tree_root_node(self.tree), &ranges) catch return;
        if (ranges.items.len == 0) return;
        const p = self.inline_parser.?;
        if (!ts.ts_parser_set_included_ranges(p, ranges.items.ptr, @intCast(ranges.items.len))) return;
        const items = self.text.items;
        self.inline_tree = ts.ts_parser_parse_string_encoding(p, null, items.ptr, @intCast(items.len), self.tsEncoding());
    }

    /// Replaces units [start, old_end) with `new_text` and reparses only
    /// what changed. Returns the range (in units, new text) whose colors
    /// may differ now.
    pub fn edit(self: *Document, start: u32, old_end: u32, new_text: []const u8) !struct { start: u32, end: u32 } {
        const u = self.unit();
        const start_byte = start * u;
        const old_end_byte = old_end * u;
        if (old_end_byte > self.text.items.len or start_byte > old_end_byte) return error.InvalidRange;
        const start_point = self.pointAt(start_byte);
        const old_end_point = self.pointAt(old_end_byte);
        try self.text.replaceRange(self.gpa, start_byte, old_end_byte - start_byte, new_text);
        const new_end_byte: u32 = start_byte + @as(u32, @intCast(new_text.len));
        const new_end = new_end_byte / u;
        const old_tree = self.tree orelse return .{ .start = start, .end = new_end };
        const input: ts.TSInputEdit = .{
            .start_byte = start_byte,
            .old_end_byte = old_end_byte,
            .new_end_byte = new_end_byte,
            .start_point = start_point,
            .old_end_point = old_end_point,
            .new_end_point = self.pointAt(new_end_byte),
        };
        ts.ts_tree_edit(old_tree, &input);
        self.reparse(old_tree);
        defer ts.ts_tree_delete(old_tree);
        var lo = start_byte;
        var hi = new_end_byte;
        var count: u32 = 0;
        const changed = ts.ts_tree_get_changed_ranges(old_tree, self.tree, &count);
        // NULL when nothing changed in the tree's shape.
        if (count > 0) {
            defer std.c.free(changed);
            for (changed[0..count]) |r| {
                lo = @min(lo, r.start_byte);
                hi = @max(hi, r.end_byte);
            }
        }
        return .{ .start = lo / u, .end = hi / u };
    }

    /// Row and column (in bytes) of a byte offset, as tree-sitter counts.
    fn pointAt(self: *const Document, byte: u32) ts.TSPoint {
        const items = self.text.items[0..byte];
        var row: u32 = 0;
        var line_start: usize = 0;
        if (self.encoding == .utf8) {
            for (items, 0..) |ch, i| if (ch == '\n') {
                row += 1;
                line_start = i + 1;
            };
        } else {
            var i: usize = 0;
            while (i + 1 < items.len) : (i += 2) if (items[i] == '\n' and items[i + 1] == 0) {
                row += 1;
                line_start = i + 2;
            };
        }
        return .{ .row = row, .column = @intCast(byte - line_start) };
    }

    /// Non-overlapping colored spans inside [start, end), in units. The
    /// innermost capture wins; for the same node, the later pattern.
    pub fn highlights(self: *Document, gpa: std.mem.Allocator, start: u32, end: u32) ![]Span {
        const language = self.language orelse return &.{};
        const u = self.unit();
        const lo = @min(start * u, @as(u32, @intCast(self.text.items.len)));
        const hi = @min(end * u, @as(u32, @intCast(self.text.items.len)));
        if (hi <= lo) return &.{};
        const paint = try gpa.alloc(highlight.Kind, (hi - lo) / u);
        defer gpa.free(paint);
        @memset(paint, .none);
        var captures: std.ArrayList(Capture) = .empty;
        defer captures.deinit(gpa);
        if (self.tree) |tree| try self.collect(gpa, tree, language, lo, hi, &captures);
        if (self.inline_tree) |tree| try self.collect(gpa, tree, languages.get(.markdown_inline), lo, hi, &captures);
        std.mem.sort(Capture, captures.items, {}, Capture.paintOrder);
        for (captures.items) |c| {
            const a = (@max(c.start, lo) - lo) / u;
            const b = (@min(c.end, hi) - lo) / u;
            if (b > a) @memset(paint[a..b], c.kind);
        }
        return runs(gpa, paint, lo / u);
    }

    fn collect(self: *Document, gpa: std.mem.Allocator, tree: *ts.TSTree, language: *const languages.Language, lo: u32, hi: u32, out: *std.ArrayList(Capture)) !void {
        const q = query.forLanguage(language) orelse return;
        const cursor = ts.ts_query_cursor_new();
        defer ts.ts_query_cursor_delete(cursor);
        _ = ts.ts_query_cursor_set_byte_range(cursor, lo, hi);
        ts.ts_query_cursor_exec(cursor, q.query, ts.ts_tree_root_node(tree));
        var match: ts.TSQueryMatch = undefined;
        const text: query.Text = .{ .context = self, .get = textOf };
        while (ts.ts_query_cursor_next_match(cursor, &match)) {
            if (!q.accepts(&match, text)) continue;
            for (match.captures[0..match.capture_count]) |c| {
                const kind = q.kinds[c.index];
                // @variable, @spell and friends color nothing; they must not
                // erase the color another pattern gave the same node.
                if (kind == .none) continue;
                try out.append(gpa, .{
                    .start = ts.ts_node_start_byte(c.node),
                    .end = ts.ts_node_end_byte(c.node),
                    .kind = kind,
                    .pattern = match.pattern_index,
                });
            }
        }
    }

    /// The text of [start, end) bytes as UTF-8, for predicates.
    fn textOf(context: *anyopaque, start: u32, end: u32, buf: []u8) []const u8 {
        const self: *Document = @ptrCast(@alignCast(context));
        const bytes = self.text.items[start..@min(end, self.text.items.len)];
        if (self.encoding == .utf8) return bytes[0..@min(bytes.len, buf.len)];
        var units: [256]u16 = undefined;
        const n = @min(bytes.len / 2, units.len);
        for (0..n) |i| units[i] = std.mem.readInt(u16, bytes[i * 2 ..][0..2], .little);
        const len = std.unicode.utf16LeToUtf8(buf, units[0..n]) catch return "";
        return buf[0..len];
    }

    /// Fold regions of the whole document (empty without a language).
    pub fn foldRegions(self: *Document, gpa: std.mem.Allocator) ![]folds.Region {
        const tree = self.tree orelse return &.{};
        const markdown = if (self.language) |l| l.id == .markdown else false;
        return folds.regions(gpa, ts.ts_tree_root_node(tree), markdown);
    }
};

const Capture = struct {
    start: u32,
    end: u32,
    kind: highlight.Kind,
    pattern: u32,

    /// Outer nodes first, so inner ones paint over them; for the same node,
    /// earlier patterns first, so the later pattern stays.
    fn paintOrder(_: void, a: Capture, b: Capture) bool {
        const la = a.end - a.start;
        const lb = b.end - b.start;
        if (la != lb) return la > lb;
        if (a.start != b.start) return a.start < b.start;
        return a.pattern < b.pattern;
    }
};

/// Runs of the same kind in `paint`, skipping uncolored ones.
fn runs(gpa: std.mem.Allocator, paint: []const highlight.Kind, base: u32) ![]Span {
    var list: std.ArrayList(Span) = .empty;
    errdefer list.deinit(gpa);
    var i: usize = 0;
    while (i < paint.len) {
        const kind = paint[i];
        var j = i + 1;
        while (j < paint.len and paint[j] == kind) j += 1;
        if (kind != .none) try list.append(gpa, .{ .start = base + @as(u32, @intCast(i)), .end = base + @as(u32, @intCast(j)), .kind = kind });
        i = j;
    }
    return list.toOwnedSlice(gpa);
}

fn collectInline(gpa: std.mem.Allocator, node: ts.TSNode, out: *std.ArrayList(ts.TSRange)) !void {
    if (std.mem.eql(u8, std.mem.span(ts.ts_node_type(node)), "inline")) {
        try out.append(gpa, .{
            .start_point = ts.ts_node_start_point(node),
            .end_point = ts.ts_node_end_point(node),
            .start_byte = ts.ts_node_start_byte(node),
            .end_byte = ts.ts_node_end_byte(node),
        });
        return;
    }
    const n = ts.ts_node_child_count(node);
    for (0..n) |i| try collectInline(gpa, ts.ts_node_child(node, @intCast(i)), out);
}

test "markdown folds sections and code blocks only" {
    const source = "# A\n\n- one\n- two\n\n```zig\nconst x = 1;\n```\n\n## B\n\ntext\n";
    const doc = try Document.open(std.testing.allocator, "n.md", source, .utf8);
    defer doc.close();
    const regions = try doc.foldRegions(std.testing.allocator);
    defer std.testing.allocator.free(regions);
    try std.testing.expectEqual(@as(usize, 3), regions.len);
    try std.testing.expectEqual(@as(u32, 0), regions[0].start_row);
    try std.testing.expectEqual(@as(u32, 5), regions[1].start_row);
    try std.testing.expectEqual(@as(u32, 9), regions[2].start_row);
}

test {
    _ = @import("document_test.zig");
}
