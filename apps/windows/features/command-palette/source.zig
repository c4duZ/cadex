//! What the palette lists: commands, files (Ctrl+P), text in files, tabs and
//! spaces. Each list is a Source; the palette asks it for the rows of a
//! query and tells it which row was chosen and how.

const std = @import("std");
const gfx = @import("gfx");
const cadex = @import("cadex");

pub const Item = struct {
    /// What choose() gets back: a command id, a path, a tab index.
    id: []const u8,
    title: []const u8,
    /// On the right of the title, dimmed (a folder, a line of text).
    detail: []const u8 = "",
    icon: u21,
    icon_color: ?gfx.Color = null,
    /// A file's name: its Material drawing replaces `icon` when the pack
    /// has one (the file searches, as on the Mac).
    file_name: []const u8 = "",
    /// "Ctrl+Shift+D", drawn as keys.
    shortcut: []const u8 = "",
    /// A title drawn above this row (the start of a section).
    section: []const u8 = "",
    /// Byte offsets in `title` of the letters the query matched, in bold.
    bold: []const u32 = &.{},
};

/// How a row is opened: Enter, Alt+Enter (beside) or Ctrl+Enter (new tab).
pub const How = enum { normal, beside, new_tab };

pub const Source = struct {
    context: *anyopaque,
    placeholder: []const u8,
    empty_text: []const u8,
    icon: u21,
    /// Whether Alt+Enter and Ctrl+Enter mean something (files do).
    opens_files: bool = false,
    /// The rows for `query`, allocated in `arena` (freed every frame), and
    /// a short note for the right of the field ("Indexando…").
    search: *const fn (context: *anyopaque, arena: std.mem.Allocator, query: []const u8, out: *std.ArrayList(Item)) ?[]const u8,
    choose: *const fn (context: *anyopaque, id: []const u8, how: How) void,
    /// The query changed or the palette closed: a slow search can stop.
    reset: ?*const fn (context: *anyopaque) void = null,
};

/// Ranks `texts` against `query` with the core's fuzzy match (accents and
/// case do not matter; word starts count more). Indices best first, with
/// the matched byte offsets of each, in `arena`.
pub fn rank(arena: std.mem.Allocator, query: []const u8, texts: []const []const u8) ![]Ranked {
    const items = try arena.alloc(cadex.cadex_text, texts.len);
    for (texts, items) |t, *item| item.* = .{ .text = t.ptr, .len = t.len };
    var result: cadex.cadex_fuzzy_result = undefined;
    if (cadex.cadex_fuzzy_rank(query.ptr, query.len, items.ptr, items.len, &result) != cadex.CADEX_OK) return &.{};
    defer cadex.cadex_fuzzy_result_free(&result);
    const out = try arena.alloc(Ranked, result.count);
    for (out, 0..) |*r, i| {
        const m = result.matches[i];
        r.* = .{ .index = m.index, .bold = try arena.dupe(u32, result.positions[m.positions_offset..][0..m.positions_count]) };
    }
    return out;
}

pub const Ranked = struct { index: u32, bold: []const u32 };

test {
    @import("win32").refAllDeep(@This());
}
