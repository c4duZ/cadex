//! Where the editor offers folding (docs/spec/editor.md): nodes of several
//! lines whose type is a block, a body, a function, a class, an object...
//! One region per starting line, the outermost. The grammars do not ship
//! fold queries for every language, so the node type decides.

const std = @import("std");
const ts = @import("ts.zig").c;

/// Rows are 0-based, as tree-sitter counts; end_row is the last row inside.
pub const Region = extern struct { start_row: u32, end_row: u32 };

/// Words in a node type that make it foldable, across the grammars of the
/// MVP: statement_block, function_definition, class_body, object, element...
const foldable_words = [_][]const u8{
    "block",  "body",   "class",     "function", "method",  "object",  "array", "struct",
    "enum",   "interface", "impl",   "declaration_list", "compound_statement", "table",
    "element", "section", "fenced_code", "dictionary", "list", "mapping", "sequence",
};

/// In Markdown only sections (a heading and what follows it) and code
/// blocks fold: lists and tables end on the blank line after them, so
/// every item looked foldable (2026-10-19).
const markdown_foldable = [_][]const u8{ "section", "fenced_code_block" };

pub fn regions(gpa: std.mem.Allocator, root: ts.TSNode, markdown: bool) ![]Region {
    var by_row: std.AutoArrayHashMapUnmanaged(u32, u32) = .empty;
    defer by_row.deinit(gpa);
    const cursor_root = root;
    var cursor = ts.ts_tree_cursor_new(cursor_root);
    defer ts.ts_tree_cursor_delete(&cursor);
    // Depth-first walk; parents come before children, so the first region
    // on a row is the outermost.
    var depth: usize = 0;
    while (true) {
        const node = ts.ts_tree_cursor_current_node(&cursor);
        if (depth > 0 and ts.ts_node_is_named(node)) try consider(gpa, node, &by_row, markdown);
        if (ts.ts_tree_cursor_goto_first_child(&cursor)) {
            depth += 1;
            continue;
        }
        while (!ts.ts_tree_cursor_goto_next_sibling(&cursor)) {
            if (!ts.ts_tree_cursor_goto_parent(&cursor)) return collect(gpa, &by_row);
            depth -= 1;
        }
    }
}

fn consider(gpa: std.mem.Allocator, node: ts.TSNode, by_row: *std.AutoArrayHashMapUnmanaged(u32, u32), markdown: bool) !void {
    const start = ts.ts_node_start_point(node);
    const end = ts.ts_node_end_point(node);
    // A node ending at column 0 really ends on the line before.
    const last = if (end.column == 0 and end.row > 0) end.row - 1 else end.row;
    if (last <= start.row) return;
    if (by_row.contains(start.row)) return;
    if (!isFoldable(std.mem.span(ts.ts_node_type(node)), if (markdown) &markdown_foldable else &foldable_words)) return;
    try by_row.put(gpa, start.row, last);
}

fn isFoldable(node_type: []const u8, words: []const []const u8) bool {
    for (words) |word| {
        if (std.mem.indexOf(u8, node_type, word) != null) return true;
    }
    return false;
}

fn collect(gpa: std.mem.Allocator, by_row: *std.AutoArrayHashMapUnmanaged(u32, u32)) ![]Region {
    const list = try gpa.alloc(Region, by_row.count());
    for (by_row.keys(), by_row.values(), list) |start, end, *r| r.* = .{ .start_row = start, .end_row = end };
    std.mem.sort(Region, list, {}, struct {
        fn lessThan(_: void, a: Region, b: Region) bool {
            return a.start_row < b.start_row;
        }
    }.lessThan);
    return list;
}
