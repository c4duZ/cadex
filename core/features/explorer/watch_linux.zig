//! Watching the disk on Linux: inotify, one watch per folder, on a thread
//! of its own. Changes gather for the latency window after the first one,
//! then go to the app as one batch with each folder once, like FSEvents on
//! the Mac and ReadDirectoryChangesW on Windows. The interface is
//! `watch.zig`.

const std = @import("std");
const c = std.c;
const clock = @import("../../shared/clock.zig");
const fs = @import("../../shared/fs.zig");
const workspace = @import("../workspace/workspace.zig");
const errors = @import("errors.zig");
const watch = @import("watch.zig");

const paths = workspace.paths;
const Error = errors.Error;
const Change = watch.Change;
const Callback = watch.Callback;

// inotify(7). The request is a bit in an i32; the values are the same on
// every Linux architecture.
const IN_MODIFY: u32 = 0x00000002;
const IN_ATTRIB: u32 = 0x00000004;
const IN_MOVED_FROM: u32 = 0x00000040;
const IN_MOVED_TO: u32 = 0x00000080;
const IN_CREATE: u32 = 0x00000100;
const IN_DELETE: u32 = 0x00000200;
const IN_DELETE_SELF: u32 = 0x00000400;
const IN_MOVE_SELF: u32 = 0x00000800;
const IN_Q_OVERFLOW: u32 = 0x00004000;
const IN_IGNORED: u32 = 0x00008000;
const IN_ONLYDIR: u32 = 0x01000000;
const IN_ISDIR: u32 = 0x40000000;

/// Names, sizes and in-place writes all matter to the tree; IN_MODIFY is
/// the one that catches an editor saving over a file.
const watch_mask = IN_MODIFY | IN_ATTRIB | IN_CREATE | IN_DELETE |
    IN_MOVED_FROM | IN_MOVED_TO | IN_DELETE_SELF | IN_MOVE_SELF | IN_ONLYDIR;

const Event = extern struct {
    wd: i32,
    mask: u32,
    cookie: u32,
    len: u32,
};

extern "c" fn inotify_init1(flags: i32) c_int;
extern "c" fn inotify_add_watch(fd: c_int, path: [*:0]const u8, mask: u32) c_int;

pub const Watcher = struct {
    gpa: std.mem.Allocator,
    root: []u8,
    fd: c_int,
    thread: std.Thread = undefined,
    stop_flag: std.atomic.Value(bool) = .init(false),
    callback: Callback,
    context: ?*anyopaque,
    latency_ms: u32,
    /// watch descriptor -> folder. Only the reader thread looks things up;
    /// stop frees it after join, so no lock is needed. The paths live in
    /// `arena`, released in one step (one free per path was ~480 ms on /usr).
    watches: std.AutoHashMapUnmanaged(c_int, []u8) = .empty,
    arena: std.heap.ArenaAllocator,

    /// Watches the folder `root` (inside an authorized directory) and
    /// everything below it.
    pub fn start(gpa: std.mem.Allocator, registry: *workspace.Registry, root: []const u8, callback: Callback, context: ?*anyopaque, latency_s: f64) Error!*Watcher {
        var buf: paths.Buffer = undefined;
        const real = try registry.resolve(root, &buf);
        if (!paths.isDirectory(real)) return error.NotDirectory;

        const self = try gpa.create(Watcher);
        errdefer gpa.destroy(self);
        const root_copy = try gpa.dupe(u8, real);
        errdefer gpa.free(root_copy);
        const init_flags: u32 = @bitCast(std.c.O{ .CLOEXEC = true, .NONBLOCK = true });
        const fd = inotify_init1(@intCast(init_flags));
        if (fd < 0) return error.Unexpected;
        errdefer _ = c.close(fd);

        self.* = .{
            .gpa = gpa,
            .root = root_copy,
            .fd = fd,
            .callback = callback,
            .context = context,
            .latency_ms = @intFromFloat(@max(latency_s, 0) * 1000),
            .arena = .init(gpa),
        };
        errdefer self.deinitWatches();
        // Every folder existing now gets a watch before start returns, so
        // nothing done after it is missed.
        try self.addWatchTree(real);
        self.thread = std.Thread.spawn(.{ .stack_size = 1024 * 1024 }, loop, .{self}) catch return error.Unexpected;
        return self;
    }

    /// Stops watching and frees the watcher. No callback runs after this.
    pub fn stop(self: *Watcher) void {
        self.stop_flag.store(true, .release);
        // Do not close the descriptor here: the kernel releases every watch
        // on close, which took ~550 ms for /usr (2026-11-01). The reader
        // wakes on its own poll timeout, and a detached closer releases the
        // descriptor without making stop() wait.
        self.thread.join();
        self.deinitWatches();
        self.gpa.free(self.root);
        const fd = self.fd;
        self.gpa.destroy(self);
        const closer = std.Thread.spawn(.{}, closeFd, .{fd}) catch {
            _ = c.close(fd);
            return;
        };
        closer.detach();
    }

    fn deinitWatches(self: *Watcher) void {
        self.watches.deinit(self.gpa);
        self.arena.deinit();
    }

    fn addWatchTree(self: *Watcher, path: []const u8) Error!void {
        try self.addWatch(path);
        var reader = fs.DirReader.open(path) catch return;
        defer reader.close();
        var name_buf: fs.Buffer = undefined;
        var child: fs.Buffer = undefined;
        while (reader.next()) |entry| {
            if (entry.kind != .directory) continue;
            const name = std.fmt.bufPrint(&name_buf, "{s}", .{entry.name}) catch return error.NameTooLong;
            const sub = fs.join(&child, path, name) catch continue;
            // A folder that cannot be watched (permission) is still listed
            // by its parent; the watcher does not fail the whole tree.
            self.addWatchTree(sub) catch {};
        }
    }

    fn addWatch(self: *Watcher, path: []const u8) Error!void {
        var z: fs.Buffer = undefined;
        const p = try terminate(path, &z);
        const wd = inotify_add_watch(self.fd, p.ptr, watch_mask);
        if (wd < 0) return error.Unexpected;
        const copy = try self.arena.allocator().dupeZ(u8, path);
        const gop = try self.watches.getOrPut(self.gpa, wd);
        gop.value_ptr.* = copy;
    }
};

fn closeFd(fd: c_int) void {
    _ = c.close(fd);
}

fn terminate(path: []const u8, out: *fs.Buffer) Error![:0]const u8 {
    if (path.len >= fs.max_path) return error.NameTooLong;
    @memcpy(out[0..path.len], path);
    out[path.len] = 0;
    return out[0..path.len :0];
}

/// The folders changed since the last batch, each once.
const Batch = struct {
    arena: std.heap.ArenaAllocator,
    index: std.StringHashMapUnmanaged(usize) = .empty,
    changes: std.ArrayList(Change) = .empty,

    fn add(self: *Batch, folder: []const u8, subtree: bool) void {
        const a = self.arena.allocator();
        if (self.index.get(folder)) |at| {
            self.changes.items[at].subtree = self.changes.items[at].subtree or subtree;
            return;
        }
        const copy = a.dupeZ(u8, folder) catch return;
        self.index.put(a, copy, self.changes.items.len) catch return;
        self.changes.append(a, .{ .path = copy.ptr, .subtree = subtree }) catch return;
    }

    fn deliver(self: *Batch, watcher: *Watcher) void {
        if (self.changes.items.len > 0) watcher.callback(watcher.context, self.changes.items.ptr, self.changes.items.len);
        self.index = .empty;
        self.changes = .empty;
        _ = self.arena.reset(.retain_capacity);
    }
};

fn loop(self: *Watcher) void {
    var batch: Batch = .{ .arena = .init(self.gpa) };
    defer batch.arena.deinit();
    var buffer: [64 * 1024]u8 = undefined;
    var deadline: ?i64 = null;
    while (!self.stop_flag.load(.acquire)) {
        const timeout: i32 = if (deadline) |d| @intCast(@max(d - clock.monotonicMs(), 0)) else 100;
        var fds = [_]c.pollfd{.{ .fd = self.fd, .events = c.POLL.IN, .revents = 0 }};
        const ready = c.poll(&fds, 1, timeout);
        if (self.stop_flag.load(.acquire)) return;
        if (ready > 0) {
            while (true) {
                const n = c.read(self.fd, &buffer, buffer.len);
                if (n < 0) {
                    if (c.errno(n) == .INTR) continue;
                    if (c.errno(n) == .AGAIN) break;
                    return;
                }
                if (n == 0) break;
                readEvents(self, &batch, buffer[0..@intCast(n)]);
                if (deadline == null) deadline = clock.monotonicMs() + self.latency_ms;
            }
        }
        if (deadline) |d| {
            if (clock.monotonicMs() >= d) {
                batch.deliver(self);
                deadline = null;
            }
        }
    }
}

fn readEvents(self: *Watcher, batch: *Batch, bytes: []const u8) void {
    var at: usize = 0;
    while (at + @sizeOf(Event) <= bytes.len) {
        const event: Event = @as(*align(1) const Event, @ptrCast(bytes[at..].ptr)).*;
        const name_at = at + @sizeOf(Event);
        const name_len: usize = event.len;
        if (name_at + name_len > bytes.len) return;
        const name = std.mem.sliceTo(bytes[name_at..][0..name_len], 0);
        at = name_at + name_len;

        // Overflow carries wd -1: the details are gone, so read the tree.
        if (event.mask & IN_Q_OVERFLOW != 0) {
            batch.add(self.root, true);
            continue;
        }
        const dir = self.watches.get(event.wd) orelse continue;
        // The folder itself went away: the tree must be read again. Report
        // before IN_IGNORED removes the watch.
        if (event.mask & (IN_DELETE_SELF | IN_MOVE_SELF) != 0) {
            batch.add(dir, true);
        }
        if (event.mask & IN_IGNORED != 0) {
            _ = self.watches.remove(event.wd);
            continue;
        }
        // A new folder gets its watch before the app rescans it, so files
        // written there right away are not lost.
        if (name.len > 0 and event.mask & IN_ISDIR != 0 and event.mask & (IN_CREATE | IN_MOVED_TO) != 0) {
            var child: fs.Buffer = undefined;
            const path = fs.join(&child, dir, name) catch {
                batch.add(dir, true);
                continue;
            };
            self.addWatchTree(path) catch {};
        }
        batch.add(dir, false);
    }
}
