//! Walks a workspace folder for the searches: files only, `.git` and
//! ignored paths left out (shared/ignore.zig), hidden ones unless asked.
//! Symbolic links are not followed, so the walk never leaves the folder.

const std = @import("std");
const fs = @import("../../shared/fs.zig");
const ignore = @import("../../shared/ignore.zig");

/// A walk stops after this many files by default: a home folder opened by
/// mistake should not eat the memory. The indexes pass smaller budgets and
/// spend them near the user's folder first (nearby.zig).
pub const max_files = 300_000;

/// Folders no search wants, left out even without a .gitignore saying so:
/// dependencies, caches and build output, which made a home folder's walk
/// read 1.2 million files (measured 2026-10-20).
pub const skipped_folders = [_][]const u8{
    "node_modules", "bower_components", ".Trash", "__pycache__", ".venv", ".zig-cache", ".build", ".next", ".gradle", ".cache",
};

/// Left out only when the root is the user's home folder: the system's
/// own data, always changing (the Mac's Library, Windows' AppData).
pub const skipped_in_home = [_][]const u8{ "Library", "AppData" };

pub const Options = struct {
    show_hidden: bool = false,
    /// How many files a walk visits before it stops.
    limit: usize = max_files,
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
    /// Files visited so far; the indexes set it to what they hold before
    /// reading a folder again, so the budget counts what is kept.
    count: usize = 0,
    /// The root is the user's home folder: skipped_in_home applies.
    at_home: bool,

    pub fn init(gpa: std.mem.Allocator, root: []const u8, options: Options) !Walker {
        return .{ .gpa = gpa, .root = root, .matcher = try ignore.Matcher.init(gpa, root), .options = options, .at_home = isHome(root) };
    }

    /// Whether the walk stopped at its budget.
    pub fn full(self: *const Walker) bool {
        return self.count >= self.options.limit;
    }

    fn skipped(self: *const Walker, folder: []const u8, name: []const u8) bool {
        for (skipped_folders) |s| if (std.mem.eql(u8, name, s)) return true;
        if (self.at_home and folder.len == 0) for (skipped_in_home) |s| if (std.mem.eql(u8, name, s)) return true;
        return false;
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
        // Relative paths keep '/' on every system (the ignore rules are
        // written that way); Windows takes it in a full path too.
        var path_buf: fs.Buffer = undefined;
        const path = (if (folder.len == 0) self.root else fs.join(&path_buf, self.root, folder)) catch return .{ .files = &.{}, .folders = &.{} };
        var dir = fs.DirReader.open(path) catch return .{ .files = &.{}, .folders = &.{} };
        defer dir.close();

        var files: std.ArrayList(File) = .empty;
        var folders: std.ArrayList([]const u8) = .empty;
        while (dir.next()) |entry| {
            const name = entry.name;
            if (std.mem.eql(u8, name, ".git")) continue;
            if (!self.options.show_hidden and name[0] == '.') continue;
            if (entry.kind != .file and entry.kind != .directory) continue;
            if (entry.kind == .directory and self.skipped(folder, name)) continue;
            const rel = try join(a, folder, try a.dupe(u8, name));
            if (self.matcher.decide(rel, entry.kind == .directory)) continue;
            if (entry.kind == .directory) try folders.append(a, rel) else try files.append(a, .{ .rel = rel, .size = entry.size });
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
            if (self.count >= self.options.limit) return false;
            self.count += 1;
            if (!visit(context, file.rel, file.size)) return false;
        }
        return true;
    }
};

/// The user's home folder ($HOME, or %USERPROFILE% on Windows).
fn isHome(root: []const u8) bool {
    const name = if (@import("builtin").os.tag == .windows) "USERPROFILE" else "HOME";
    const home = std.mem.span(std.c.getenv(name) orelse return false);
    return std.mem.eql(u8, std.mem.trimEnd(u8, home, "/\\"), std.mem.trimEnd(u8, root, "/\\"));
}

pub fn join(a: std.mem.Allocator, folder: []const u8, name: []const u8) ![]const u8 {
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
