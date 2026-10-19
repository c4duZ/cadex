//! The directories the user opened in this run of the app. Every file
//! operation and search asks `resolve` first (docs/spec/workspace.md). The
//! list only grows while the app is open: switching workspace keeps the old
//! folder authorized for the session.

const std = @import("std");
const c = std.c;
const paths = @import("paths.zig");

pub const Error = paths.Error || error{ OutOfMemory, NotDirectory, Outside };

pub const Registry = struct {
    gpa: std.mem.Allocator,
    roots: std.ArrayList([]u8) = .empty,
    /// The app calls from the main thread; search and file watching from
    /// their own threads.
    mutex: c.pthread_mutex_t = c.PTHREAD_MUTEX_INITIALIZER,

    pub fn init(gpa: std.mem.Allocator) Registry {
        return .{ .gpa = gpa };
    }

    pub fn deinit(self: *Registry) void {
        for (self.roots.items) |root| self.gpa.free(root);
        self.roots.deinit(self.gpa);
    }

    /// Authorizes an existing directory. Returns its canonical path, which
    /// lives as long as the registry.
    pub fn authorize(self: *Registry, path: []const u8) Error![]const u8 {
        var buf: paths.Buffer = undefined;
        const real = try paths.canonicalize(path, &buf);
        if (!paths.isDirectory(real)) return error.NotDirectory;
        _ = c.pthread_mutex_lock(&self.mutex);
        defer _ = c.pthread_mutex_unlock(&self.mutex);
        for (self.roots.items) |root| {
            if (std.mem.eql(u8, root, real)) return root;
        }
        const copy = try self.gpa.dupe(u8, real);
        errdefer self.gpa.free(copy);
        try self.roots.append(self.gpa, copy);
        return copy;
    }

    /// The canonical form of `path` if it is inside an authorized
    /// directory, written to `out`. Operations use this result, not the
    /// path they were given.
    pub fn resolve(self: *Registry, path: []const u8, out: *paths.Buffer) Error![]const u8 {
        const real = try paths.canonicalize(path, out);
        _ = c.pthread_mutex_lock(&self.mutex);
        defer _ = c.pthread_mutex_unlock(&self.mutex);
        for (self.roots.items) |root| {
            if (paths.isWithin(root, real)) return real;
        }
        return error.Outside;
    }

    pub fn allows(self: *Registry, path: []const u8) bool {
        var buf: paths.Buffer = undefined;
        _ = self.resolve(path, &buf) catch return false;
        return true;
    }
};

const testing = std.testing;

/// A fresh directory under .zig-cache/tmp, with its canonical path.
const Fixture = struct {
    tmp: testing.TmpDir,
    root: paths.Buffer = undefined,
    root_len: usize = 0,

    fn init() !Fixture {
        var self: Fixture = .{ .tmp = testing.tmpDir(.{}) };
        var rel: paths.Buffer = undefined;
        const relative = try std.fmt.bufPrintZ(&rel, ".zig-cache/tmp/{s}", .{self.tmp.sub_path});
        const real = c.realpath(relative.ptr, &self.root) orelse return error.NotFound;
        self.root_len = std.mem.span(real).len;
        return self;
    }

    fn path(self: *const Fixture) []const u8 {
        return self.root[0..self.root_len];
    }

    fn join(self: *const Fixture, buf: []u8, sub: []const u8) ![]const u8 {
        return std.fmt.bufPrint(buf, "{s}/{s}", .{ self.path(), sub });
    }
};

test "paths inside an authorized directory resolve; outside are refused" {
    var fx = try Fixture.init();
    defer fx.tmp.cleanup();
    try fx.tmp.dir.createDirPath(testing.io, "inside/deep");
    var registry = Registry.init(testing.allocator);
    defer registry.deinit();

    var buf: [1024]u8 = undefined;
    _ = try registry.authorize(try fx.join(&buf, "inside"));
    try testing.expect(registry.allows(try fx.join(&buf, "inside/deep")));
    try testing.expect(registry.allows(try fx.join(&buf, "inside/new-file.txt")));
    try testing.expect(!registry.allows(try fx.join(&buf, "inside/../outside.txt")));
    try testing.expect(!registry.allows(fx.path()));
    try testing.expect(!registry.allows("/etc/passwd"));
    try testing.expect(!registry.allows("inside/deep"));
}

test "a symbolic link pointing outside is refused" {
    var fx = try Fixture.init();
    defer fx.tmp.cleanup();
    try fx.tmp.dir.createDirPath(testing.io, "inside");
    var registry = Registry.init(testing.allocator);
    defer registry.deinit();

    var buf: [1024]u8 = undefined;
    var link: [1024]u8 = undefined;
    const link_path = try std.fmt.bufPrintZ(&link, "{s}/inside/escape", .{fx.path()});
    try testing.expectEqual(@as(c_int, 0), c.symlink("/etc", link_path.ptr));
    _ = try registry.authorize(try fx.join(&buf, "inside"));
    try testing.expect(!registry.allows(link_path));
    try testing.expect(!registry.allows(try fx.join(&buf, "inside/escape/hosts")));
}

test "a sibling with the same prefix is refused" {
    var fx = try Fixture.init();
    defer fx.tmp.cleanup();
    try fx.tmp.dir.createDirPath(testing.io, "work");
    try fx.tmp.dir.createDirPath(testing.io, "workshop");
    var registry = Registry.init(testing.allocator);
    defer registry.deinit();

    var buf: [1024]u8 = undefined;
    _ = try registry.authorize(try fx.join(&buf, "work"));
    try testing.expect(!registry.allows(try fx.join(&buf, "workshop")));
    try testing.expect(!registry.allows(try fx.join(&buf, "workshop/file")));
}

test "authorizing keeps one entry per directory and refuses files and missing paths" {
    var fx = try Fixture.init();
    defer fx.tmp.cleanup();
    try fx.tmp.dir.createDirPath(testing.io, "a");
    try fx.tmp.dir.writeFile(testing.io, .{ .sub_path = "file.txt", .data = "x" });
    var registry = Registry.init(testing.allocator);
    defer registry.deinit();

    var buf: [1024]u8 = undefined;
    const first = try registry.authorize(try fx.join(&buf, "a"));
    const again = try registry.authorize(try fx.join(&buf, "a/."));
    try testing.expectEqual(first.ptr, again.ptr);
    try testing.expectEqual(@as(usize, 1), registry.roots.items.len);
    try testing.expectError(error.NotDirectory, registry.authorize(try fx.join(&buf, "file.txt")));
    try testing.expectError(error.NotFound, registry.authorize(try fx.join(&buf, "missing/x")));
}
