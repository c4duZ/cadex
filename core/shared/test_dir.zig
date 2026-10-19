//! A fresh directory for tests that touch the disk, under .zig-cache/tmp,
//! with its canonical (realpath) path. Used by the workspace and explorer
//! tests; only compiled into tests.

const std = @import("std");
const c = std.c;
const testing = std.testing;

pub const TestDir = struct {
    tmp: testing.TmpDir,
    root: [c.PATH_MAX]u8 = undefined,
    root_len: usize = 0,
    /// Scratch for join().
    joined: [c.PATH_MAX]u8 = undefined,

    pub fn init() !TestDir {
        var self: TestDir = .{ .tmp = testing.tmpDir(.{}) };
        var rel: [c.PATH_MAX]u8 = undefined;
        const relative = try std.fmt.bufPrintZ(&rel, ".zig-cache/tmp/{s}", .{self.tmp.sub_path});
        const real = c.realpath(relative.ptr, &self.root) orelse return error.NotFound;
        self.root_len = std.mem.span(real).len;
        return self;
    }

    pub fn deinit(self: *TestDir) void {
        self.tmp.cleanup();
    }

    pub fn path(self: *const TestDir) []const u8 {
        return self.root[0..self.root_len];
    }

    /// root/sub, NUL-terminated. Valid until the next join on this TestDir.
    pub fn join(self: *TestDir, sub: []const u8) ![:0]const u8 {
        return std.fmt.bufPrintZ(&self.joined, "{s}/{s}", .{ self.path(), sub });
    }

    /// root/sub in a buffer of the caller, for keeping two paths at once.
    pub fn joinInto(self: *const TestDir, buf: []u8, sub: []const u8) ![:0]const u8 {
        return std.fmt.bufPrintZ(buf, "{s}/{s}", .{ self.path(), sub });
    }

    pub fn makeDir(self: *TestDir, sub: []const u8) !void {
        try self.tmp.dir.createDirPath(testing.io, sub);
    }

    pub fn writeFile(self: *TestDir, sub: []const u8, data: []const u8) !void {
        try self.tmp.dir.writeFile(testing.io, .{ .sub_path = sub, .data = data });
    }

    pub fn exists(self: *TestDir, sub: []const u8) bool {
        const p = self.join(sub) catch return false;
        return c.access(p.ptr, c.F_OK) == 0;
    }
};
