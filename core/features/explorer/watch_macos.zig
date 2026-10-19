//! Watching the disk on the Mac: FSEvents, on a dispatch queue of its own.
//! FSEvents already gathers the changes of the latency window into one
//! batch. The interface is `watch.zig`.

const std = @import("std");
const dispatch = std.c.dispatch;
const workspace = @import("../workspace/workspace.zig");
const errors = @import("errors.zig");
const watch = @import("watch.zig");

const paths = workspace.paths;
const Error = errors.Error;
const Change = watch.Change;
const Callback = watch.Callback;

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
