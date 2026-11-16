//! The hook queue: an event the engine did not take in time waits in
//! `<memory dir>/spool/` and the engine replays it when it starts
//! (core/features/memory/server/src/spool.rs, which documents the format).
//! One file per request, named by the time so the names sort in order,
//! written under a `.tmp` name and renamed so the engine never reads half
//! of one. Plan 22 phase C: "a fila guarda e esvazia quando ele volta, sem
//! perder evento".

const std = @import("std");
const fs = @import("../../shared/fs.zig");
const c = std.c;

extern "c" fn arc4random() u32;

/// The file's content: `{"v":1,"path":…,"body":…}`, the body as a string
/// (the hook's JSON as it came, even when it is not JSON).
pub fn record(gpa: std.mem.Allocator, target: []const u8, body: []const u8) ![]u8 {
    return std.fmt.allocPrint(gpa, "{{\"v\":1,\"path\":{f},\"body\":{f}}}\n", .{
        std.json.fmt(target, .{}), std.json.fmt(body, .{}),
    });
}

/// `<unix ms, 13 digits>-<8 hex>.json`: sortable by time, unique enough for
/// hooks of one person's sessions written in the same millisecond.
pub fn fileName(out: []u8, unix_ms: i64, random: u32) ![]const u8 {
    return std.fmt.bufPrint(out, "{d:0>13}-{x:0>8}.json", .{ @as(u64, @intCast(@max(unix_ms, 0))), random });
}

fn unixMs() i64 {
    var ts: c.timespec = undefined;
    _ = c.clock_gettime(.REALTIME, &ts);
    return @as(i64, ts.sec) * 1000 + @divTrunc(@as(i64, ts.nsec), 1_000_000);
}

/// A folder only this user reads: the queue holds prompts and tool output.
fn ensureFolder(path: []const u8) bool {
    if (fs.isDirectory(path)) return true;
    var z: fs.Buffer = undefined;
    if (path.len >= z.len) return false;
    @memcpy(z[0..path.len], path);
    z[path.len] = 0;
    _ = c.mkdir(@ptrCast(&z), 0o700);
    return fs.isDirectory(path);
}

/// Queue one request in `<memory_dir>/spool/`.
pub fn write(gpa: std.mem.Allocator, memory_dir: []const u8, target: []const u8, body: []const u8) !void {
    if (!ensureFolder(memory_dir)) return error.NoFolder;
    var dir_buf: fs.Buffer = undefined;
    const dir = try fs.join(&dir_buf, memory_dir, "spool");
    if (!ensureFolder(dir)) return error.NoFolder;
    var name_buf: [64]u8 = undefined;
    const name = try fileName(&name_buf, unixMs(), arc4random());
    var path_buf: fs.Buffer = undefined;
    const path = try fs.join(&path_buf, dir, name);
    var tmp_buf: fs.Buffer = undefined;
    const tmp = try std.fmt.bufPrint(&tmp_buf, "{s}.tmp", .{path});
    const data = try record(gpa, target, body);
    defer gpa.free(data);
    try fs.writeThenRename(tmp, path, data, 0o600);
}

const testing = std.testing;

test "a queued request is the path and the body as text" {
    const data = try record(testing.allocator, "/hook?event=stop&x=1", "{\"a\":\"b\"}\n");
    defer testing.allocator.free(data);
    try testing.expectEqualStrings("{\"v\":1,\"path\":\"/hook?event=stop&x=1\",\"body\":\"{\\\"a\\\":\\\"b\\\"}\\n\"}\n", data);
}

test "file names sort by time" {
    var a: [64]u8 = undefined;
    var b: [64]u8 = undefined;
    const first = try fileName(&a, 999, 0xffffffff);
    const second = try fileName(&b, 1_700_000_000_000, 1);
    try testing.expectEqualStrings("0000000000999-ffffffff.json", first);
    try testing.expectEqualStrings("1700000000000-00000001.json", second);
    try testing.expect(std.mem.order(u8, first, second) == .lt);
}

test "write leaves one finished file in a private folder" {
    var tmp = try @import("../../shared/test_dir.zig").TestDir.init();
    defer tmp.deinit();
    var mem_buf: fs.Buffer = undefined;
    const memory_dir = try fs.join(&mem_buf, tmp.path(), "memory");
    try write(testing.allocator, memory_dir, "/hook?event=stop", "{}");
    var spool_buf: fs.Buffer = undefined;
    const spool_dir = try fs.join(&spool_buf, memory_dir, "spool");
    try testing.expectEqual(@as(u32, 0o700), fs.info(spool_dir, true).?.mode & 0o777);
    var reader = try fs.DirReader.open(spool_dir);
    defer reader.close();
    var count: usize = 0;
    while (reader.next()) |entry| {
        try testing.expect(std.mem.endsWith(u8, entry.name, ".json"));
        count += 1;
    }
    try testing.expectEqual(@as(usize, 1), count);
}
