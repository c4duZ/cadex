//! Walks a workspace folder for the searches: files only, `.git` and
//! ignored paths left out (shared/ignore.zig), hidden ones unless asked.
//! Symbolic links are not followed, so the walk never leaves the folder.

const std = @import("std");
const c = std.c;
const ignore = @import("../../shared/ignore.zig");

extern "c" fn dirfd(dir: *c.DIR) c.fd_t;

/// A walk stops after this many files: a home folder opened by mistake
/// should not eat the memory.
pub const max_files = 300_000;

pub const Options = struct {
    show_hidden: bool = false,
    /// Checked between folders; the walk returns early when it turns true.
    cancel: ?*const std.atomic.Value(bool) = null,
};

/// Called with each file's path relative to the root and its size.
/// Returning false stops the walk.
pub const Visit = fn (context: *anyopaque, rel: []const u8, size: u64) bool;

pub const Walker = struct {
    gpa: std.mem.Allocator,
    root: []const u8,
    matcher: ignore.Matcher,
    options: Options,
    count: usize = 0,

    pub fn init(gpa: std.mem.Allocator, root: []const u8, options: Options) !Walker {
        return .{ .gpa = gpa, .root = root, .matcher = try ignore.Matcher.init(gpa, root), .options = options };
    }

    pub fn deinit(self: *Walker) void {
        self.matcher.deinit();
    }

    /// Visits every file under `start` (relative, "" for the root), sorted
    /// by name inside each folder. False if stopped (visit, cancel, limit).
    pub fn walk(self: *Walker, start: []const u8, context: *anyopaque, visit: *const Visit) !bool {
        var pending: std.ArrayList([]u8) = .empty;
        defer {
            for (pending.items) |p| self.gpa.free(p);
            pending.deinit(self.gpa);
        }
        try pending.append(self.gpa, try self.gpa.dupe(u8, start));
        while (pending.pop()) |folder| {
            defer self.gpa.free(folder);
            if (self.cancelled()) return false;
            if (!try self.walkFolder(folder, context, visit, &pending)) return false;
        }
        return true;
    }

    fn cancelled(self: *Walker) bool {
        const flag = self.options.cancel orelse return false;
        return flag.load(.acquire);
    }

    pub const File = struct { rel: []const u8, size: u64 };
    /// One folder's files and subfolders that pass the rules, by name.
    pub const Folder = struct { files: []File, folders: [][]const u8 };

    /// Reads one folder (relative, "" for the root), allocating in `a`. A
    /// folder that cannot be opened reads as empty.
    pub fn readFolder(self: *Walker, a: std.mem.Allocator, folder: []const u8) !Folder {
        var path_buf: [c.PATH_MAX]u8 = undefined;
        const path = (if (folder.len == 0)
            std.fmt.bufPrintZ(&path_buf, "{s}", .{self.root})
        else
            std.fmt.bufPrintZ(&path_buf, "{s}/{s}", .{ self.root, folder })) catch return .{ .files = &.{}, .folders = &.{} };
        const dir = c.opendir(path.ptr) orelse return .{ .files = &.{}, .folders = &.{} };
        defer _ = c.closedir(dir);
        const fd = dirfd(dir);

        var files: std.ArrayList(File) = .empty;
        var folders: std.ArrayList([]const u8) = .empty;
        while (c.readdir(dir)) |ent| {
            const name = ent.name[0..ent.namlen];
            if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..") or std.mem.eql(u8, name, ".git")) continue;
            if (!self.options.show_hidden and name[0] == '.') continue;
            var st: c.Stat = undefined;
            if (c.fstatat(fd, (try a.dupeZ(u8, name)).ptr, &st, c.AT.SYMLINK_NOFOLLOW) != 0) continue;
            const kind = st.mode & c.S.IFMT;
            if (kind != c.S.IFREG and kind != c.S.IFDIR) continue;
            const rel = try join(a, folder, try a.dupe(u8, name));
            if (self.matcher.decide(rel, kind == c.S.IFDIR)) continue;
            if (kind == c.S.IFDIR) try folders.append(a, rel) else try files.append(a, .{ .rel = rel, .size = @intCast(st.size) });
        }
        std.mem.sort(File, files.items, {}, struct {
            fn lessThan(_: void, x: File, y: File) bool {
                return std.mem.order(u8, x.rel, y.rel) == .lt;
            }
        }.lessThan);
        std.mem.sort([]const u8, folders.items, {}, struct {
            fn lessThan(_: void, x: []const u8, y: []const u8) bool {
                return std.mem.order(u8, x, y) == .lt;
            }
        }.lessThan);
        return .{ .files = files.items, .folders = folders.items };
    }

    fn walkFolder(self: *Walker, folder: []const u8, context: *anyopaque, visit: *const Visit, pending: *std.ArrayList([]u8)) !bool {
        var arena: std.heap.ArenaAllocator = .init(self.gpa);
        defer arena.deinit();
        const contents = try self.readFolder(arena.allocator(), folder);
        // Folders go on the stack in reverse, so they come out in order.
        var i = contents.folders.len;
        while (i > 0) {
            i -= 1;
            try pending.append(self.gpa, try self.gpa.dupe(u8, contents.folders[i]));
        }
        for (contents.files) |file| {
            self.count += 1;
            if (self.count > max_files) return false;
            if (!visit(context, file.rel, file.size)) return false;
        }
        return true;
    }
};

fn join(a: std.mem.Allocator, folder: []const u8, name: []const u8) ![]const u8 {
    if (folder.len == 0) return name;
    return std.fmt.allocPrint(a, "{s}/{s}", .{ folder, name });
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

test "walks files in order, leaving out .git, ignored and hidden paths" {
    var dir = try TestDir.init();
    defer dir.deinit();
    try dir.writeFile(".gitignore", "zig-out/\n*.o\n");
    try dir.makeDir(".git/objects");
    try dir.writeFile(".git/HEAD", "ref");
    try dir.makeDir("zig-out/lib");
    try dir.writeFile("zig-out/lib/libcadex.a", "");
    try dir.makeDir("src/b");
    try dir.writeFile("src/b/two.zig", "");
    try dir.writeFile("src/a.zig", "");
    try dir.writeFile("src/a.o", "");
    try dir.writeFile(".env", "");
    try dir.writeFile("main.zig", "");

    var walker = try Walker.init(testing.allocator, dir.path(), .{});
    defer walker.deinit();
    var seen: Collect = .{};
    defer seen.deinit();
    try testing.expect(try walker.walk("", &seen, Collect.visit));
    const want = [_][]const u8{ "main.zig", "src/a.zig", "src/b/two.zig" };
    try testing.expectEqual(want.len, seen.list.items.len);
    for (want, seen.list.items) |w, got| try testing.expectEqualStrings(w, got);

    var with_hidden = try Walker.init(testing.allocator, dir.path(), .{ .show_hidden = true });
    defer with_hidden.deinit();
    var all: Collect = .{};
    defer all.deinit();
    _ = try with_hidden.walk("", &all, Collect.visit);
    try testing.expectEqualStrings(".env", all.list.items[0]);
    try testing.expectEqualStrings(".gitignore", all.list.items[1]);
}
