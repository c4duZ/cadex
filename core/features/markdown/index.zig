//! Headings and links of every Markdown file of the workspace, read on a
//! thread of its own and kept current by the explorer's watcher: a changed
//! folder has only its own notes read again (docs/spec/markdown.md).

const std = @import("std");
const fs = @import("../../shared/fs.zig");
const sync = @import("../../shared/sync.zig");
const workspace = @import("../workspace/workspace.zig");
const explorer = @import("../explorer/explorer.zig");
const search = @import("../search/search.zig");
const outline = @import("outline.zig");
const resolve = @import("resolve.zig");

const watch = explorer.watch;
const paths = workspace.paths;
const Walker = search.walker.Walker;
const nearby = search.nearby;

/// Notes above this size are skipped: not hand-written notes.
const max_note_bytes = 2 * 1024 * 1024;

/// How many notes the index keeps: far more than a project's docs, spent
/// near the focus first; a home folder has 60 000 .md files (measured
/// 2026-10-20), and each kept outline costs memory.
pub const note_budget = 5_000;

pub const Index = struct {
    gpa: std.mem.Allocator,
    registry: *workspace.Registry,
    root: []u8,
    /// Nothing is read until the first query: a workspace with no note
    /// open costs nothing.
    started: bool = false,
    /// Where the budget is spent first (the open note's folder), relative.
    focus: []u8 = &.{},
    covered: nearby.Covered,
    truncated: std.atomic.Value(bool) = .init(false),
    refocus: bool = false,
    mutex: sync.Mutex = .{},
    wake: sync.Condition = .{},
    /// Relative path (owned) -> its outline.
    notes: std.StringArrayHashMapUnmanaged(*outline.Outline) = .empty,
    ready: std.atomic.Value(bool) = .init(false),
    cancelled: std.atomic.Value(bool) = .init(false),
    stop: bool = false,
    pending: std.ArrayList([]u8) = .empty,
    thread: std.Thread = undefined,
    watcher: ?*watch.Watcher = null,

    pub fn open(gpa: std.mem.Allocator, registry: *workspace.Registry, root: []const u8) !*Index {
        var buf: paths.Buffer = undefined;
        const real = try registry.resolve(root, &buf);
        if (!paths.isDirectory(real)) return error.NotDirectory;
        const self = try gpa.create(Index);
        errdefer gpa.destroy(self);
        self.* = .{ .gpa = gpa, .registry = registry, .root = try gpa.dupe(u8, real), .covered = .{ .gpa = gpa } };
        return self;
    }

    /// Starts reading, once: every query calls it.
    pub fn start(self: *Index) void {
        self.lock();
        defer self.unlock();
        if (self.started) return;
        self.thread = std.Thread.spawn(.{}, run, .{self}) catch return;
        self.started = true;
        self.watcher = watch.Watcher.start(self.gpa, self.registry, self.root, onChanges, self, watch.default_latency_s) catch null;
    }

    /// The folder of the note in use (absolute); outside what was read,
    /// the index reads again from it.
    pub fn setFocus(self: *Index, folder: []const u8) void {
        const rel = if (paths.isWithin(self.root, folder)) std.mem.trim(u8, folder[self.root.len..], "/\\") else "";
        self.lock();
        defer self.unlock();
        if (std.mem.eql(u8, rel, self.focus)) return;
        const copy = self.gpa.dupe(u8, rel) catch return;
        std.mem.replaceScalar(u8, copy, '\\', '/');
        self.gpa.free(self.focus);
        self.focus = copy;
        if (self.started and self.truncated.load(.acquire) and !self.covered.contains(copy)) {
            self.refocus = true;
            self.wake.signal();
        }
    }

    pub fn close(self: *Index) void {
        if (self.watcher) |w| w.stop();
        self.cancelled.store(true, .release);
        self.lock();
        self.stop = true;
        self.wake.signal();
        const running = self.started;
        self.unlock();
        if (running) self.thread.join();
        self.gpa.free(self.focus);
        self.covered.deinit();
        for (self.pending.items) |p| self.gpa.free(p);
        self.pending.deinit(self.gpa);
        for (self.notes.keys(), self.notes.values()) |k, v| self.free(k, v);
        self.notes.deinit(self.gpa);
        self.gpa.free(self.root);
        self.gpa.destroy(self);
    }

    pub fn lock(self: *Index) void {
        self.mutex.lock();
    }

    pub fn unlock(self: *Index) void {
        self.mutex.unlock();
    }

    fn free(self: *Index, key: []const u8, value: *outline.Outline) void {
        value.deinit();
        self.gpa.destroy(value);
        self.gpa.free(key);
    }

    /// Lock held: the resolver's view of the notes.
    pub fn notesView(self: *Index) resolve.Notes {
        return .{ .context = self, .list = list, .get = get };
    }

    fn list(context: *anyopaque) []const []const u8 {
        const self: *Index = @ptrCast(@alignCast(context));
        return self.notes.keys();
    }

    fn get(context: *anyopaque, rel: []const u8) ?*const outline.Outline {
        const self: *Index = @ptrCast(@alignCast(context));
        return self.notes.get(rel);
    }

    /// The root-relative form of an absolute path inside the root.
    pub fn relative(self: *const Index, abs: []const u8) ?[]const u8 {
        if (!paths.isWithin(self.root, abs) or abs.len == self.root.len) return null;
        return abs[self.root.len + 1 ..];
    }

    fn run(self: *Index) void {
        var walker = Walker.init(self.gpa, self.root, .{ .cancel = &self.cancelled }) catch return;
        defer walker.deinit();
        self.build(&walker);
        self.ready.store(true, .release);
        while (self.nextWork()) |work| switch (work) {
            .rebuild => self.build(&walker),
            .folder => |folder| {
                defer self.gpa.free(folder);
                self.refresh(&walker, folder);
            },
        };
    }

    const Work = union(enum) { rebuild, folder: []u8 };

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

    /// Reads the notes from the focus outward, up to the budget, replacing
    /// what was there.
    fn build(self: *Index, walker: *Walker) void {
        self.lock();
        const focus = self.gpa.dupe(u8, self.focus) catch {
            self.unlock();
            return;
        };
        for (self.notes.keys(), self.notes.values()) |k, v| self.free(k, v);
        self.notes.clearRetainingCapacity();
        self.unlock();
        defer self.gpa.free(focus);
        walker.count = 0;
        var covered: nearby.Covered = .{ .gpa = self.gpa };
        nearby.walk(walker, focus, self, visitNote, &covered) catch {};
        self.lock();
        defer self.unlock();
        self.covered.deinit();
        self.covered = covered;
        self.truncated.store(!covered.all, .release);
    }

    fn visitNote(context: *anyopaque, rel: []const u8, size: u64) bool {
        const index: *Index = @ptrCast(@alignCast(context));
        if (resolve.isMarkdown(rel) and size <= max_note_bytes) {
            index.lock();
            const full = index.notes.count() >= note_budget;
            index.unlock();
            if (full) return false;
            index.readNote(rel);
        }
        return !index.cancelled.load(.acquire);
    }

    /// Every note under `folder`.
    fn readTree(self: *Index, walker: *Walker, folder: []const u8) void {
        walker.count = 0;
        _ = walker.walk(folder, self, visitNote) catch {};
    }

    /// A changed folder: its own notes read again or dropped, new
    /// subfolders read, vanished ones dropped.
    fn refresh(self: *Index, walker: *Walker, folder: []const u8) void {
        var arena: std.heap.ArenaAllocator = .init(self.gpa);
        defer arena.deinit();
        const contents = walker.readFolder(arena.allocator(), folder) catch return;
        self.lock();
        var i: usize = 0;
        while (i < self.notes.count()) {
            const key = self.notes.keys()[i];
            if (isUnder(key, folder) and !stillThere(key, folder, contents)) {
                const value = self.notes.values()[i];
                self.notes.swapRemoveAt(i);
                self.free(key, value);
            } else i += 1;
        }
        var new_folders: std.ArrayList([]const u8) = .empty;
        for (contents.folders) |sub| {
            if (!self.hasUnder(sub)) new_folders.append(arena.allocator(), sub) catch {};
        }
        self.unlock();
        for (contents.files) |f| {
            if (resolve.isMarkdown(f.rel) and f.size <= max_note_bytes) self.readNote(f.rel);
        }
        for (new_folders.items) |sub| self.readTree(walker, sub);
    }

    fn hasUnder(self: *Index, folder: []const u8) bool {
        for (self.notes.keys()) |key| if (isUnder(key, folder)) return true;
        return false;
    }

    /// Reads and parses one note, replacing what was indexed for it.
    fn readNote(self: *Index, rel: []const u8) void {
        var buf: paths.Buffer = undefined;
        const path = std.fmt.bufPrintZ(&buf, "{s}/{s}", .{ self.root, rel }) catch return;
        const text = readFile(self.gpa, path) orelse return;
        defer self.gpa.free(text);
        const parsed = self.gpa.create(outline.Outline) catch return;
        parsed.* = outline.parse(self.gpa, text) catch {
            self.gpa.destroy(parsed);
            return;
        };
        self.lock();
        defer self.unlock();
        if (self.notes.getEntry(rel)) |entry| {
            entry.value_ptr.*.deinit();
            self.gpa.destroy(entry.value_ptr.*);
            entry.value_ptr.* = parsed;
            return;
        }
        const key = self.gpa.dupe(u8, rel) catch return self.free("", parsed);
        self.notes.put(self.gpa, key, parsed) catch self.free(key, parsed);
    }

    fn onChanges(context: ?*anyopaque, changes: [*]const watch.Change, n: usize) callconv(.c) void {
        const self: *Index = @ptrCast(@alignCast(context orelse return));
        self.lock();
        defer self.unlock();
        for (changes[0..n]) |change| {
            const abs = std.mem.span(change.path);
            if (!paths.isWithin(self.root, abs)) continue;
            const rel = std.mem.trimStart(u8, abs[self.root.len..], "/");
            if (std.mem.startsWith(u8, rel, ".git")) continue;
            // Outside what the budget covers, changes do not matter.
            if (self.truncated.load(.acquire) and !self.covered.contains(rel)) continue;
            const copy = self.gpa.dupe(u8, rel) catch continue;
            self.pending.append(self.gpa, copy) catch self.gpa.free(copy);
        }
        self.wake.signal();
    }
};

/// Whether `key` is inside `folder` ("" is the root).
fn isUnder(key: []const u8, folder: []const u8) bool {
    if (folder.len == 0) return true;
    return key.len > folder.len and std.mem.startsWith(u8, key, folder) and key[folder.len] == '/';
}

/// Whether an indexed note under a re-read folder still exists: its own
/// files must be listed again, notes in subfolders need the subfolder.
fn stillThere(key: []const u8, folder: []const u8, contents: Walker.Folder) bool {
    const below = if (folder.len == 0) key else key[folder.len + 1 ..];
    if (std.mem.indexOfScalar(u8, below, '/')) |slash| {
        const sub = key[0 .. key.len - below.len + slash];
        for (contents.folders) |f| if (std.mem.eql(u8, f, sub)) return true;
        return false;
    }
    for (contents.files) |f| if (std.mem.eql(u8, f.rel, key)) return true;
    return false;
}

fn readFile(gpa: std.mem.Allocator, path: []const u8) ?[]u8 {
    const file = fs.File.openRead(path, .{}) catch return null;
    defer file.close();
    var out: std.ArrayList(u8) = .empty;
    fs.appendUpTo(gpa, file, &out, max_note_bytes) catch {
        out.deinit(gpa);
        return null;
    };
    return out.toOwnedSlice(gpa) catch null;
}

test {
    _ = @import("index_test.zig");
}
