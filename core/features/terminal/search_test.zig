//! Find (⌘F) as the app drives it: start, move through matches, read the
//! counts, and see the matches marked in the frame.

const std = @import("std");
const testing = std.testing;
const Model = @import("model.zig").Model;
const render = @import("render.zig");

fn frameOf(model: *Model, renderer: *render.Renderer) !*const render.Frame {
    try renderer.capture(testing.allocator, &model.terminal, &model.search);
    return renderer.build(testing.allocator, &model.search);
}

test "finds matches in the history and marks the ones on screen" {
    const model = try Model.create(testing.io, testing.allocator, .{ .cols = 20, .rows = 3 });
    defer model.destroy();
    var renderer: render.Renderer = .{};
    defer renderer.deinit(testing.allocator);

    // "erro" twice in lines that scroll into the history, once on screen.
    model.feed("um erro aqui\r\nnada\r\nERRO de novo\r\nnada\r\nnada\r\nnada\r\nfim erro");
    try model.search.start(testing.allocator, &model.terminal, "erro");
    var c = model.search.counts();
    try testing.expectEqual(@as(usize, 3), c.total);
    try testing.expectEqual(@as(usize, 0), c.current);

    // On screen: "fim erro" on the last row, cols 4..7.
    var frame = try frameOf(model, &renderer);
    const last_row = 2 * @as(usize, frame.cols);
    try testing.expect(frame.cells[last_row + 4].flags & render.CellFlags.match != 0);
    try testing.expect(frame.cells[last_row + 3].flags & render.CellFlags.match == 0);

    // next starts at the newest match and moves toward older ones.
    try testing.expect(try model.search.select(&model.terminal, .next));
    c = model.search.counts();
    try testing.expectEqual(@as(usize, 1), c.current);
    frame = try frameOf(model, &renderer);
    try testing.expect(frame.cells[last_row + 4].flags & render.CellFlags.match_current != 0);

    // Going to the oldest match scrolls the history into view.
    _ = try model.search.select(&model.terminal, .next);
    _ = try model.search.select(&model.terminal, .next);
    const text = try model.plainText(testing.allocator);
    defer testing.allocator.free(text);
    try testing.expect(std.mem.indexOf(u8, text, "um erro aqui") != null);

    model.search.stop(&model.terminal);
    frame = try frameOf(model, &renderer);
    for (frame.cells[0 .. @as(usize, frame.cols) * frame.rows]) |cell| {
        try testing.expect(cell.flags & (render.CellFlags.match | render.CellFlags.match_current) == 0);
    }
}

test "an empty search finds nothing and selects nothing" {
    const model = try Model.create(testing.io, testing.allocator, .{ .cols = 20, .rows = 3 });
    defer model.destroy();
    model.feed("texto");
    try model.search.start(testing.allocator, &model.terminal, "");
    try testing.expect(!model.search.isActive());
    try testing.expect(!try model.search.select(&model.terminal, .next));
}
