//! How a tab is divided into panes (docs/spec/tabs.md, "Divisões"): a
//! binary tree whose leaves are panes (by id) and whose nodes split their
//! space side by side or one above the other. Pure, the same rules as the
//! Mac's PaneTree.swift, so splitting, closing and focus moves are tested.

const std = @import("std");
const gfx = @import("gfx");

pub const Axis = enum { horizontal, vertical };
pub const Direction = enum { left, right, up, down };

pub const Node = union(enum) {
    leaf: u32,
    split: Split,

    pub const Split = struct {
        axis: Axis,
        a: *Node,
        b: *Node,
        /// The share of the first child, between 0 and 1.
        ratio: f32,
    };
};

pub const Tree = struct {
    gpa: std.mem.Allocator,
    root: *Node,

    pub fn init(gpa: std.mem.Allocator, pane: u32) !Tree {
        const root = try gpa.create(Node);
        root.* = .{ .leaf = pane };
        return .{ .gpa = gpa, .root = root };
    }

    pub fn deinit(self: *Tree) void {
        free(self.gpa, self.root);
    }

    fn free(gpa: std.mem.Allocator, node: *Node) void {
        switch (node.*) {
            .leaf => {},
            .split => |s| {
                free(gpa, s.a);
                free(gpa, s.b);
            },
        }
        gpa.destroy(node);
    }

    /// The panes in reading order: left before right, top before bottom.
    pub fn leaves(self: *const Tree, out: *std.ArrayList(u32)) void {
        collect(self.root, out, self.gpa);
    }

    fn collect(node: *const Node, out: *std.ArrayList(u32), gpa: std.mem.Allocator) void {
        switch (node.*) {
            .leaf => |id| out.append(gpa, id) catch {},
            .split => |s| {
                collect(s.a, out, gpa);
                collect(s.b, out, gpa);
            },
        }
    }

    pub fn count(self: *const Tree) usize {
        return countOf(self.root);
    }

    fn countOf(node: *const Node) usize {
        return switch (node.*) {
            .leaf => 1,
            .split => |s| countOf(s.a) + countOf(s.b),
        };
    }

    fn find(node: *Node, pane: u32) ?*Node {
        switch (node.*) {
            .leaf => |id| return if (id == pane) node else null,
            .split => |s| return find(s.a, pane) orelse find(s.b, pane),
        }
    }

    /// Splits `pane` in two, `new_pane` after it, half and half.
    pub fn split(self: *Tree, pane: u32, axis: Axis, new_pane: u32) !void {
        const node = find(self.root, pane) orelse return;
        const a = try self.gpa.create(Node);
        errdefer self.gpa.destroy(a);
        const b = try self.gpa.create(Node);
        a.* = .{ .leaf = pane };
        b.* = .{ .leaf = new_pane };
        node.* = .{ .split = .{ .axis = axis, .a = a, .b = b, .ratio = 0.5 } };
    }

    /// Removes `pane`; its sibling takes the space. False when it was the
    /// only pane (the caller closes the tab).
    pub fn remove(self: *Tree, pane: u32) bool {
        if (self.root.* == .leaf) return false;
        return removeFrom(self.gpa, self.root, pane);
    }

    fn removeFrom(gpa: std.mem.Allocator, node: *Node, pane: u32) bool {
        const s = switch (node.*) {
            .leaf => return false,
            .split => |s| s,
        };
        const keep: ?*Node = if (s.a.* == .leaf and s.a.leaf == pane) s.b else if (s.b.* == .leaf and s.b.leaf == pane) s.a else null;
        if (keep) |k| {
            const gone = if (k == s.a) s.b else s.a;
            node.* = k.*;
            gpa.destroy(k);
            gpa.destroy(gone);
            return true;
        }
        return removeFrom(gpa, s.a, pane) or removeFrom(gpa, s.b, pane);
    }

    pub const Frame = struct { pane: u32, rect: gfx.Rect };

    /// Where each pane goes inside `rect`, with `gap` between siblings.
    pub fn frames(self: *const Tree, rect: gfx.Rect, gap: f32, out: *std.ArrayList(Frame)) void {
        framesOf(self.root, rect, gap, out, self.gpa);
    }

    fn framesOf(node: *const Node, rect: gfx.Rect, gap: f32, out: *std.ArrayList(Frame), gpa: std.mem.Allocator) void {
        switch (node.*) {
            .leaf => |id| out.append(gpa, .{ .pane = id, .rect = rect }) catch {},
            .split => |s| {
                const parts = divide(rect, s.axis, s.ratio, gap);
                framesOf(s.a, parts[0], gap, out, gpa);
                framesOf(s.b, parts[1], gap, out, gpa);
            },
        }
    }

    pub fn divide(rect: gfx.Rect, axis: Axis, ratio: f32, gap: f32) [2]gfx.Rect {
        switch (axis) {
            .horizontal => {
                const first_w = @round((rect.w - gap) * ratio);
                return .{
                    .{ .x = rect.x, .y = rect.y, .w = first_w, .h = rect.h },
                    .{ .x = rect.x + first_w + gap, .y = rect.y, .w = rect.w - first_w - gap, .h = rect.h },
                };
            },
            .vertical => {
                const first_h = @round((rect.h - gap) * ratio);
                return .{
                    .{ .x = rect.x, .y = rect.y, .w = rect.w, .h = first_h },
                    .{ .x = rect.x, .y = rect.y + first_h + gap, .w = rect.w, .h = rect.h - first_h - gap },
                };
            },
        }
    }

    /// Ctrl+Shift+] and [: the next or previous pane in reading order, wrapping.
    pub fn cycle(self: *const Tree, from: u32, step: i32) ?u32 {
        var all: std.ArrayList(u32) = .empty;
        defer all.deinit(self.gpa);
        self.leaves(&all);
        const i = std.mem.indexOfScalar(u32, all.items, from) orelse return null;
        const n: i32 = @intCast(all.items.len);
        const next = @mod(@as(i32, @intCast(i)) + step + n, n);
        return all.items[@intCast(next)];
    }

    /// The pane next to `from` in that direction, facing it most, nearest first.
    pub fn neighbor(self: *const Tree, from: u32, direction: Direction, rect: gfx.Rect) ?u32 {
        var list: std.ArrayList(Frame) = .empty;
        defer list.deinit(self.gpa);
        self.frames(rect, 0, &list);
        var origin: ?gfx.Rect = null;
        for (list.items) |f| if (f.pane == from) {
            origin = f.rect;
        };
        const o = origin orelse return null;
        var best: ?u32 = null;
        var best_distance: f32 = std.math.inf(f32);
        var best_overlap: f32 = 0;
        for (list.items) |f| {
            if (f.pane == from) continue;
            const r = f.rect;
            const vertical = direction == .left or direction == .right;
            const ov = overlap(r, o, vertical);
            const ok = ov > 0 and switch (direction) {
                .left => r.right() <= o.x + 1,
                .right => r.x >= o.right() - 1,
                .up => r.bottom() <= o.y + 1,
                .down => r.y >= o.bottom() - 1,
            };
            if (!ok) continue;
            const d = switch (direction) {
                .left => o.x - r.right(),
                .right => r.x - o.right(),
                .up => o.y - r.bottom(),
                .down => r.y - o.bottom(),
            };
            if (d < best_distance or (d == best_distance and ov > best_overlap)) {
                best = f.pane;
                best_distance = d;
                best_overlap = ov;
            }
        }
        return best;
    }

    /// Every pane in a row (or a column) the same size: each split gives
    /// its sides space by how many panes they line up in its direction.
    pub fn balance(self: *Tree) void {
        balanceNode(self.root);
    }

    fn balanceNode(node: *Node) void {
        switch (node.*) {
            .leaf => {},
            .split => |*s| {
                const wa = along(s.a, s.axis);
                const wb = along(s.b, s.axis);
                s.ratio = @as(f32, @floatFromInt(wa)) / @as(f32, @floatFromInt(wa + wb));
                balanceNode(s.a);
                balanceNode(s.b);
            },
        }
    }

    fn along(node: *const Node, axis: Axis) usize {
        return switch (node.*) {
            .leaf => 1,
            .split => |s| if (s.axis == axis) along(s.a, axis) + along(s.b, axis) else 1,
        };
    }
};

fn overlap(a: gfx.Rect, b: gfx.Rect, vertical: bool) f32 {
    return if (vertical) @min(a.bottom(), b.bottom()) - @max(a.y, b.y) else @min(a.right(), b.right()) - @max(a.x, b.x);
}

const testing = std.testing;

fn leavesOf(t: *const Tree) ![]u32 {
    var list: std.ArrayList(u32) = .empty;
    t.leaves(&list);
    return list.toOwnedSlice(testing.allocator);
}

test "split, remove and balance give the layouts of the spec" {
    var t = try Tree.init(testing.allocator, 1);
    defer t.deinit();
    try t.split(1, .horizontal, 2);
    try t.split(2, .horizontal, 3);
    t.balance();
    var frames: std.ArrayList(Tree.Frame) = .empty;
    defer frames.deinit(testing.allocator);
    t.frames(.{ .w = 300, .h = 100 }, 0, &frames);
    try testing.expectEqual(@as(f32, 100), frames.items[0].rect.w);
    try testing.expectEqual(@as(f32, 100), frames.items[1].rect.w);
    try testing.expect(t.remove(2));
    t.balance();
    const left = try leavesOf(&t);
    defer testing.allocator.free(left);
    try testing.expectEqualSlices(u32, &.{ 1, 3 }, left);
    try testing.expect(t.remove(3));
    try testing.expect(!t.remove(1));
}

test "neighbors by direction and cycling" {
    var t = try Tree.init(testing.allocator, 1);
    defer t.deinit();
    try t.split(1, .horizontal, 2);
    try t.split(2, .vertical, 3);
    const area: gfx.Rect = .{ .w = 200, .h = 200 };
    try testing.expectEqual(@as(?u32, 2), t.neighbor(1, .right, area));
    try testing.expectEqual(@as(?u32, 3), t.neighbor(2, .down, area));
    try testing.expectEqual(@as(?u32, 1), t.neighbor(3, .left, area));
    try testing.expectEqual(@as(?u32, null), t.neighbor(1, .left, area));
    try testing.expectEqual(@as(?u32, 1), t.cycle(3, 1));
    try testing.expectEqual(@as(?u32, 3), t.cycle(1, -1));
}
