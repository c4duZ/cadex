//! Selection as the app drives it: clicks, drags and Shift+click on viewport
//! cells, then the copied text and the cells marked in the frame.

const std = @import("std");
const testing = std.testing;
const Model = @import("model.zig").Model;
const selection = @import("selection.zig");
const render = @import("render.zig");

/// Cells 10 px wide and 20 px tall, no padding.
fn at(col: u16, row: u16, side: enum { left, right }) selection.Pointer {
    const x: f64 = @floatFromInt(@as(u32, col) * 10 + @as(u32, if (side == .left) 1 else 9));
    return .{
        .x = x,
        .y = @floatFromInt(@as(u32, row) * 20 + 10),
        .col = col,
        .row = row,
        .cell_width = 10,
        .padding_left = 0,
        .view_height = 20 * 4,
    };
}

fn expectSelected(model: *Model, expected: ?[]const u8) !void {
    const text = try selection.selectedText(&model.terminal, testing.allocator);
    defer if (text) |t| testing.allocator.free(t);
    if (expected) |e| {
        try testing.expectEqualStrings(e, text orelse return error.NoSelection);
    } else {
        try testing.expect(text == null);
    }
}

fn click(model: *Model, p: selection.Pointer, clicks: u8) !void {
    try model.selector.press(&model.terminal, p, clicks, false);
    model.selector.release(&model.terminal, p);
}

test "double click selects a word, triple click the line" {
    const model = try Model.create(testing.io, testing.allocator, .{ .cols = 30, .rows = 4 });
    defer model.destroy();
    model.feed("ls ~/projeto/src (ok)");

    try click(model, at(5, 0, .left), 2);
    try expectSelected(model, "~/projeto/src");

    try click(model, at(5, 0, .left), 3);
    try expectSelected(model, "ls ~/projeto/src (ok)");

    // A plain click clears the selection.
    try click(model, at(5, 0, .left), 1);
    try expectSelected(model, null);
}

test "dragging selects from cell to cell" {
    const model = try Model.create(testing.io, testing.allocator, .{ .cols = 20, .rows = 4 });
    defer model.destroy();
    model.feed("first line\r\nsecond line");

    try model.selector.press(&model.terminal, at(6, 0, .left), 1, false);
    _ = try model.selector.drag(&model.terminal, at(5, 1, .right));
    model.selector.release(&model.terminal, at(5, 1, .right));
    try expectSelected(model, "line\nsecond");
}

test "Shift+click extends the selection" {
    const model = try Model.create(testing.io, testing.allocator, .{ .cols = 20, .rows = 4 });
    defer model.destroy();
    model.feed("one two three");

    try click(model, at(0, 0, .left), 2);
    try model.selector.press(&model.terminal, at(6, 0, .left), 1, true);
    try expectSelected(model, "one two");
}

test "a line wrapped by width copies back whole, without trailing spaces" {
    const model = try Model.create(testing.io, testing.allocator, .{ .cols = 10, .rows = 4 });
    defer model.destroy();
    model.feed("echo abcdefghij   \r\nnext");

    try click(model, at(0, 0, .left), 3);
    try expectSelected(model, "echo abcdefghij");
}

test "select all includes the history" {
    const model = try Model.create(testing.io, testing.allocator, .{ .cols = 10, .rows = 2 });
    defer model.destroy();
    model.feed("a\r\nb\r\nc\r\nd");

    try selection.selectAll(&model.terminal);
    try expectSelected(model, "a\nb\nc\nd");
    selection.clear(&model.terminal);
    try testing.expect(!selection.hasSelection(&model.terminal));
}

test "selected cells are marked in the frame" {
    const model = try Model.create(testing.io, testing.allocator, .{ .cols = 10, .rows = 2 });
    defer model.destroy();
    var renderer: render.Renderer = .{};
    defer renderer.deinit(testing.allocator);
    model.feed("ab cd");

    try click(model, at(3, 0, .left), 2);
    try renderer.capture(testing.allocator, &model.terminal);
    const frame = try renderer.build(testing.allocator);
    const selected = render.CellFlags.selected;
    try testing.expect(frame.cells[0].flags & selected == 0);
    try testing.expect(frame.cells[3].flags & selected != 0);
    try testing.expect(frame.cells[4].flags & selected != 0);
    try testing.expect(frame.cells[5].flags & selected == 0);
}
