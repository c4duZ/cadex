//! Ranks a list of texts against a query with fuzzy.zig: the matches, best
//! first, each with the byte positions to bold.

const std = @import("std");
const fuzzy = @import("fuzzy.zig");

pub const Ranked = struct {
    /// Index of the text in the input list.
    index: u32,
    score: i32,
    /// Matched byte offsets in the text.
    positions: []u32,
};

/// The texts that match, best score first; ties go to the shorter text,
/// then to the input order. An empty query keeps every text in order.
/// Caller frees with `deinit`.
pub fn rank(gpa: std.mem.Allocator, query: []const u8, texts: []const []const u8) ![]Ranked {
    var out: std.ArrayList(Ranked) = .empty;
    errdefer deinit(gpa, out.items);
    for (texts, 0..) |text, i| {
        const m = try fuzzy.match(gpa, query, text) orelse continue;
        try out.append(gpa, .{ .index = @intCast(i), .score = m.score, .positions = m.positions });
    }
    const Order = struct {
        texts: []const []const u8,
        fn before(ctx: @This(), a: Ranked, b: Ranked) bool {
            if (a.score != b.score) return a.score > b.score;
            const la = ctx.texts[a.index].len;
            const lb = ctx.texts[b.index].len;
            if (la != lb) return la < lb;
            return a.index < b.index;
        }
    };
    if (query.len > 0) std.mem.sort(Ranked, out.items, Order{ .texts = texts }, Order.before);
    return out.toOwnedSlice(gpa);
}

pub fn deinit(gpa: std.mem.Allocator, ranked: []const Ranked) void {
    for (ranked) |r| gpa.free(r.positions);
}

const testing = std.testing;

test "the palette's example: 'na' puts Nova aba first" {
    const texts = [_][]const u8{ "Abrir nova janela", "Limpar o terminal", "Nova aba" };
    const ranked = try rank(testing.allocator, "na", &texts);
    defer {
        deinit(testing.allocator, ranked);
        testing.allocator.free(ranked);
    }
    // "terminal" has an n before an a too: all three match, Nova aba first.
    try testing.expectEqual(@as(usize, 3), ranked.len);
    try testing.expectEqual(@as(u32, 2), ranked[0].index);
}

test "an empty query keeps every text in order" {
    const texts = [_][]const u8{ "b", "a" };
    const ranked = try rank(testing.allocator, "", &texts);
    defer {
        deinit(testing.allocator, ranked);
        testing.allocator.free(ranked);
    }
    try testing.expectEqual(@as(usize, 2), ranked.len);
    try testing.expectEqual(@as(u32, 0), ranked[0].index);
}
