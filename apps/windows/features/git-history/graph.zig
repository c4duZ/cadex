//! One row of the graph (docs/spec/git-history.md), the Mac's
//! HistoryGraphView: lines from the row above to the dot or straight down,
//! the dot (hollow on a merge, larger on HEAD), and the lines to the
//! parents' lanes. Rows are drawn one at a time, only those in view.

const std = @import("std");
const gfx = @import("gfx");
const ui = @import("ui");
const log = @import("log.zig");

const Color = gfx.Color;
const Point = gfx.Point;

pub const lane_width: f32 = 12;
pub const margin: f32 = 8;
/// Lanes past this are cut: the graph column would eat the subjects.
pub const max_lanes = 24;

/// The Mac's system colors in dark mode, in its order.
const palette = [_]u32{ 0x0a84ff, 0xff375f, 0x30d158, 0xff9f0a, 0xbf5af2, 0x40c8e0, 0xffd60a, 0xff453a };

pub fn color(index: usize) Color {
    return Color.rgb(palette[index % palette.len]);
}

/// The column's width for rows touching `lanes` lanes, in DIPs.
pub fn width(lanes: usize) f32 {
    return margin * 2 + @as(f32, @floatFromInt(std.math.clamp(lanes, 1, max_lanes))) * lane_width;
}

pub fn draw(u: *ui.Ui, r: gfx.Rect, graph: log.Graph, merge: bool, head: bool) void {
    u.painter.pushClip(r);
    defer u.painter.popClip();
    const mid = r.y + r.h / 2;
    const thick = @max(1.5, u.px(2));
    for (graph.top) |s| curve(u, .{ .x = x(u, r, s.from), .y = r.y }, .{ .x = x(u, r, s.to), .y = mid }, color(s.color), thick);
    for (graph.bottom) |s| curve(u, .{ .x = x(u, r, s.from), .y = mid }, .{ .x = x(u, r, s.to), .y = r.bottom() }, color(s.color), thick);
    const radius = u.px(if (head) 4.5 else 3.5);
    const at: Point = .{ .x = x(u, r, graph.column), .y = mid };
    const tint = color(graph.color);
    u.painter.fillEllipse(at, radius, radius, tint);
    if (merge) {
        const hole = radius - thick;
        if (hole > 0) u.painter.fillEllipse(at, hole, hole, u.style.panel);
    }
}

fn x(u: *ui.Ui, r: gfx.Rect, lane: u16) f32 {
    return r.x + u.px(margin) + (@as(f32, @floatFromInt(lane)) + 0.5) * u.px(lane_width);
}

/// Straight when the lane does not move; otherwise an S curve (a cubic
/// with vertical tangents, in eight pieces: the painter draws lines), so
/// forks and merges read as branches.
fn curve(u: *ui.Ui, a: Point, b: Point, tint: Color, thick: f32) void {
    if (a.x == b.x) return u.painter.line(a, b, tint, thick);
    var last = a;
    const pieces = 8;
    for (1..pieces + 1) |i| {
        const t = @as(f32, @floatFromInt(i)) / pieces;
        const next = sCurve(a, b, t);
        u.painter.line(last, next, tint, thick);
        last = next;
    }
}

/// The point at `t` of the cubic from a to b whose control points sit
/// halfway down, straight below a and above b.
pub fn sCurve(a: Point, b: Point, t: f32) Point {
    const bend = (b.y - a.y) / 2;
    const p1: Point = .{ .x = a.x, .y = a.y + bend };
    const p2: Point = .{ .x = b.x, .y = b.y - bend };
    const s = 1 - t;
    const k0 = s * s * s;
    const k1 = 3 * s * s * t;
    const k2 = 3 * s * t * t;
    const k3 = t * t * t;
    return .{ .x = k0 * a.x + k1 * p1.x + k2 * p2.x + k3 * b.x, .y = k0 * a.y + k1 * p1.y + k2 * p2.y + k3 * b.y };
}

test "the S curve starts and ends on its lanes and crosses halfway" {
    const a: Point = .{ .x = 0, .y = 0 };
    const b: Point = .{ .x = 12, .y = 10 };
    try std.testing.expectEqual(a, sCurve(a, b, 0));
    try std.testing.expectEqual(b, sCurve(a, b, 1));
    const m = sCurve(a, b, 0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 6), m.x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 5), m.y, 0.001);
}

test "the column fits the lanes, up to the cut" {
    try std.testing.expectEqual(margin * 2 + lane_width, width(0));
    try std.testing.expectEqual(margin * 2 + 24 * lane_width, width(100));
}

test {
    @import("win32").refAllDeep(@This());
}
