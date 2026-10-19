//! The lane layout on hand-made histories: two merges, an octopus, and
//! two histories with no common root.

const std = @import("std");
const testing = std.testing;
const graph = @import("graph.zig");

const S = graph.Segment;

fn expectRow(row: graph.Row, column: u16, color: u16, top: []const S, bottom: []const S) !void {
    try testing.expectEqual(column, row.column);
    try testing.expectEqual(color, row.color);
    try testing.expectEqualSlices(S, top, row.top);
    try testing.expectEqualSlices(S, bottom, row.bottom);
}

fn seg(from: u16, to: u16, color: u16) S {
    return .{ .from = from, .to = to, .color = color };
}

test "two merges: a feature merged into main, then a branch off the merge merged back" {
    // A <- B <- D(B, C) <- E <- G(E, F); C off A; F off D.
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var g = graph.Graph.init(testing.allocator);
    defer g.deinit();

    try expectRow(try g.add(arena, "G", &.{ "E", "F" }), 0, 0, &.{}, &.{ seg(0, 0, 0), seg(0, 1, 1) });
    try expectRow(try g.add(arena, "F", &.{"D"}), 1, 1, &.{ seg(0, 0, 0), seg(1, 1, 1) }, &.{ seg(0, 0, 0), seg(1, 1, 1) });
    try expectRow(try g.add(arena, "E", &.{"D"}), 0, 0, &.{ seg(0, 0, 0), seg(1, 1, 1) }, &.{ seg(0, 0, 0), seg(1, 1, 1) });
    // Both lanes wait for D: they meet at its dot; C gets the freed lane.
    try expectRow(try g.add(arena, "D", &.{ "B", "C" }), 0, 0, &.{ seg(0, 0, 0), seg(1, 0, 1) }, &.{ seg(0, 0, 0), seg(0, 1, 2) });
    try expectRow(try g.add(arena, "C", &.{"A"}), 1, 2, &.{ seg(0, 0, 0), seg(1, 1, 2) }, &.{ seg(0, 0, 0), seg(1, 1, 2) });
    try expectRow(try g.add(arena, "B", &.{"A"}), 0, 0, &.{ seg(0, 0, 0), seg(1, 1, 2) }, &.{ seg(0, 0, 0), seg(1, 1, 2) });
    // The root ends both lanes.
    try expectRow(try g.add(arena, "A", &.{}), 0, 0, &.{ seg(0, 0, 0), seg(1, 0, 2) }, &.{});
    try testing.expectEqual(@as(usize, 0), g.lanes.items.len);
}

test "an octopus merge draws one line per parent" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var g = graph.Graph.init(testing.allocator);
    defer g.deinit();
    const row = try g.add(arena, "M", &.{ "P1", "P2", "P3" });
    try expectRow(row, 0, 0, &.{}, &.{ seg(0, 0, 0), seg(0, 1, 1), seg(0, 2, 2) });
    try expectRow(try g.add(arena, "P3", &.{}), 2, 2, &.{ seg(0, 0, 0), seg(1, 1, 1), seg(2, 2, 2) }, &.{ seg(0, 0, 0), seg(1, 1, 1) });
}

test "histories without a common root start and end on their own" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var g = graph.Graph.init(testing.allocator);
    defer g.deinit();
    try expectRow(try g.add(arena, "X2", &.{"X1"}), 0, 0, &.{}, &.{seg(0, 0, 0)});
    // Y2 waits in no lane: a new one, a new color.
    try expectRow(try g.add(arena, "Y2", &.{"Y1"}), 1, 1, &.{seg(0, 0, 0)}, &.{ seg(0, 0, 0), seg(1, 1, 1) });
    try expectRow(try g.add(arena, "X1", &.{}), 0, 0, &.{ seg(0, 0, 0), seg(1, 1, 1) }, &.{seg(1, 1, 1)});
    // The free lane on the left is taken by the next tip.
    try expectRow(try g.add(arena, "Z1", &.{}), 0, 2, &.{seg(1, 1, 1)}, &.{seg(1, 1, 1)});
    try expectRow(try g.add(arena, "Y1", &.{}), 1, 1, &.{seg(1, 1, 1)}, &.{});
}

test "the layout continues across pages with the same state" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    var g = graph.Graph.init(testing.allocator);
    defer g.deinit();
    _ = try g.add(arena_state.allocator(), "B", &.{"A"});
    _ = arena_state.reset(.free_all);
    try expectRow(try g.add(arena_state.allocator(), "A", &.{}), 0, 0, &.{seg(0, 0, 0)}, &.{});
}
