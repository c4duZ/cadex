//! The file system the features use, the same on the Mac and on Windows:
//! `fs_posix.zig` (libc) or `fs_windows.zig` (Win32), picked here once.
//! Paths are UTF-8 on both. Used by the workspace, explorer, search,
//! Markdown, source control and the terminal's links.

const std = @import("std");
const builtin = @import("builtin");

const impl = if (builtin.os.tag == .windows) @import("fs_windows.zig") else @import("fs_posix.zig");

pub const max_path = impl.max_path;
pub const Buffer = [max_path]u8;
/// The separator of the paths this system hands out.
pub const sep = std.fs.path.sep;

pub const Error = error{
    NotFound,
    PermissionDenied,
    AlreadyExists,
    NotDirectory,
    IsDirectory,
    /// Moving across volumes, which a rename cannot do.
    CrossDevice,
    NameTooLong,
    OutOfMemory,
    Unexpected,
};

pub const Kind = enum(u8) { file = 0, directory = 1, symlink = 2, other = 3 };

pub const Info = struct {
    kind: Kind,
    /// Bytes, for files; 0 otherwise.
    size: u64,
    /// Permission bits (0o755); 0 on Windows, which has none.
    mode: u32,
};

pub const OpenOptions = struct {
    /// false fails on a symbolic link instead of opening what it points to.
    follow: bool = true,
};

pub const DirEntry = struct { name: []const u8, kind: Kind, size: u64 };

/// The canonical path of an existing `path` (links, `.` and `..`
/// resolved), in `out`; null when it does not exist.
pub const realPath = impl.realPath;
/// What is at `path`, following a last link or not; null when nothing is.
pub const info = impl.info;
pub const File = impl.File;
/// A new empty file; error.AlreadyExists when the name is taken.
pub const createNew = impl.createNew;
pub const makeDirectory = impl.makeDirectory;
/// `exclusive` refuses a taken `to`; otherwise `to` is replaced (which
/// also allows a change of case only).
pub const rename = impl.rename;
/// Copies a file or a folder with everything in it to `to`, which must
/// not exist. Links are copied as links.
pub const copyTree = impl.copyTree;
pub const writeThenRename = impl.writeThenRename;
pub const processId = impl.processId;
/// A folder's entries, one at a time: `open`, `next`, `close`.
pub const DirReader = impl.DirReader;

/// Whether something (a link counts, even a broken one) is at `path`.
pub fn exists(path: []const u8) bool {
    return info(path, false) != null;
}

pub fn isDirectory(path: []const u8) bool {
    const found = info(path, true) orelse return false;
    return found.kind == .directory;
}

/// Fills `out` from the file until it is full or the file ends; the count
/// read. A file that shrinks while read gives what was there.
pub fn readAll(file: File, out: []u8) Error!usize {
    var at: usize = 0;
    while (at < out.len) {
        const n = try file.read(out[at..]);
        if (n == 0) break;
        at += n;
    }
    return at;
}

/// Appends the file to `list` until it ends or `list` passes `limit`
/// bytes (the caller sees it passed and treats the file as too big).
pub fn appendUpTo(gpa: std.mem.Allocator, file: File, list: *std.ArrayList(u8), limit: usize) (Error || error{OutOfMemory})!void {
    var chunk: [64 * 1024]u8 = undefined;
    while (list.items.len <= limit) {
        const n = file.read(&chunk) catch return;
        if (n == 0) return;
        try list.appendSlice(gpa, chunk[0..n]);
    }
}

/// `dir` and `name` joined by this system's separator, in `out`.
pub fn join(out: []u8, dir: []const u8, name: []const u8) error{NameTooLong}![]const u8 {
    const separator: []const u8 = if (dir.len > 0 and isSeparator(dir[dir.len - 1])) "" else &.{sep};
    return std.fmt.bufPrint(out, "{s}{s}{s}", .{ dir, separator, name }) catch error.NameTooLong;
}

pub fn isSeparator(byte: u8) bool {
    return byte == '/' or (builtin.os.tag == .windows and byte == '\\');
}

const testing = std.testing;
const TestDir = @import("test_dir.zig").TestDir;

test "reads, renames, copies and lists through the system" {
    var dir = try TestDir.init();
    defer dir.deinit();
    try dir.writeFile("a.txt", "hello");
    try dir.makeDir("sub/deep");
    try dir.writeFile("sub/deep/b.txt", "bb");

    var buf: Buffer = undefined;
    const a = try join(&buf, dir.path(), "a.txt");
    const found = info(a, true).?;
    try testing.expectEqual(Kind.file, found.kind);
    try testing.expectEqual(@as(u64, 5), found.size);

    const file = try File.openRead(a, .{});
    var bytes: [16]u8 = undefined;
    try testing.expectEqualStrings("hello", bytes[0..try readAll(file, &bytes)]);
    file.close();

    var to_buf: Buffer = undefined;
    const renamed = try join(&to_buf, dir.path(), "c.txt");
    try rename(a, renamed, true);
    try testing.expect(!exists(a) and exists(renamed));
    try testing.expectError(error.AlreadyExists, createNew(renamed));

    var sub_buf: Buffer = undefined;
    var copy_buf: Buffer = undefined;
    try copyTree(try join(&sub_buf, dir.path(), "sub"), try join(&copy_buf, dir.path(), "sub2"));
    try testing.expect(dir.exists("sub2/deep/b.txt"));

    var names: std.ArrayList([]const u8) = .empty;
    defer {
        for (names.items) |n| testing.allocator.free(n);
        names.deinit(testing.allocator);
    }
    var reader = try DirReader.open(dir.path());
    defer reader.close();
    while (reader.next()) |entry| try names.append(testing.allocator, try testing.allocator.dupe(u8, entry.name));
    try testing.expectEqual(@as(usize, 3), names.items.len);
}

test "real paths resolve dots; missing paths give null" {
    var dir = try TestDir.init();
    defer dir.deinit();
    try dir.makeDir("x");
    var in: Buffer = undefined;
    var out: Buffer = undefined;
    const dotted = try std.fmt.bufPrint(&in, "{s}{c}x{c}..{c}x", .{ dir.path(), sep, sep, sep });
    var expected: Buffer = undefined;
    try testing.expectEqualStrings(try join(&expected, dir.path(), "x"), realPath(dotted, &out).?);
    try testing.expect(realPath(try join(&in, dir.path(), "missing"), &out) == null);
}
