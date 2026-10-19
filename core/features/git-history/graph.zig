//! The commit graph laid out in lanes (docs/spec/git-history.md). Commits
//! come newest first, children before parents (git log --date-order); each
//! lane waits for one commit. A row says where its commit sits and which
//! lines cross its top half (from the row above to the dot, or straight
//! down) and its bottom half (from the dot to the parents' lanes, or
//! straight down). The state carries over between pages, so the lines
//! continue without a seam. Pure: no git here.

const std = @import("std");

pub const Segment = struct {
    from: u16,
    to: u16,
    color: u16,
};

pub const Row = struct {
    column: u16,
    color: u16,
    /// From a lane at the top edge to `to` at the middle.
    top: []Segment,
    /// From `from` at the middle to a lane at the bottom edge.
    bottom: []Segment,
};

/// A commit id (sha-1 or sha-256, in hex) kept without allocating.
const Sha = struct {
    buf: [64]u8 = undefined,
    len: u8 = 0,

    fn of(text: []const u8) Sha {
        var s: Sha = .{};
        s.len = @intCast(@min(text.len, s.buf.len));
        @memcpy(s.buf[0..s.len], text[0..s.len]);
        return s;
    }

    fn eql(self: Sha, text: []const u8) bool {
        return std.mem.eql(u8, self.buf[0..self.len], text);
    }
};

const Lane = struct {
    /// The commit this lane waits for.
    sha: Sha,
    color: u16,
};

pub const Graph = struct {
    gpa: std.mem.Allocator,
    lanes: std.ArrayList(?Lane) = .empty,
    next_color: u16 = 0,

    pub fn init(gpa: std.mem.Allocator) Graph {
        return .{ .gpa = gpa };
    }

    pub fn deinit(self: *Graph) void {
        self.lanes.deinit(self.gpa);
    }

    /// Lays out the next commit. The row's segments are allocated in
    /// `arena` (one per page).
    pub fn add(self: *Graph, arena: std.mem.Allocator, sha: []const u8, parents: []const []const u8) !Row {
        var top: std.ArrayList(Segment) = .empty;
        var bottom: std.ArrayList(Segment) = .empty;

        // Every lane waiting for this commit ends at its dot; the first one
        // holds it. None waiting: a branch tip, in a new lane.
        var column: ?u16 = null;
        for (self.lanes.items, 0..) |maybe, k| {
            const lane = maybe orelse continue;
            const here: u16 = @intCast(k);
            if (lane.sha.eql(sha)) {
                if (column == null) column = here;
                try top.append(arena, .{ .from = here, .to = column.?, .color = lane.color });
            } else {
                try top.append(arena, .{ .from = here, .to = here, .color = lane.color });
            }
        }
        const col = column orelse try self.open(Sha.of(sha), self.newColor());
        const color = self.lanes.items[col].?.color;
        for (self.lanes.items, 0..) |*maybe, k| {
            if (k != col and maybe.* != null and maybe.*.?.sha.eql(sha)) maybe.* = null;
        }

        // The first parent continues the lane; the others go to the lane
        // already waiting for them or to a new one (merges, octopus too).
        var merges: std.ArrayList(Segment) = .empty;
        if (parents.len == 0) {
            self.lanes.items[col] = null;
        } else {
            self.lanes.items[col] = .{ .sha = Sha.of(parents[0]), .color = color };
            for (parents[1..]) |parent| {
                const target = self.waiting(parent) orelse try self.open(Sha.of(parent), self.newColor());
                try merges.append(arena, .{ .from = col, .to = target, .color = self.lanes.items[target].?.color });
            }
        }

        // Lines that crossed the top straight go on down; the dot's own
        // lane and the merge lines leave from the middle (a lane opened
        // just now for a merge parent starts there too).
        for (self.lanes.items, 0..) |maybe, k| {
            const lane = maybe orelse continue;
            const here: u16 = @intCast(k);
            if (here == col) {
                try bottom.append(arena, .{ .from = col, .to = col, .color = color });
            } else if (passedThrough(top.items, here)) {
                try bottom.append(arena, .{ .from = here, .to = here, .color = lane.color });
            }
        }
        try bottom.appendSlice(arena, merges.items);
        self.trim();
        return .{ .column = col, .color = color, .top = top.items, .bottom = bottom.items };
    }

    fn newColor(self: *Graph) u16 {
        defer self.next_color +%= 1;
        return self.next_color;
    }

    /// The lane already waiting for `sha`, if any.
    fn waiting(self: *Graph, sha: []const u8) ?u16 {
        for (self.lanes.items, 0..) |maybe, k| {
            if (maybe) |lane| if (lane.sha.eql(sha)) return @intCast(k);
        }
        return null;
    }

    /// Takes the first free lane, or a new one on the right.
    fn open(self: *Graph, sha: Sha, color: u16) !u16 {
        for (self.lanes.items, 0..) |*maybe, k| {
            if (maybe.* == null) {
                maybe.* = .{ .sha = sha, .color = color };
                return @intCast(k);
            }
        }
        try self.lanes.append(self.gpa, .{ .sha = sha, .color = color });
        return @intCast(self.lanes.items.len - 1);
    }

    fn trim(self: *Graph) void {
        while (self.lanes.items.len > 0 and self.lanes.items[self.lanes.items.len - 1] == null) _ = self.lanes.pop();
    }
};

/// A lane that crossed the row's top straight (not one that ended at the dot).
fn passedThrough(top: []const Segment, lane: u16) bool {
    for (top) |s| if (s.from == lane and s.to == lane) return true;
    return false;
}
