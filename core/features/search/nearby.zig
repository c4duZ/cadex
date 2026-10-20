//! Walks a workspace nearest a focus folder first (docs/spec/search.md):
//! everything under the focus, then, one level up at a time, each parent's
//! own files and its other folders. The indexes spend their budget this
//! way, so a big workspace (a home folder: 1.2 million files, measured
//! 2026-10-20) keeps the folder the user is in and leaves out what is far.

const std = @import("std");
const Walker = @import("walker.zig").Walker;
const Visit = @import("walker.zig").Visit;

/// The folders a nearby walk read completely: every file under each is in.
pub const Covered = struct {
    gpa: std.mem.Allocator,
    prefixes: std.ArrayList([]u8) = .empty,
    /// The whole root was read: nothing is left out.
    all: bool = false,

    pub fn deinit(self: *Covered) void {
        self.clear();
        self.prefixes.deinit(self.gpa);
    }

    pub fn clear(self: *Covered) void {
        for (self.prefixes.items) |p| self.gpa.free(p);
        self.prefixes.clearRetainingCapacity();
        self.all = false;
    }

    fn add(self: *Covered, rel: []const u8) !void {
        try self.prefixes.append(self.gpa, try self.gpa.dupe(u8, rel));
    }

    /// Whether `rel` (a file or folder, relative to the root) is in a
    /// folder that was read completely.
    pub fn contains(self: *const Covered, rel: []const u8) bool {
        if (self.all) return true;
        for (self.prefixes.items) |p| {
            if (p.len == 0) return true;
            if (std.mem.eql(u8, rel, p)) return true;
            if (rel.len > p.len and std.mem.startsWith(u8, rel, p) and rel[p.len] == '/') return true;
        }
        return false;
    }
};

/// Visits the root's files nearest `focus` (relative, "" for the root)
/// first, until the walker's budget, a false from `visit` or a cancel.
/// `covered` gets the folders read completely.
pub fn walk(walker: *Walker, focus: []const u8, context: *anyopaque, visit: *const Visit, covered: *Covered) !void {
    if (!try walker.walk(focus, context, visit)) return;
    try covered.add(focus);
    if (focus.len == 0) {
        covered.all = true;
        return;
    }
    var current = focus;
    while (true) {
        const parent = parentOf(current);
        var arena: std.heap.ArenaAllocator = .init(walker.gpa);
        defer arena.deinit();
        const contents = try walker.readFolder(arena.allocator(), parent);
        for (contents.files) |file| {
            if (walker.full()) return;
            walker.count += 1;
            if (!visit(context, file.rel, file.size)) return;
        }
        for (contents.folders) |sub| {
            if (std.mem.eql(u8, sub, current)) continue;
            if (!try walker.walk(sub, context, visit)) return;
            try covered.add(sub);
        }
        if (parent.len == 0) {
            covered.all = true;
            return;
        }
        try covered.add(parent);
        current = parent;
    }
}

fn parentOf(rel: []const u8) []const u8 {
    const slash = std.mem.lastIndexOfScalar(u8, rel, '/') orelse return "";
    return rel[0..slash];
}

const testing = std.testing;
const TestDir = @import("../../shared/test_dir.zig").TestDir;

const Collect = struct {
    list: std.ArrayList([]u8) = .empty,

    fn visit(context: *anyopaque, rel: []const u8, _: u64) bool {
        const self: *Collect = @ptrCast(@alignCast(context));
        self.list.append(testing.allocator, testing.allocator.dupe(u8, rel) catch return false) catch return false;
        return true;
    }

    fn deinit(self: *Collect) void {
        for (self.list.items) |p| testing.allocator.free(p);
        self.list.deinit(testing.allocator);
    }
};

fn tree(dir: *TestDir) !void {
    for ([_][]const u8{ "far/1", "far/2", "far/3", "work/app/a", "work/app/b", "work/lib/c", "work/top", "root.txt" }) |f| {
        if (std.mem.lastIndexOfScalar(u8, f, '/')) |slash| try dir.makeDir(f[0..slash]);
        try dir.writeFile(f, "");
    }
}

test "the focus first, then its parents' other folders, nearest first" {
    var dir = try TestDir.init();
    defer dir.deinit();
    try tree(&dir);
    var walker = try Walker.init(testing.allocator, dir.path(), .{});
    defer walker.deinit();
    var seen: Collect = .{};
    defer seen.deinit();
    var covered: Covered = .{ .gpa = testing.allocator };
    defer covered.deinit();
    try walk(&walker, "work/app", &seen, Collect.visit, &covered);
    const want = [_][]const u8{ "work/app/a", "work/app/b", "work/top", "work/lib/c", "root.txt", "far/1", "far/2", "far/3" };
    try testing.expectEqual(want.len, seen.list.items.len);
    for (want, seen.list.items) |w, got| try testing.expectEqualStrings(w, got);
    try testing.expect(covered.all);
}

test "a budget keeps the focus and leaves out what is far" {
    var dir = try TestDir.init();
    defer dir.deinit();
    try tree(&dir);
    var walker = try Walker.init(testing.allocator, dir.path(), .{ .limit = 4 });
    defer walker.deinit();
    var seen: Collect = .{};
    defer seen.deinit();
    var covered: Covered = .{ .gpa = testing.allocator };
    defer covered.deinit();
    try walk(&walker, "work/app", &seen, Collect.visit, &covered);
    try testing.expectEqual(@as(usize, 4), seen.list.items.len);
    try testing.expect(walker.full() and !covered.all);
    try testing.expect(covered.contains("work/app") and covered.contains("work/app/a"));
    try testing.expect(!covered.contains("far") and !covered.contains("far/1") and !covered.contains("worker/x"));
}

test "dependencies and caches are left out, Library only at home" {
    var dir = try TestDir.init();
    defer dir.deinit();
    try dir.makeDir("node_modules/x");
    try dir.writeFile("node_modules/x/index.js", "");
    try dir.makeDir("Library");
    try dir.writeFile("Library/kept.txt", "");
    try dir.writeFile("main.zig", "");
    var walker = try Walker.init(testing.allocator, dir.path(), .{});
    defer walker.deinit();
    var seen: Collect = .{};
    defer seen.deinit();
    try testing.expect(try walker.walk("", &seen, Collect.visit));
    try testing.expectEqual(@as(usize, 2), seen.list.items.len);
    try testing.expectEqualStrings("main.zig", seen.list.items[0]);
    try testing.expectEqualStrings("Library/kept.txt", seen.list.items[1]);
}
