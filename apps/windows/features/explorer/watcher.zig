//! Following the disk (docs/spec/explorer.md): the core's watcher of the
//! root reports the folders that changed on its own thread; they wait in a
//! locked list until the window's thread takes them (drain) and reloads
//! those folders of the tree.

const std = @import("std");
const cadex = @import("cadex");

pub const Watcher = struct {
    gpa: std.mem.Allocator,
    handle: ?*cadex.cadex_explorer_watcher = null,
    lock: std.atomic.Mutex = .unlocked,
    pending: std.ArrayList([]u8) = .empty,
    /// Detail was lost somewhere: read every open folder again.
    everything: bool = false,
    /// Called on the watcher's thread after queueing: wake the window (PostMessage).
    wake: *const fn (context: *anyopaque) void,
    wake_context: *anyopaque,

    pub fn start(self: *Watcher, root: []const u8) void {
        self.stop();
        const z = self.gpa.dupeZ(u8, root) catch return;
        defer self.gpa.free(z);
        var out: ?*cadex.cadex_explorer_watcher = null;
        if (cadex.cadex_explorer_watch(z.ptr, self, onChange, &out) == cadex.CADEX_OK) self.handle = out;
    }

    pub fn stop(self: *Watcher) void {
        if (self.handle) |h| cadex.cadex_explorer_watch_stop(h);
        self.handle = null;
        spin(&self.lock);
        defer self.lock.unlock();
        for (self.pending.items) |p| self.gpa.free(p);
        self.pending.clearRetainingCapacity();
    }

    pub fn deinit(self: *Watcher) void {
        self.stop();
        self.pending.deinit(self.gpa);
    }

    fn onChange(context: ?*anyopaque, changes: [*c]const cadex.cadex_explorer_change, count: usize) callconv(.c) void {
        const self: *Watcher = @ptrCast(@alignCast(context.?));
        spin(&self.lock);
        for (changes[0..count]) |change| {
            if (change.subtree) self.everything = true;
            const copy = self.gpa.dupe(u8, std.mem.span(change.path)) catch continue;
            self.pending.append(self.gpa, copy) catch self.gpa.free(copy);
        }
        self.lock.unlock();
        self.wake(self.wake_context);
    }

    pub const Batch = struct {
        paths: [][]u8,
        everything: bool,

        pub fn deinit(self: Batch, gpa: std.mem.Allocator) void {
            for (self.paths) |p| gpa.free(p);
            gpa.free(self.paths);
        }
    };

    /// What changed since the last drain, owned by the caller.
    pub fn drain(self: *Watcher) ?Batch {
        spin(&self.lock);
        defer self.lock.unlock();
        if (self.pending.items.len == 0 and !self.everything) return null;
        const paths = self.pending.toOwnedSlice(self.gpa) catch return null;
        const all = self.everything;
        self.everything = false;
        return .{ .paths = paths, .everything = all };
    }
};

fn spin(m: *std.atomic.Mutex) void {
    while (!m.tryLock()) std.atomic.spinLoopHint();
}

test {
    @import("win32").refAllDeep(@This());
}
