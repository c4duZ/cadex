//! What the apps draw: feeds escape sequences into a model and checks the
//! flat frame the renderer produces.

const std = @import("std");
const testing = std.testing;
const Model = @import("model.zig").Model;
const render = @import("render.zig");
const Flags = render.CellFlags;

const Fixture = struct {
    model: *Model,
    renderer: render.Renderer = .{},

    fn init(cols: u16, rows: u16) !Fixture {
        return .{ .model = try Model.create(testing.io, testing.allocator, .{ .cols = cols, .rows = rows }) };
    }

    fn deinit(self: *Fixture) void {
        self.renderer.deinit(testing.allocator);
        self.model.destroy();
    }

    fn frame(self: *Fixture) !*const render.Frame {
        try self.renderer.capture(testing.allocator, &self.model.terminal);
        return self.renderer.build(testing.allocator);
    }
};

fn cellAt(frame: *const render.Frame, x: usize, y: usize) render.Cell {
    return frame.cells[y * frame.cols + x];
}

fn textOf(frame: *const render.Frame, cell: render.Cell) []const u8 {
    return frame.text[cell.text_offset..][0..cell.text_len];
}

test "plain text uses the default colors and has no background" {
    var f = try Fixture.init(10, 3);
    defer f.deinit();
    f.model.feed("hi");
    const frame = try f.frame();

    try testing.expectEqual(@as(u16, 10), frame.cols);
    try testing.expectEqual(@as(u16, 3), frame.rows);
    const h = cellAt(frame, 0, 0);
    try testing.expectEqualStrings("h", textOf(frame, h));
    try testing.expectEqual(frame.foreground, h.fg);
    try testing.expectEqual(@as(u16, 0), h.flags & Flags.has_background);
    try testing.expectEqual(@as(u16, 0), cellAt(frame, 5, 0).text_len);
}

test "true color, bold, italic, underline and strikethrough" {
    var f = try Fixture.init(10, 3);
    defer f.deinit();
    f.model.feed("\x1b[1;3;4;9;38;2;255;128;0;48;2;0;0;255mX");
    const cell = cellAt(try f.frame(), 0, 0);

    try testing.expectEqual(@as(u32, 0xFF8000), cell.fg);
    try testing.expectEqual(@as(u32, 0x0000FF), cell.bg);
    try testing.expect(cell.flags & Flags.bold != 0);
    try testing.expect(cell.flags & Flags.italic != 0);
    try testing.expect(cell.flags & Flags.strikethrough != 0);
    try testing.expect(cell.flags & Flags.has_background != 0);
    try testing.expectEqual(@as(u16, 1), (cell.flags >> Flags.underline_shift) & 0b111);
}

test "inverse swaps the colors" {
    var f = try Fixture.init(10, 3);
    defer f.deinit();
    f.model.feed("\x1b[7mI");
    const frame = try f.frame();
    const cell = cellAt(frame, 0, 0);
    try testing.expectEqual(frame.background, cell.fg);
    try testing.expectEqual(frame.foreground, cell.bg);
    try testing.expect(cell.flags & Flags.has_background != 0);
}

test "wide characters and emoji graphemes" {
    var f = try Fixture.init(10, 3);
    defer f.deinit();
    // CJK ideograph (wide), then a thumbs-up with a skin tone modifier.
    f.model.feed("\u{4E2D}\u{1F44D}\u{1F3FD}");
    const frame = try f.frame();

    const wide = cellAt(frame, 0, 0);
    try testing.expectEqualStrings("\u{4E2D}", textOf(frame, wide));
    try testing.expect(wide.flags & Flags.wide != 0);
    try testing.expect(cellAt(frame, 1, 0).flags & Flags.spacer != 0);
    try testing.expectEqualStrings("\u{1F44D}\u{1F3FD}", textOf(frame, cellAt(frame, 2, 0)));
}

test "cursor position and style" {
    var f = try Fixture.init(10, 3);
    defer f.deinit();
    // Move to row 2, column 4 (1-based) and ask for a bar cursor.
    f.model.feed("\x1b[2;4H\x1b[6 q");
    const frame = try f.frame();
    try testing.expectEqual(@as(u16, 3), frame.cursor_x);
    try testing.expectEqual(@as(u16, 1), frame.cursor_y);
    try testing.expect(frame.cursor_visible);
    try testing.expectEqual(render.CursorStyle.bar, frame.cursor_style);

    f.model.feed("\x1b[?25l");
    try testing.expect(!(try f.frame()).cursor_visible);
}

test "the frame follows a resize" {
    var f = try Fixture.init(10, 3);
    defer f.deinit();
    try f.model.resize(.{ .cols = 20, .rows = 5 });
    const frame = try f.frame();
    try testing.expectEqual(@as(u16, 20), frame.cols);
    try testing.expectEqual(@as(u16, 5), frame.rows);
}
