//! Content search on real folders: results, limits, and cancellation.

const std = @import("std");
const sync = @import("../../shared/sync.zig");
const clock = @import("../../shared/clock.zig");
const testing = std.testing;
const workspace = @import("../workspace/workspace.zig");
const content = @import("content.zig");
const TestDir = @import("../../shared/test_dir.zig").TestDir;

/// Collects what the callbacks deliver, from the search thread.
const Seen = struct {
    mutex: sync.Mutex = .{},
    lines: std.ArrayList([]u8) = .empty,
    done: std.atomic.Value(bool) = .init(false),
    truncated: bool = false,

    fn onHits(context: ?*anyopaque, hits: [*]const content.Hit, count: usize) callconv(.c) void {
        const self: *Seen = @ptrCast(@alignCast(context.?));
        self.mutex.lock();
        defer self.mutex.unlock();
        for (hits[0..count]) |h| {
            const text = h.text[0..h.text_len];
            const line = std.fmt.allocPrint(testing.allocator, "{s}:{d}:{d}:{s}", .{
                std.mem.span(h.path), h.line, h.column, text[h.match_start..][0..h.match_len],
            }) catch return;
            self.lines.append(testing.allocator, line) catch testing.allocator.free(line);
        }
    }

    fn onDone(context: ?*anyopaque, truncated: bool, _: u32) callconv(.c) void {
        const self: *Seen = @ptrCast(@alignCast(context.?));
        self.truncated = truncated;
        self.done.store(true, .release);
    }

    fn wait(self: *Seen) !void {
        var attempts: u32 = 0;
        while (!self.done.load(.acquire)) : (attempts += 1) {
            if (attempts > 250) return error.SearchNeverFinished;
            clock.sleepMs(20);
        }
    }

    fn deinit(self: *Seen) void {
        for (self.lines.items) |l| testing.allocator.free(l);
        self.lines.deinit(testing.allocator);
    }

    fn callbacks(self: *Seen) content.Callbacks {
        return .{ .context = self, .on_hits = onHits, .on_done = onDone };
    }
};

fn fixture(dir: *TestDir, registry: *workspace.Registry) !void {
    try dir.writeFile(".gitignore", "zig-out/\n");
    try dir.makeDir("core/features");
    try dir.writeFile("core/features/model.zig", "// uses libghostty-vt\nconst vt = @import(\"ghostty-vt\");\n");
    try dir.writeFile("README.md", "# Cadex\n\nBuilt on LibGhostty.\n");
    try dir.makeDir("zig-out");
    try dir.writeFile("zig-out/copy.zig", "libghostty\n");
    try dir.writeFile("image.png", "PNG\x00libghostty");
    _ = try registry.authorize(dir.path());
}

test "finds text in files, one hit per line, skipping ignored and binary files" {
    var dir = try TestDir.init();
    defer dir.deinit();
    var registry = workspace.Registry.init(testing.allocator);
    defer registry.deinit();
    try fixture(&dir, &registry);

    var seen: Seen = .{};
    defer seen.deinit();
    const search = try content.Search.start(testing.allocator, &registry, dir.path(), "libghostty", .{}, seen.callbacks());
    try seen.wait();
    search.cancel();
    const want = [_][]const u8{ "README.md:3:9:LibGhostty", "core/features/model.zig:1:8:libghostty" };
    try testing.expectEqual(want.len, seen.lines.items.len);
    for (want, seen.lines.items) |w, got| try testing.expectEqualStrings(w, got);
    try testing.expect(!seen.truncated);
}

test "regex search and the result limit" {
    var dir = try TestDir.init();
    defer dir.deinit();
    var registry = workspace.Registry.init(testing.allocator);
    defer registry.deinit();
    try fixture(&dir, &registry);

    var seen: Seen = .{};
    defer seen.deinit();
    const search = try content.Search.start(testing.allocator, &registry, dir.path(), "ghostty(-vt)?\"", .{ .regex = true }, seen.callbacks());
    try seen.wait();
    search.cancel();
    try testing.expectEqual(@as(usize, 1), seen.lines.items.len);
    try testing.expectEqualStrings("core/features/model.zig:2:20:ghostty-vt\"", seen.lines.items[0]);

    var limited: Seen = .{};
    defer limited.deinit();
    const capped = try content.Search.start(testing.allocator, &registry, dir.path(), "e", .{ .max_results = 2 }, limited.callbacks());
    try limited.wait();
    capped.cancel();
    try testing.expectEqual(@as(usize, 2), limited.lines.items.len);
    try testing.expect(limited.truncated);
}

test "a cancelled search delivers nothing afterwards" {
    var dir = try TestDir.init();
    defer dir.deinit();
    var registry = workspace.Registry.init(testing.allocator);
    defer registry.deinit();
    // Enough files that the search is still running when cancelled.
    var name: [64]u8 = undefined;
    for (0..400) |i| try dir.writeFile(try std.fmt.bufPrint(&name, "f{d}.txt", .{i}), "needle\n" ** 50);
    _ = try registry.authorize(dir.path());

    var seen: Seen = .{};
    defer seen.deinit();
    const search = try content.Search.start(testing.allocator, &registry, dir.path(), "needle", .{}, seen.callbacks());
    search.cancel();
    seen.mutex.lock();
    const after_cancel = seen.lines.items.len;
    seen.mutex.unlock();
    clock.sleepMs(100);
    try testing.expectEqual(after_cancel, seen.lines.items.len);
}

test "an invalid regex fails at start; outside the workspace is refused" {
    var registry = workspace.Registry.init(testing.allocator);
    defer registry.deinit();
    _ = try registry.authorize("/usr/share");
    var seen: Seen = .{};
    defer seen.deinit();
    try testing.expectError(error.InvalidPattern, content.Search.start(testing.allocator, &registry, "/usr/share", "(", .{ .regex = true }, seen.callbacks()));
    try testing.expectError(error.Outside, content.Search.start(testing.allocator, &registry, "/usr/lib", "x", .{}, seen.callbacks()));
}

test "snippets cut long lines around the match" {
    const line = "\t\tconst value = compute();";
    const cut = content.snippet(line, 8, 5);
    try testing.expectEqualStrings("const value = compute();", line[cut.start..cut.end]);
    const long = "x" ** 500 ++ "needle" ++ "y" ** 500;
    const around = content.snippet(long, 500, 6);
    try testing.expect(around.end - around.start <= content.snippet_max);
    try testing.expect(around.start <= 500 and around.end >= 506);
}
