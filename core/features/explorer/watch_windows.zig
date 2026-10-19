//! Watching the disk on Windows: ReadDirectoryChangesW over the whole tree,
//! on a thread of its own. Changes are gathered for the latency window
//! after the first one, then go to the app as one batch with each folder
//! once, like FSEvents does on the Mac. The interface is `watch.zig`.

const std = @import("std");
const w = @import("../../shared/win32.zig");
const fs = @import("../../shared/fs.zig");
const clock = @import("../../shared/clock.zig");
const workspace = @import("../workspace/workspace.zig");
const errors = @import("errors.zig");
const watch = @import("watch.zig");

const paths = workspace.paths;
const Error = errors.Error;
const Change = watch.Change;
const Callback = watch.Callback;

/// What the folder handle reports. Names cover create, delete and rename;
/// size and last write cover a file saved in place.
const filter = w.FILE_NOTIFY_CHANGE_FILE_NAME | w.FILE_NOTIFY_CHANGE_DIR_NAME |
    w.FILE_NOTIFY_CHANGE_SIZE | w.FILE_NOTIFY_CHANGE_LAST_WRITE;
/// 64 KB: the most ReadDirectoryChangesW takes over a network share.
const buffer_size = 64 * 1024;

pub const Watcher = struct {
    gpa: std.mem.Allocator,
    root: []u8,
    dir: w.HANDLE,
    io_event: w.HANDLE,
    stop_event: w.HANDLE,
    callback: Callback,
    context: ?*anyopaque,
    latency_ms: u32,
    overlapped: w.OVERLAPPED = .{},
    buffer: [buffer_size]u8 align(@alignOf(w.DWORD)) = undefined,
    thread: std.Thread = undefined,

    pub fn start(gpa: std.mem.Allocator, registry: *workspace.Registry, root: []const u8, callback: Callback, context: ?*anyopaque, latency_s: f64) Error!*Watcher {
        var buf: paths.Buffer = undefined;
        const real = try registry.resolve(root, &buf);
        if (!paths.isDirectory(real)) return error.NotDirectory;

        const self = try gpa.create(Watcher);
        errdefer gpa.destroy(self);
        const root_copy = try gpa.dupe(u8, real);
        errdefer gpa.free(root_copy);
        const dir = try openFolder(real);
        errdefer _ = w.CloseHandle(dir);
        const io_event = w.CreateEventW(null, 1, 0, null) orelse return error.Unexpected;
        errdefer _ = w.CloseHandle(io_event);
        const stop_event = w.CreateEventW(null, 1, 0, null) orelse return error.Unexpected;
        errdefer _ = w.CloseHandle(stop_event);
        self.* = .{
            .gpa = gpa,
            .root = root_copy,
            .dir = dir,
            .io_event = io_event,
            .stop_event = stop_event,
            .callback = callback,
            .context = context,
            .latency_ms = @intFromFloat(@max(latency_s, 0) * 1000),
        };
        // Issued before start returns, so nothing done after it is missed.
        if (!self.issueRead()) return error.Unexpected;
        self.thread = std.Thread.spawn(.{ .stack_size = 256 * 1024 }, loop, .{self}) catch {
            self.cancelRead();
            return error.Unexpected;
        };
        return self;
    }

    /// Stops watching and frees the watcher. No callback runs after this.
    pub fn stop(self: *Watcher) void {
        _ = w.SetEvent(self.stop_event);
        self.thread.join();
        self.cancelRead();
        _ = w.CloseHandle(self.stop_event);
        _ = w.CloseHandle(self.io_event);
        _ = w.CloseHandle(self.dir);
        self.gpa.free(self.root);
        self.gpa.destroy(self);
    }

    fn issueRead(self: *Watcher) bool {
        self.overlapped = .{ .hEvent = self.io_event };
        return w.ReadDirectoryChangesW(self.dir, &self.buffer, buffer_size, 1, filter, null, &self.overlapped, null) != 0;
    }

    /// Cancels the pending read and waits for it, so the kernel is done
    /// with the buffer before it is freed.
    fn cancelRead(self: *Watcher) void {
        _ = w.CancelIoEx(self.dir, &self.overlapped);
        var n: w.DWORD = 0;
        _ = w.GetOverlappedResult(self.dir, &self.overlapped, &n, 1);
    }
};

fn openFolder(real: []const u8) Error!w.HANDLE {
    var wide: [fs.max_path:0]u16 = undefined;
    const len = std.unicode.wtf8ToWtf16Le(&wide, real) catch return error.NotFound;
    wide[len] = 0;
    const share = w.FILE_SHARE_READ | w.FILE_SHARE_WRITE | w.FILE_SHARE_DELETE;
    const h = w.CreateFileW(&wide, w.FILE_LIST_DIRECTORY, share, null, w.OPEN_EXISTING, w.FILE_FLAG_BACKUP_SEMANTICS | w.FILE_FLAG_OVERLAPPED, null);
    if (h == w.INVALID_HANDLE_VALUE) return error.Unexpected;
    return h;
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
    var deadline: ?i64 = null;
    const events = [_]w.HANDLE{ self.stop_event, self.io_event };
    while (true) {
        const timeout: w.DWORD = if (deadline) |d| @intCast(@max(d - clock.monotonicMs(), 0)) else w.INFINITE;
        const woke = w.WaitForMultipleObjects(events.len, &events, 0, timeout);
        if (woke == w.WAIT_OBJECT_0) return;
        if (woke == w.WAIT_TIMEOUT) {
            batch.deliver(self);
            deadline = null;
            continue;
        }
        var n: w.DWORD = 0;
        const ok = w.GetOverlappedResult(self.dir, &self.overlapped, &n, 0) != 0;
        // Failed (the root went away) or 0 bytes (the buffer overflowed):
        // the details are lost, so the whole tree is read again.
        if (!ok or n == 0) batch.add(self.root, true) else readRecords(self, &batch, self.buffer[0..n]);
        if (deadline == null) deadline = clock.monotonicMs() + self.latency_ms;
        if (!self.issueRead()) {
            batch.deliver(self);
            return;
        }
    }
}

/// Each record names a changed entry relative to the root; its folder is
/// what changed for the tree.
fn readRecords(self: *Watcher, batch: *Batch, bytes: []const u8) void {
    var at: usize = 0;
    while (at + @sizeOf(w.FILE_NOTIFY_INFORMATION) <= bytes.len) {
        const record: *align(1) const w.FILE_NOTIFY_INFORMATION = @ptrCast(bytes[at..].ptr);
        const name_at = at + @sizeOf(w.FILE_NOTIFY_INFORMATION);
        const name_len = record.FileNameLength / 2;
        if (name_at + name_len * 2 > bytes.len) return;
        const name: []align(1) const u16 = @as([*]align(1) const u16, @ptrCast(bytes[name_at..].ptr))[0..name_len];
        addFolderOf(self, batch, name);
        if (record.NextEntryOffset == 0) return;
        at += record.NextEntryOffset;
    }
}

fn addFolderOf(self: *Watcher, batch: *Batch, name: []align(1) const u16) void {
    var wide: [fs.max_path / 3]u16 = undefined;
    if (name.len > wide.len) return batch.add(self.root, true);
    for (name, 0..) |unit, i| wide[i] = unit;
    var rel: fs.Buffer = undefined;
    const text = rel[0..std.unicode.wtf16LeToWtf8(&rel, wide[0..name.len])];
    const parent = if (std.mem.lastIndexOfScalar(u8, text, '\\')) |slash| text[0..slash] else "";
    if (parent.len == 0) return batch.add(self.root, false);
    var full: fs.Buffer = undefined;
    batch.add(fs.join(&full, self.root, parent) catch return batch.add(self.root, true), false);
}
