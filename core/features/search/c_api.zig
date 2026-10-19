//! The search feature's part of the C API (include/cadex.h).

const std = @import("std");
const status = @import("../../status.zig");
const search = @import("search.zig");

/// Buffers handed to the app come from malloc, freed with
/// cadex_fuzzy_result_free.
const gpa = std.heap.c_allocator;

pub const Text = extern struct { text: ?[*]const u8, len: usize };

pub const Match = extern struct {
    index: u32,
    score: i32,
    positions_offset: u32,
    positions_count: u32,
};

pub const Result = extern struct {
    matches: ?[*]Match,
    count: usize,
    /// Byte offsets of every match, each match's slice given by
    /// positions_offset and positions_count.
    positions: ?[*]u32,
};

/// Ranks `texts` against `query`; fills `out`. Free with cadex_fuzzy_result_free.
pub export fn cadex_fuzzy_rank(
    query: ?[*]const u8,
    query_len: usize,
    texts: ?[*]const Text,
    count: usize,
    out: ?*Result,
) callconv(.c) status.Code {
    const result = out orelse return status.invalid_argument;
    result.* = .{ .matches = null, .count = 0, .positions = null };
    const q: []const u8 = if (query_len == 0) "" else (query orelse return status.invalid_argument)[0..query_len];
    if (count == 0) return status.ok;
    const list = texts orelse return status.invalid_argument;

    const slices = gpa.alloc([]const u8, count) catch return status.out_of_memory;
    defer gpa.free(slices);
    for (slices, 0..) |*slice, i| {
        const t = list[i];
        slice.* = if (t.len == 0) "" else (t.text orelse return status.invalid_argument)[0..t.len];
    }
    const ranked = search.rank.rank(gpa, q, slices) catch |err| return status.fromError(err);
    defer {
        search.rank.deinit(gpa, ranked);
        gpa.free(ranked);
    }
    if (ranked.len == 0) return status.ok;
    return flatten(ranked, result);
}

fn flatten(ranked: []const search.rank.Ranked, result: *Result) status.Code {
    var total: usize = 0;
    for (ranked) |r| total += r.positions.len;
    const matches = gpa.alloc(Match, ranked.len) catch return status.out_of_memory;
    // malloc(0) may return NULL: keep at least one slot.
    const positions = gpa.alloc(u32, @max(total, 1)) catch {
        gpa.free(matches);
        return status.out_of_memory;
    };
    var at: usize = 0;
    for (ranked, matches) |r, *m| {
        m.* = .{ .index = r.index, .score = r.score, .positions_offset = @intCast(at), .positions_count = @intCast(r.positions.len) };
        @memcpy(positions[at..][0..r.positions.len], r.positions);
        at += r.positions.len;
    }
    result.* = .{ .matches = matches.ptr, .count = matches.len, .positions = positions.ptr };
    return status.ok;
}

pub export fn cadex_fuzzy_result_free(result: ?*Result) callconv(.c) void {
    const r = result orelse return;
    if (r.matches) |m| gpa.free(m[0..r.count]);
    if (r.positions) |p| std.c.free(p);
    r.* = .{ .matches = null, .count = 0, .positions = null };
}

test "ranks through the C API and frees" {
    const texts = [_]Text{ .{ .text = "Abrir nova janela", .len = 17 }, .{ .text = "Nova aba", .len = 8 } };
    var result: Result = undefined;
    try std.testing.expectEqual(status.ok, cadex_fuzzy_rank("na", 2, &texts, texts.len, &result));
    defer cadex_fuzzy_result_free(&result);
    try std.testing.expectEqual(@as(usize, 2), result.count);
    try std.testing.expectEqual(@as(u32, 1), result.matches.?[0].index);
    try std.testing.expectEqual(@as(u32, 2), result.matches.?[0].positions_count);
}
