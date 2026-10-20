//! The workspace's file names in memory, for ⌘P (docs/spec/search.md). Built
//! on its own thread, then kept current by the explorer's watcher: each
//! changed folder is read again, alone, so saving a file does not rescan
//! the workspace.

const std = @import("std");
const sync = @import("../../shared/sync.zig");
const clock = @import("../../shared/clock.zig");
const c = std.c;
const workspace = @import("../workspace/workspace.zig");
const explorer = @import("../explorer/explorer.zig");
const Walker = @import("walker.zig").Walker;
const nearby = @import("nearby.zig");

const watch = explorer.watch;
const paths = workspace.paths;

/// How many file names ⌘P keeps: far more than a project has, and spent
/// near the focus first, so a home folder keeps the folder in use (a blind
/// limit of 300 000 held 267 MB, measured 2026-10-20).
pub const file_budget = 100_000;

pub const Index = struct {
    gpa: std.mem.Allocator,
    registry: *workspace.Registry,
    root: []u8,
    show_hidden: bool,
    /// Nothing is read until the first query (start): a workspace nobody
    /// searches costs nothing.
    started: bool = false,
    /// Where the budget is spent first, relative to the root (the focused
    /// terminal's folder). Guarded by the mutex.
    focus: []u8 = &.{},
    /// The folders read completely; with the budget spent, what is outside
    /// them is left out, and changes there are ignored. Guarded.
    covered: nearby.Covered,
    truncated: std.atomic.Value(bool) = .init(false),
    /// The focus moved outside `covered`: read again from it.
    refocus: bool = false,
    mutex: sync.Mutex = .{},
    wake: sync.Condition = .{},
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
        self.* = .{ .gpa = gpa, .registry = registry, .root = try gpa.dupe(u8, real), .show_hidden = show_hidden, .covered = .{ .gpa = gpa } };
        return self;
    }

    /// Starts reading, once: the first query calls it.
    pub fn start(self: *Index) void {
        self.lock();
        defer self.unlock();
        if (self.started) return;
        self.thread = std.Thread.spawn(.{}, run, .{self}) catch return;
        self.started = true;
        self.watcher = watch.Watcher.start(self.gpa, self.registry, self.root, onChanges, self, watch.default_latency_s) catch null;
    }

    /// The folder the user is in (absolute); outside the root, the root.
    /// A focus outside what was read makes the index read again from it.
    pub fn setFocus(self: *Index, folder: []const u8) void {
        const rel = if (paths.isWithin(self.root, folder)) std.mem.trim(u8, folder[self.root.len..], "/\\") else "";
        self.lock();
        defer self.unlock();
        if (std.mem.eql(u8, rel, self.focus)) return;
        const copy = self.gpa.dupe(u8, rel) catch return;
        // Relative paths use '/' on every system (the walker's).
        std.mem.replaceScalar(u8, copy, '\\', '/');
        self.gpa.free(self.focus);
        self.focus = copy;
        if (self.started and self.truncated.load(.acquire) and !self.covered.contains(rel)) {
            self.refocus = true;
            self.wake.signal();
        }
    }

    /// Stops the watcher and the thread, and frees everything.
    pub fn close(self: *Index) void {
        if (self.watcher) |w| w.stop();
        self.cancelled.store(true, .release);
        self.mutex.lock();
        self.stop = true;
        self.wake.signal();
        const running = self.started;
        self.mutex.unlock();
        if (running) self.thread.join();
        self.gpa.free(self.focus);
        self.covered.deinit();
        for (self.pending.items) |p| self.gpa.free(p.rel);
        self.pending.deinit(self.gpa);
        for (self.files.keys()) |key| self.gpa.free(key);
        self.files.deinit(self.gpa);
        self.gpa.free(self.root);
        self.gpa.destroy(self);
    }

    pub fn lock(self: *Index) void {
        self.mutex.lock();
    }

    pub fn unlock(self: *Index) void {
        self.mutex.unlock();
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
        var walker = Walker.init(self.gpa, self.root, .{ .show_hidden = self.show_hidden, .cancel = &self.cancelled, .limit = file_budget }) catch return;
        defer walker.deinit();
        self.build(&walker);
        self.ready.store(true, .release);
        while (self.nextWork()) |work| switch (work) {
            .rebuild => self.build(&walker),
            .folder => |p| {
                defer self.gpa.free(p.rel);
                self.rescan(&walker, p.rel, p.subtree);
            },
        };
    }

    const Work = union(enum) { rebuild, folder: Pending };

    /// Waits for a refocus or a changed folder; null when closing.
    fn nextWork(self: *Index) ?Work {
        self.lock();
        defer self.unlock();
        while (!self.stop and !self.refocus and self.pending.items.len == 0) self.wake.wait(&self.mutex);
        if (self.stop) return null;
        if (self.refocus) {
            self.refocus = false;
            return .rebuild;
        }
        return .{ .folder = self.pending.orderedRemove(0) };
    }

    /// Reads the workspace from the focus outward, up to the budget,
    /// replacing what was there.
    fn build(self: *Index, walker: *Walker) void {
        self.lock();
        const focus = self.gpa.dupe(u8, self.focus) catch {
            self.unlock();
            return;
        };
        for (self.files.keys()) |key| self.gpa.free(key);
        self.files.clearRetainingCapacity();
        self.covered.clear();
        self.unlock();
        defer self.gpa.free(focus);
        const Insert = struct {
            fn visit(context: *anyopaque, rel: []const u8, _: u64) bool {
                const index: *Index = @ptrCast(@alignCast(context));
                index.lock();
                defer index.unlock();
                const key = index.gpa.dupe(u8, rel) catch return false;
                index.files.put(index.gpa, key, {}) catch index.gpa.free(key);
                return !index.cancelled.load(.acquire);
            }
        };
        walker.count = 0;
        var covered: nearby.Covered = .{ .gpa = self.gpa };
        nearby.walk(walker, focus, self, Insert.visit, &covered) catch {};
        self.lock();
        defer self.unlock();
        self.covered.deinit();
        self.covered = covered;
        self.truncated.store(!covered.all, .release);
    }

    /// Reads `folder` again: its files always; below it, everything when
    /// `subtree`, otherwise only subfolders that appeared or vanished.
    fn rescan(self: *Index, walker: *Walker, folder: []const u8, subtree: bool) void {
        var arena: std.heap.ArenaAllocator = .init(self.gpa);
        defer arena.deinit();
        const a = arena.allocator();
        // The budget counts what the index keeps.
        self.lock();
        walker.count = self.files.count();
        self.unlock();
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
            // Outside what the budget covers, changes do not matter.
            if (self.truncated.load(.acquire) and !self.covered.contains(rel)) continue;
            const copy = self.gpa.dupe(u8, rel) catch continue;
            self.pending.append(self.gpa, .{ .rel = copy, .subtree = change.subtree }) catch self.gpa.free(copy);
        }
        self.wake.signal();
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

fn waitFor(index: *Index, comptime check: fn (*Index) bool) !void {
    var attempts: u32 = 0;
    while (attempts < 250) : (attempts += 1) {
        index.lock();
        const ok = check(index);
        index.unlock();
        if (ok) return;
        clock.sleepMs(20);
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
    index.start();
    try waitFor(index, struct {
        fn f(i: *Index) bool {
            return i.files.contains("core/features/terminal/render.zig") and i.files.contains("README.md");
        }
    }.f);
    clock.sleepMs(200);
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
    index.start();
    clock.sleepMs(20);
    const before = clock.monotonicMs();
    index.close();
    try testing.expect(clock.monotonicMs() - before < 500);
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
