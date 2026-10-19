//! Tells the app which folders changed on disk, through FSEvents (macOS).
//! FSEvents already gathers the changes of a short window (latency) into
//! one batch; each batch reaches the app as one callback with every changed
//! folder once. Same thread rule as the terminal's callbacks
//! (terminal/session.zig): they run on the watcher's own queue, must return
//! quickly, and none runs after stop() returns.

const std = @import("std");
const sync = @import("../../shared/sync.zig");
const clock = @import("../../shared/clock.zig");
const dispatch = std.c.dispatch;
const workspace = @import("../workspace/workspace.zig");
const errors = @import("errors.zig");

const paths = workspace.paths;
pub const Error = errors.Error;

/// One changed folder. `subtree`: FSEvents lost detail (dropped events,
/// root moved or deleted), so everything below must be read again.
pub const Change = extern struct {
    path: [*:0]const u8,
    subtree: bool,
};

pub const Callback = *const fn (context: ?*anyopaque, changes: [*]const Change, count: usize) callconv(.c) void;

/// How long FSEvents gathers changes before a batch. Short enough that the
/// tree feels live; long enough that `git checkout` arrives as a few batches.
pub const default_latency_s: f64 = 0.1;

pub const Watcher = struct {
    gpa: std.mem.Allocator,
    stream: *anyopaque,
    queue: dispatch.queue_t,
    callback: Callback,
    context: ?*anyopaque,

    /// Watches the folder `root` (inside an authorized directory) and
    /// everything below it.
    pub fn start(gpa: std.mem.Allocator, registry: *workspace.Registry, root: []const u8, callback: Callback, context: ?*anyopaque, latency_s: f64) Error!*Watcher {
        var buf: paths.Buffer = undefined;
        const real = try registry.resolve(root, &buf);
        if (!paths.isDirectory(real)) return error.NotDirectory;

        const self = try gpa.create(Watcher);
        errdefer gpa.destroy(self);
        const queue = dispatch.queue_create("cadex.explorer.watch", dispatch.QUEUE_SERIAL()) orelse return error.Unexpected;
        errdefer dispatch.release(queue.as_object());
        self.* = .{ .gpa = gpa, .stream = undefined, .queue = queue, .callback = callback, .context = context };
        self.stream = try createStream(self, real, latency_s);
        FSEventStreamSetDispatchQueue(self.stream, queue);
        if (FSEventStreamStart(self.stream) == 0) {
            FSEventStreamInvalidate(self.stream);
            FSEventStreamRelease(self.stream);
            return error.Unexpected;
        }
        return self;
    }

    /// Stops watching and frees the watcher. No callback runs after this.
    pub fn stop(self: *Watcher) void {
        FSEventStreamStop(self.stream);
        FSEventStreamInvalidate(self.stream);
        FSEventStreamRelease(self.stream);
        // A batch may still be running on the queue: wait for it.
        dispatch.sync_f(self.queue, null, noop);
        dispatch.release(self.queue.as_object());
        self.gpa.destroy(self);
    }
};

fn noop(_: ?*anyopaque) callconv(.c) void {}

fn createStream(self: *Watcher, real: []const u8, latency_s: f64) Error!*anyopaque {
    const string = CFStringCreateWithBytes(null, real.ptr, @intCast(real.len), cf_utf8, 0) orelse return error.OutOfMemory;
    defer CFRelease(string);
    const values = [_]?*const anyopaque{string};
    const array = CFArrayCreate(null, &values, 1, &kCFTypeArrayCallBacks) orelse return error.OutOfMemory;
    defer CFRelease(array);
    var context: StreamContext = .{ .info = self };
    return FSEventStreamCreate(null, onEvents, &context, array, event_id_since_now, latency_s, create_flag_watch_root) orelse error.Unexpected;
}

/// Runs on the watcher's queue with one FSEvents batch.
fn onEvents(_: ?*anyopaque, info: ?*anyopaque, count: usize, event_paths: ?*anyopaque, flags: [*]const u32, _: [*]const u64) callconv(.c) void {
    const self: *Watcher = @ptrCast(@alignCast(info orelse return));
    const raw: [*]const [*:0]const u8 = @ptrCast(@alignCast(event_paths orelse return));
    var arena: std.heap.ArenaAllocator = .init(self.gpa);
    defer arena.deinit();
    const changes = collapse(arena.allocator(), raw[0..count], flags[0..count]) catch return;
    if (changes.len > 0) self.callback(self.context, changes.ptr, changes.len);
}

/// Each folder once, without the trailing slash FSEvents adds; `subtree`
/// if any of its events asked for a rescan.
fn collapse(a: std.mem.Allocator, raw: []const [*:0]const u8, flags: []const u32) ![]Change {
    var index: std.StringHashMapUnmanaged(usize) = .empty;
    var changes: std.ArrayList(Change) = .empty;
    for (raw, flags) |p, flag| {
        const span = std.mem.span(p);
        const trimmed = if (span.len > 1) std.mem.trimEnd(u8, span, "/") else span;
        const subtree = flag & rescan_flags != 0;
        if (index.get(trimmed)) |at| {
            changes.items[at].subtree = changes.items[at].subtree or subtree;
            continue;
        }
        const copy = try a.dupeZ(u8, trimmed);
        try index.put(a, copy, changes.items.len);
        try changes.append(a, .{ .path = copy.ptr, .subtree = subtree });
    }
    return changes.items;
}

// CoreFoundation and FSEvents (CoreServices), declared here because Zig's
// libc bindings do not have them. Constants from FSEvents.h.
const cf_utf8: u32 = 0x08000100;
const event_id_since_now: u64 = 0xFFFFFFFFFFFFFFFF;
const create_flag_watch_root: u32 = 0x4;
/// MustScanSubDirs, UserDropped, KernelDropped, RootChanged.
const rescan_flags: u32 = 0x1 | 0x2 | 0x4 | 0x20;

const CFArrayCallBacks = extern struct {
    version: isize,
    retain: ?*const anyopaque,
    release: ?*const anyopaque,
    copy_description: ?*const anyopaque,
    equal: ?*const anyopaque,
};
const StreamContext = extern struct {
    version: isize = 0,
    info: ?*anyopaque,
    retain: ?*const anyopaque = null,
    release: ?*const anyopaque = null,
    copy_description: ?*const anyopaque = null,
};
const StreamCallback = *const fn (?*anyopaque, ?*anyopaque, usize, ?*anyopaque, [*]const u32, [*]const u64) callconv(.c) void;

extern "c" const kCFTypeArrayCallBacks: CFArrayCallBacks;
extern "c" fn CFStringCreateWithBytes(allocator: ?*anyopaque, bytes: [*]const u8, len: isize, encoding: u32, external: u8) ?*const anyopaque;
extern "c" fn CFArrayCreate(allocator: ?*anyopaque, values: [*]const ?*const anyopaque, count: isize, callbacks: *const CFArrayCallBacks) ?*const anyopaque;
extern "c" fn CFRelease(object: ?*const anyopaque) void;
extern "c" fn FSEventStreamCreate(allocator: ?*anyopaque, callback: StreamCallback, context: *StreamContext, paths_to_watch: ?*const anyopaque, since_when: u64, latency: f64, flags: u32) ?*anyopaque;
extern "c" fn FSEventStreamSetDispatchQueue(stream: *anyopaque, queue: ?dispatch.queue_t) void;
extern "c" fn FSEventStreamStart(stream: *anyopaque) u8;
extern "c" fn FSEventStreamStop(stream: *anyopaque) void;
extern "c" fn FSEventStreamInvalidate(stream: *anyopaque) void;
extern "c" fn FSEventStreamRelease(stream: *anyopaque) void;

const testing = std.testing;
const TestDir = @import("../../shared/test_dir.zig").TestDir;

const Seen = struct {
    mutex: sync.Mutex = .{},
    text: [8192]u8 = undefined,
    len: usize = 0,

    fn record(context: ?*anyopaque, changes: [*]const Change, count: usize) callconv(.c) void {
        const self: *Seen = @ptrCast(@alignCast(context.?));
        self.mutex.lock();
        defer self.mutex.unlock();
        for (changes[0..count]) |change| {
            const p = std.mem.span(change.path);
            if (self.len + p.len + 1 > self.text.len) return;
            @memcpy(self.text[self.len..][0..p.len], p);
            self.text[self.len + p.len] = '\n';
            self.len += p.len + 1;
        }
    }

    fn clear(self: *Seen) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.len = 0;
    }

    /// Polls for ~5 s until `line` was reported.
    fn waitFor(self: *Seen, line: []const u8) !void {
        var attempts: u32 = 0;
        while (attempts < 250) : (attempts += 1) {
            self.mutex.lock();
            const found = std.mem.indexOf(u8, self.text[0..self.len], line) != null;
            self.mutex.unlock();
            if (found) return;
            clock.sleepMs(20);
        }
        return error.ChangeNeverReported;
    }
};

test "reports the folder where a file was created, then removed" {
    var dir = try TestDir.init();
    defer dir.deinit();
    try dir.makeDir("sub");
    var registry = workspace.Registry.init(testing.allocator);
    defer registry.deinit();
    _ = try registry.authorize(dir.path());

    var seen: Seen = .{};
    const watcher = try Watcher.start(testing.allocator, &registry, dir.path(), Seen.record, &seen, 0.05);
    defer watcher.stop();
    // FSEvents only reports what happens after the stream is running.
    clock.sleepMs(200);

    try dir.writeFile("sub/new.txt", "x");
    var line: [1024]u8 = undefined;
    const sub = try std.fmt.bufPrint(&line, "{s}/sub\n", .{dir.path()});
    try seen.waitFor(sub);
    seen.clear();
    try dir.tmp.dir.deleteFile(testing.io, "sub/new.txt");
    try seen.waitFor(sub);
}

test "collapse keeps each folder once and merges the rescan flag" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const raw = [_][*:0]const u8{ "/a/b/", "/a/", "/a/b/" };
    const flags = [_]u32{ 0, 0, 0x1 };
    const changes = try collapse(arena.allocator(), &raw, &flags);
    try testing.expectEqual(@as(usize, 2), changes.len);
    try testing.expectEqualStrings("/a/b", std.mem.span(changes[0].path));
    try testing.expect(changes[0].subtree);
    try testing.expectEqualStrings("/a", std.mem.span(changes[1].path));
    try testing.expect(!changes[1].subtree);
}

test "watching outside the workspace is refused" {
    var registry = workspace.Registry.init(testing.allocator);
    defer registry.deinit();
    var seen: Seen = .{};
    try testing.expectError(error.Outside, Watcher.start(testing.allocator, &registry, "/private/tmp", Seen.record, &seen, 0.05));
}
