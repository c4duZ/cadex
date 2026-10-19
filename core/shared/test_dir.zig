//! A fresh directory for tests that touch the disk, under .zig-cache/tmp,
//! with its canonical (realpath) path. Used by the workspace and explorer
//! tests; only compiled into tests.

const std = @import("std");
const builtin = @import("builtin");
const fs = @import("fs.zig");
const testing = std.testing;

pub const TestDir = struct {
    tmp: testing.TmpDir,
    root: fs.Buffer = undefined,
    root_len: usize = 0,
    /// Scratch for join().
    joined: fs.Buffer = undefined,

    pub fn init() !TestDir {
        var self: TestDir = .{ .tmp = testing.tmpDir(.{}) };
        var rel: fs.Buffer = undefined;
        const relative = try std.fmt.bufPrint(&rel, ".zig-cache/tmp/{s}", .{self.tmp.sub_path});
        const real = fs.realPath(relative, &self.root) orelse return error.NotFound;
        self.root_len = real.len;
        return self;
    }

    pub fn deinit(self: *TestDir) void {
        self.tmp.cleanup();
    }

    pub fn path(self: *const TestDir) []const u8 {
        return self.root[0..self.root_len];
    }

    /// root/sub, NUL-terminated, with this system's separators (tests
    /// write "a/b"). Valid until the next join on this TestDir.
    pub fn join(self: *TestDir, sub: []const u8) ![:0]const u8 {
        return self.joinInto(&self.joined, sub);
    }

    /// root/sub in a buffer of the caller, for keeping two paths at once.
    pub fn joinInto(self: *const TestDir, buf: []u8, sub: []const u8) ![:0]const u8 {
        const out = try std.fmt.bufPrintZ(buf, "{s}{c}{s}", .{ self.path(), fs.sep, sub });
        if (fs.sep != '/') std.mem.replaceScalar(u8, out, '/', fs.sep);
        return out;
    }

    pub fn makeDir(self: *TestDir, sub: []const u8) !void {
        try self.tmp.dir.createDirPath(testing.io, sub);
    }

    pub fn writeFile(self: *TestDir, sub: []const u8, data: []const u8) !void {
        try self.tmp.dir.writeFile(testing.io, .{ .sub_path = sub, .data = data });
    }

    pub fn exists(self: *TestDir, sub: []const u8) bool {
        return fs.exists(self.join(sub) catch return false);
    }

    /// A symbolic link at `sub` to the folder `target`. Windows makes links
    /// only in Developer Mode or as administrator: the test is skipped
    /// otherwise.
    pub fn symlinkToDirectory(self: *TestDir, target: []const u8, sub: []const u8) !void {
        const flags: std.Io.Dir.SymLinkFlags = .{ .is_directory = true };
        if (builtin.os.tag == .windows) {
            self.tmp.dir.symLink(testing.io, target, sub, flags) catch return error.SkipZigTest;
        } else {
            try self.tmp.dir.symLink(testing.io, target, sub, flags);
        }
    }
};
