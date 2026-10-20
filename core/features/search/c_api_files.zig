//! File search (⌘P) in the C API (include/cadex.h): the name index and its
//! ranking.

const std = @import("std");
const clock = @import("../../shared/clock.zig");
const status = @import("../../status.zig");
const workspace = @import("../workspace/workspace.zig");
const Index = @import("index.zig").Index;
const files = @import("files.zig");

/// Buffers handed to the app come from malloc, freed with
/// cadex_search_files_result_free.
const gpa = std.heap.c_allocator;

pub const FileMatch = extern struct {
    /// Into FilesResult.paths; relative to the index root, not NUL-terminated.
    path_offset: u32,
    path_len: u32,
    score: i32,
    positions_offset: u32,
    positions_count: u32,
};

pub const FilesResult = extern struct {
    matches: ?[*]FileMatch,
    count: usize,
    paths: ?[*]u8,
    /// Byte offsets in each path of the matched characters.
    positions: ?[*]u32,
};

pub export fn cadex_search_index_open(root: ?[*:0]const u8, show_hidden: bool, out: ?*?*Index) callconv(.c) status.Code {
    const result = out orelse return status.invalid_argument;
    result.* = null;
    const p = std.mem.span(root orelse return status.invalid_argument);
    result.* = Index.open(gpa, workspace.registry(), p, show_hidden) catch |err| return status.fromError(err);
    return status.ok;
}

pub export fn cadex_search_index_close(index: ?*Index) callconv(.c) void {
    if (index) |i| i.close();
}

/// Files indexed so far, and whether the first full read is done. Starts
/// the reading if nothing asked before (the index is lazy).
pub export fn cadex_search_index_count(index: ?*Index, ready: ?*bool) callconv(.c) usize {
    const i = index orelse return 0;
    i.start();
    if (ready) |r| r.* = i.ready.load(.acquire);
    return i.count();
}

/// The folder the user is in (absolute, e.g. the focused terminal's): the
/// index spends its budget there first, and reads again from it when it
/// was left out.
pub export fn cadex_search_index_focus(index: ?*Index, folder: ?[*:0]const u8) callconv(.c) void {
    const i = index orelse return;
    i.setFocus(std.mem.span(folder orelse return));
}

/// Whether the workspace was too big to read whole: what is far from the
/// focus was left out.
pub export fn cadex_search_index_partial(index: ?*Index) callconv(.c) bool {
    const i = index orelse return false;
    return i.truncated.load(.acquire);
}

pub export fn cadex_search_files(index: ?*Index, query: ?[*]const u8, query_len: usize, limit: usize, out: ?*FilesResult) callconv(.c) status.Code {
    const result = out orelse return status.invalid_argument;
    result.* = .{ .matches = null, .count = 0, .paths = null, .positions = null };
    const i = index orelse return status.invalid_argument;
    const q: []const u8 = if (query_len == 0) "" else (query orelse return status.invalid_argument)[0..query_len];
    i.start();
    i.lock();
    defer i.unlock();
    const list = i.lockedPaths();
    const hits = files.rank(gpa, q, list, limit) catch |err| return status.fromError(err);
    defer {
        files.deinit(gpa, hits);
        gpa.free(hits);
    }
    return flatten(hits, list, result);
}

fn flatten(hits: []const files.Hit, list: []const []const u8, result: *FilesResult) status.Code {
    var path_total: usize = 0;
    var position_total: usize = 0;
    for (hits) |h| {
        path_total += list[h.index].len;
        position_total += h.positions.len;
    }
    // malloc(0) may return NULL: keep at least one slot of each.
    const matches = gpa.alloc(FileMatch, @max(hits.len, 1)) catch return status.out_of_memory;
    const names = gpa.alloc(u8, @max(path_total, 1)) catch {
        gpa.free(matches);
        return status.out_of_memory;
    };
    const positions = gpa.alloc(u32, @max(position_total, 1)) catch {
        gpa.free(matches);
        gpa.free(names);
        return status.out_of_memory;
    };
    var at_path: usize = 0;
    var at_pos: usize = 0;
    for (hits, matches[0..hits.len]) |h, *m| {
        const path = list[h.index];
        m.* = .{
            .path_offset = @intCast(at_path),
            .path_len = @intCast(path.len),
            .score = h.score,
            .positions_offset = @intCast(at_pos),
            .positions_count = @intCast(h.positions.len),
        };
        @memcpy(names[at_path..][0..path.len], path);
        @memcpy(positions[at_pos..][0..h.positions.len], h.positions);
        at_path += path.len;
        at_pos += h.positions.len;
    }
    result.* = .{ .matches = matches.ptr, .count = hits.len, .paths = names.ptr, .positions = positions.ptr };
    return status.ok;
}

pub export fn cadex_search_files_result_free(result: ?*FilesResult) callconv(.c) void {
    const r = result orelse return;
    std.c.free(r.matches);
    std.c.free(r.paths);
    std.c.free(r.positions);
    r.* = .{ .matches = null, .count = 0, .paths = null, .positions = null };
}

const testing = std.testing;
const TestDir = @import("../../shared/test_dir.zig").TestDir;

test "indexes and ranks through the C API" {
    var dir = try TestDir.init();
    defer dir.deinit();
    try dir.makeDir("core/features/terminal");
    try dir.writeFile("core/features/terminal/render.zig", "");
    try dir.writeFile("Makefile", "");
    _ = try workspace.registry().authorize(dir.path());

    var index: ?*Index = null;
    try testing.expectEqual(status.ok, cadex_search_index_open((try dir.join("")).ptr, false, &index));
    defer cadex_search_index_close(index);
    var ready = false;
    var attempts: u32 = 0;
    while (!ready or cadex_search_index_count(index, &ready) < 2) : (attempts += 1) {
        if (attempts > 250) return error.IndexNeverReady;
        _ = cadex_search_index_count(index, &ready);
        clock.sleepMs(20);
    }
    var result: FilesResult = undefined;
    try testing.expectEqual(status.ok, cadex_search_files(index, "render", 6, 10, &result));
    defer cadex_search_files_result_free(&result);
    try testing.expectEqual(@as(usize, 1), result.count);
    const m = result.matches.?[0];
    try testing.expectEqualStrings("core/features/terminal/render.zig", result.paths.?[m.path_offset..][0..m.path_len]);
    try testing.expectEqual(@as(u32, 6), m.positions_count);
}
