//! The workspace's file names in memory, for ⌘P (docs/spec/search.md). Built
//! on its own thread, then kept current by the explorer's watcher: each
//! changed folder is read again, alone, so saving a file does not rescan
//! the workspace.

const std = @import("std");
const c = std.c;
const workspace = @import("../workspace/workspace.zig");
const explorer = @import("../explorer/explorer.zig");
const Walker = @import("walker.zig").Walker;

const watch = explorer.watch;
const paths = workspace.paths;

pub const Index = struct {
    gpa: std.mem.Allocator,
    root: []u8,
    show_hidden: bool,
    mutex: c.pthread_mutex_t = c.PTHREAD_MUTEX_INITIALIZER,
    wake: c.pthread_cond_t = c.PTHREAD_COND_INITIALIZER,
    /// Paths relative to the root, owned.
    files: std.StringArrayHashMapUnmanaged(void) = .empty,
    ready: std.atomic.Value(bool) = .init(false),
    stop: bool = false,
    /// Read by the walk between folders: closing does not wait for a
    /// workspace-sized read to finish (switching away from the home folder
    /// took seconds, 2026-10-19).
    cancelled: std.atomic.Value(bool) = .init(false),
    /// Folders the watcher reported, waiting for the index thread.
    pending: std.ArrayList(Pending) = .empty,
    thread: std.Thread = undefined,
    watcher: ?*watch.Watcher = null,

    const Pending = struct { rel: []u8, subtree: bool };

    /// Starts indexing `root` (inside an authorized directory) in the
    /// background. Queries before it is ready see what was read so far.
    pub fn open(gpa: std.mem.Allocator, registry: *workspace.Registry, root: []const u8, show_hidden: bool) !*Index {
        var buf: paths.Buffer = undefined;
        const real = try registry.resolve(root, &buf);
        if (!paths.isDirectory(real)) return error.NotDirectory;
        const self = try gpa.create(Index);
        errdefer gpa.destroy(self);
        self.* = .{ .gpa = gpa, .root = try gpa.dupe(u8, real), .show_hidden = show_hidden };
        errdefer gpa.free(self.root);
        self.thread = try std.Thread.spawn(.{}, run, .{self});
        self.watcher = watch.Watcher.start(gpa, registry, real, onChanges, self, watch.default_latency_s) catch null;
        return self;
    }

    /// Stops the watcher and the thread, and frees everything.
    pub fn close(self: *Index) void {
        if (self.watcher) |w| w.stop();
        self.cancelled.store(true, .release);
        _ = c.pthread_mutex_lock(&self.mutex);
        self.stop = true;
        _ = c.pthread_cond_signal(&self.wake);
        _ = c.pthread_mutex_unlock(&self.mutex);
        self.thread.join();
        for (self.pending.items) |p| self.gpa.free(p.rel);
        self.pending.deinit(self.gpa);
        for (self.files.keys()) |key| self.gpa.free(key);
        self.files.deinit(self.gpa);
        self.gpa.free(self.root);
        self.gpa.destroy(self);
    }

    pub fn lock(self: *Index) void {
        _ = c.pthread_mutex_lock(&self.mutex);
    }

    pub fn unlock(self: *Index) void {
        _ = c.pthread_mutex_unlock(&self.mutex);
    }

    /// The indexed paths; hold lock() while using them.
    pub fn lockedPaths(self: *Index) []const []const u8 {
        return self.files.keys();
    }

    pub fn count(self: *Index) usize {
        self.lock();
        defer self.unlock();
        return self.files.count();
    }

    fn run(self: *Index) void {
        var walker = Walker.init(self.gpa, self.root, .{ .show_hidden = self.show_hidden, .cancel = &self.cancelled }) catch return;
        defer walker.deinit();
        self.rescan(&walker, "", true);
        self.ready.store(true, .release);
        while (self.nextPending()) |p| {
            defer self.gpa.free(p.rel);
            self.rescan(&walker, p.rel, p.subtree);
        }
    }

    /// Waits for a changed folder; null when closing.
    fn nextPending(self: *Index) ?Pending {
        self.lock();
        defer self.unlock();
        while (!self.stop and self.pending.items.len == 0) _ = c.pthread_cond_wait(&self.wake, &self.mutex);
        if (self.stop) return null;
        return self.pending.orderedRemove(0);
    }

    /// Reads `folder` again: its files always; below it, everything when
    /// `subtree`, otherwise only subfolders that appeared or vanished.
    fn rescan(self: *Index, walker: *Walker, folder: []const u8, subtree: bool) void {
        var arena: std.heap.ArenaAllocator = .init(self.gpa);
        defer arena.deinit();
        const a = arena.allocator();
        const contents = walker.readFolder(a, folder) catch return;
        var fresh: std.ArrayList([]const u8) = .empty;
        for (contents.files) |f| fresh.append(a, f.rel) catch return;
        var new_folders: std.ArrayList([]const u8) = .empty;
        self.lock();
        for (contents.folders) |sub| {
            if (subtree or !self.hasUnder(sub)) new_folders.append(a, sub) catch {};
        }
        self.unlock();
        // New folders are walked without the lock: a big one takes a while.
        const Collect = struct {
            list: *std.ArrayList([]const u8),
            a: std.mem.Allocator,
            fn visit(context: *anyopaque, rel: []const u8, _: u64) bool {
                const s: *@This() = @ptrCast(@alignCast(context));
                s.list.append(s.a, s.a.dupe(u8, rel) catch return false) catch return false;
                return true;
            }
        };
        var collect: Collect = .{ .list = &fresh, .a = a };
        for (new_folders.items) |sub| {
            if (self.cancelled.load(.acquire)) return;
            _ = walker.walk(sub, &collect, Collect.visit) catch {};
        }

        self.lock();
        defer self.unlock();
        self.removeStale(folder, contents.folders, subtree);
        for (fresh.items) |rel| {
            if (self.files.contains(rel)) continue;
            const key = self.gpa.dupe(u8, rel) catch return;
            self.files.put(self.gpa, key, {}) catch self.gpa.free(key);
        }
    }

    /// Drops the folder's own files, and what was below subfolders that
    /// are gone (or everything below, for a subtree rescan). Locked.
    fn removeStale(self: *Index, folder: []const u8, kept_folders: []const []const u8, subtree: bool) void {
        var i: usize = 0;
        while (i < self.files.count()) {
            const key = self.files.keys()[i];
            if (isStale(key, folder, kept_folders, subtree)) {
                self.files.swapRemoveAt(i);
                self.gpa.free(key);
            } else i += 1;
        }
    }

    fn hasUnder(self: *Index, folder: []const u8) bool {
        for (self.files.keys()) |key| {
            if (key.len > folder.len and std.mem.startsWith(u8, key, folder) and key[folder.len] == '/') return true;
        }
        return false;
    }

    fn onChanges(context: ?*anyopaque, changes: [*]const watch.Change, n: usize) callconv(.c) void {
        const self: *Index = @ptrCast(@alignCast(context orelse return));
        self.lock();
        defer self.unlock();
        for (changes[0..n]) |change| {
            const abs = std.mem.span(change.path);
            if (!paths.isWithin(self.root, abs)) continue;
            const rel = std.mem.trimStart(u8, abs[self.root.len..], "/");
            if (std.mem.eql(u8, rel, ".git") or std.mem.startsWith(u8, rel, ".git/")) continue;
            const copy = self.gpa.dupe(u8, rel) catch continue;
            self.pending.append(self.gpa, .{ .rel = copy, .subtree = change.subtree }) catch self.gpa.free(copy);
        }
        _ = c.pthread_cond_signal(&self.wake);
    }
};

/// Whether indexed `key` must go when `folder` is read again.
fn isStale(key: []const u8, folder: []const u8, kept_folders: []const []const u8, subtree: bool) bool {
    const below = if (folder.len == 0) key else blk: {
        if (key.len <= folder.len or !std.mem.startsWith(u8, key, folder) or key[folder.len] != '/') return false;
        break :blk key[folder.len + 1 ..];
    };
    const slash = std.mem.indexOfScalar(u8, below, '/') orelse return true; // the folder's own file
    if (subtree) return true;
    const sub_len = (key.len - below.len) + slash;
    for (kept_folders) |kept| {
        if (std.mem.eql(u8, kept, key[0..sub_len])) return false;
    }
    return true;
}

const testing = std.testing;
const TestDir = @import("../../shared/test_dir.zig").TestDir;

extern "c" fn usleep(microseconds: c_uint) c_int;

fn nowMs() i64 {
    var ts: c.timespec = undefined;
    _ = c.clock_gettime(.MONOTONIC, &ts);
    return @as(i64, ts.sec) * 1000 + @divTrunc(@as(i64, ts.nsec), 1_000_000);
}

fn waitFor(index: *Index, comptime check: fn (*Index) bool) !void {
    var attempts: u32 = 0;
    while (attempts < 250) : (attempts += 1) {
        index.lock();
        const ok = check(index);
        index.unlock();
        if (ok) return;
        _ = usleep(20 * 1000);
    }
    return error.IndexNeverCaughtUp;
}

test "indexes the workspace and follows files created and removed" {
    var dir = try TestDir.init();
    defer dir.deinit();
    try dir.makeDir("core/features/terminal");
    try dir.writeFile("core/features/terminal/render.zig", "");
    try dir.writeFile("README.md", "");
    var registry = workspace.Registry.init(testing.allocator);
    defer registry.deinit();
    _ = try registry.authorize(dir.path());

    const index = try Index.open(testing.allocator, &registry, dir.path(), false);
    defer index.close();
    try waitFor(index, struct {
        fn f(i: *Index) bool {
            return i.files.contains("core/features/terminal/render.zig") and i.files.contains("README.md");
        }
    }.f);
    _ = usleep(200 * 1000);
    try dir.makeDir("core/features/search");
    try dir.writeFile("core/features/search/index.zig", "");
    try waitFor(index, struct {
        fn f(i: *Index) bool {
            return i.files.contains("core/features/search/index.zig");
        }
    }.f);
    try dir.tmp.dir.deleteTree(testing.io, "core/features/terminal");
    try waitFor(index, struct {
        fn f(i: *Index) bool {
            return !i.files.contains("core/features/terminal/render.zig") and i.files.count() == 2;
        }
    }.f);
}

test "closing during the first read does not wait for it" {
    var registry = workspace.Registry.init(testing.allocator);
    defer registry.deinit();
    // A big tree that takes far longer than the limit below to walk.
    _ = try registry.authorize("/usr");
    const index = try Index.open(testing.allocator, &registry, "/usr", true);
    _ = usleep(20 * 1000);
    const before = nowMs();
    index.close();
    try testing.expect(nowMs() - before < 500);
}

test "stale keys after reading a folder again" {
    const kept = [_][]const u8{"src/a"};
    try testing.expect(isStale("src/x.zig", "src", &kept, false));
    try testing.expect(!isStale("src/a/y.zig", "src", &kept, false));
    try testing.expect(isStale("src/gone/y.zig", "src", &kept, false));
    try testing.expect(isStale("src/a/y.zig", "src", &kept, true));
    try testing.expect(!isStale("other/y.zig", "src", &kept, false));
    try testing.expect(!isStale("srcx/y.zig", "src", &kept, false));
    try testing.expect(isStale("top.zig", "", &.{}, false));
}
