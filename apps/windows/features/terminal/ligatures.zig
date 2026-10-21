//! Ligatures (plan 15, phase C), as the Mac's QuadBuilder+Ligatures.swift:
//! with the font's "calt" or "liga" on, a run of symbols the font joins
//! ("->", "!=", "===") is drawn as one shaped run over its cells instead of
//! letter by letter.

const std = @import("std");
const cadex = @import("cadex");
const font_mod = @import("font.zig");

/// The symbols programming fonts join; letters and digits never start a run.
const joinable = "!#$%&*+-./:;<=>?@\\^_|~";

pub const SymbolRun = struct {
    bytes: [font_mod.longest_run]u8 = undefined,
    count: usize = 0,

    pub fn text(self: *const SymbolRun) []const u8 {
        return self.bytes[0..self.count];
    }
};

/// Two or more cells from `start` up to `row_end`, each one joinable
/// symbol in the same color and style, none under the cursor.
pub fn symbolRun(cells: []const cadex.cadex_terminal_cell, text: []const u8, start: usize, row_end: usize, cursor_at: ?usize) ?SymbolRun {
    const style_flags: u16 = cadex.CADEX_CELL_BOLD | cadex.CADEX_CELL_ITALIC | cadex.CADEX_CELL_FAINT | cadex.CADEX_CELL_WIDE;
    const first = cells[start];
    var run: SymbolRun = .{};
    var i = start;
    while (i < row_end and run.count < font_mod.longest_run and i != cursor_at) : (i += 1) {
        const cell = cells[i];
        if (cell.text_len != 1 or cell.fg != first.fg) break;
        if (cell.flags & style_flags != first.flags & style_flags or cell.flags & cadex.CADEX_CELL_WIDE != 0) break;
        const byte = text[cell.text_offset];
        if (std.mem.indexOfScalar(u8, joinable, byte) == null) break;
        run.bytes[run.count] = byte;
        run.count += 1;
    }
    return if (run.count >= 2) run else null;
}

/// The advance of each shaped glyph: one cell each when the font kept one
/// glyph per letter (Fira Code, JetBrains Mono), else the cells shared out.
pub fn advance(cells: usize, glyphs: usize, cell_width: f32) f32 {
    if (glyphs == 0) return 0;
    return cell_width * @as(f32, @floatFromInt(cells)) / @as(f32, @floatFromInt(glyphs));
}

test "a run of symbols stops at letters, colors and the cursor" {
    const Cell = cadex.cadex_terminal_cell;
    const text = "a->=b";
    var cells: [5]Cell = undefined;
    for (&cells, 0..) |*cell, i| cell.* = std.mem.zeroInit(Cell, .{ .text_offset = @as(u32, @intCast(i)), .text_len = 1, .fg = 0xffffff });
    try std.testing.expect(symbolRun(&cells, text, 0, 5, null) == null);
    const run = symbolRun(&cells, text, 1, 5, null).?;
    try std.testing.expectEqualStrings("->=", run.text());
    try std.testing.expect(symbolRun(&cells, text, 1, 5, 2) == null);
    cells[3].fg = 0xff0000;
    try std.testing.expectEqualStrings("->", symbolRun(&cells, text, 1, 5, null).?.text());
    try std.testing.expectEqual(@as(f32, 16), advance(2, 1, 8));
}

test {
    @import("win32").refAllDeep(@This());
}
