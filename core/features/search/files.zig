//! Ranking the indexed paths for ⌘P: fuzzy over the relative path, with the
//! file name worth more than its folders (docs/spec/search.md). Runs on
//! every keystroke, so a cheap in-order check skips most paths before the
//! full scoring.

const std = @import("std");
const fuzzy = @import("fuzzy.zig");

/// A match in the file name alone beats any match spread over folders of a
/// similar score; tuned by hand on the Cadex tree (2026-10-19).
const bonus_in_name: i32 = 100;

pub const Hit = struct {
    /// Into the list that was ranked.
    index: u32,
    score: i32,
    /// Byte offsets in the path of the matched characters.
    positions: []u32,
};

/// The best `limit` paths for `query`, best first. An empty query gives
/// nothing (the app shows recent files). Free with deinit.
pub fn rank(gpa: std.mem.Allocator, query: []const u8, list: []const []const u8, limit: usize) ![]Hit {
    if (query.len == 0 or limit == 0) return &.{};
    var hits: std.ArrayList(Hit) = .empty;
    errdefer {
        deinit(gpa, hits.items);
        hits.deinit(gpa);
    }
    for (list, 0..) |path, i| {
        if (!mayMatch(query, path)) continue;
        const scored = try score(gpa, query, path) orelse continue;
        try hits.append(gpa, .{ .index = @intCast(i), .score = scored.score, .positions = scored.positions });
    }
    std.mem.sort(Hit, hits.items, list, better);
    const keep = @min(limit, hits.items.len);
    for (hits.items[keep..]) |h| gpa.free(h.positions);
    hits.shrinkRetainingCapacity(keep);
    return hits.toOwnedSlice(gpa);
}

pub fn deinit(gpa: std.mem.Allocator, hits: []const Hit) void {
    for (hits) |h| gpa.free(h.positions);
}

fn better(list: []const []const u8, a: Hit, b: Hit) bool {
    if (a.score != b.score) return a.score > b.score;
    if (list[a.index].len != list[b.index].len) return list[a.index].len < list[b.index].len;
    return std.mem.order(u8, list[a.index], list[b.index]) == .lt;
}

/// The name alone first; if the query does not fit in it, the whole path.
fn score(gpa: std.mem.Allocator, query: []const u8, path: []const u8) !?fuzzy.Match {
    const name_start = if (std.mem.lastIndexOfScalar(u8, path, '/')) |slash| slash + 1 else 0;
    if (try fuzzy.match(gpa, query, path[name_start..])) |m| {
        for (m.positions) |*p| p.* += @intCast(name_start);
        return .{ .score = m.score + bonus_in_name - lengthPenalty(path), .positions = m.positions };
    }
    const m = try fuzzy.match(gpa, query, path) orelse return null;
    return .{ .score = m.score - lengthPenalty(path), .positions = m.positions };
}

/// Shorter paths first among equals: core/x.zig before core/deep/x.zig.
fn lengthPenalty(path: []const u8) i32 {
    return @intCast(@min(path.len / 16, 20));
}

/// Cheap check that the query's letters appear in order, ignoring ASCII
/// case. With accents on either side it says yes and leaves the decision
/// to fuzzy, which folds them.
fn mayMatch(query: []const u8, path: []const u8) bool {
    var at: usize = 0;
    for (query) |q| {
        if (q >= 0x80) return true;
        const want = std.ascii.toLower(q);
        while (true) : (at += 1) {
            if (at >= path.len) return false;
            if (path[at] >= 0x80) return true;
            if (std.ascii.toLower(path[at]) == want) break;
        }
        at += 1;
    }
    return true;
}

const testing = std.testing;

test "the file name counts more than the folders" {
    const list = [_][]const u8{
        "docs/render/notes.md",
        "core/features/terminal/render.zig",
        "core/features/terminal/render_test.zig",
        "apps/macos/features/terminal/TerminalRenderer.swift",
    };
    const hits = try rank(testing.allocator, "render.zig", &list, 10);
    defer {
        deinit(testing.allocator, hits);
        testing.allocator.free(hits);
    }
    try testing.expectEqual(@as(u32, 1), hits[0].index);
    try testing.expectEqual(@as(usize, 10), hits[0].positions.len);
    try testing.expectEqual(@as(u32, 23), hits[0].positions[0]);
}

test "letters in order across folders find a path" {
    // The plan's example was "cntrl", but those letters are not in order in
    // this path (no t after the n of terminal); "trmcapi" is the same idea.
    const list = [_][]const u8{ "core/features/terminal/c_api.zig", "core/features/search/c_api.zig", "Makefile" };
    const hits = try rank(testing.allocator, "trmcapi", &list, 10);
    defer {
        deinit(testing.allocator, hits);
        testing.allocator.free(hits);
    }
    try testing.expectEqual(@as(usize, 1), hits.len);
    try testing.expectEqual(@as(u32, 0), hits[0].index);
}

test "the quick check agrees with fuzzy and keeps the limit" {
    try testing.expect(mayMatch("RZ", "core/render.zig"));
    try testing.expect(!mayMatch("zr", "core/render.zig"));
    try testing.expect(mayMatch("ã", "abc"));
    const list = [_][]const u8{ "a1", "a2", "a3" };
    const hits = try rank(testing.allocator, "a", &list, 2);
    defer {
        deinit(testing.allocator, hits);
        testing.allocator.free(hits);
    }
    try testing.expectEqual(@as(usize, 2), hits.len);
    const none = try rank(testing.allocator, "", &list, 2);
    try testing.expectEqual(@as(usize, 0), none.len);
}
