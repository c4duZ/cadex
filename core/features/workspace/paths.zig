//! Canonical paths and the "is this inside that" test the workspace rules
//! rest on (docs/spec/workspace.md). Every path is resolved with realpath
//! before it is compared, so `..`, `.` and symbolic links cannot leave a root.

const std = @import("std");
const builtin = @import("builtin");
const fs = @import("../../shared/fs.zig");

pub const max_path = fs.max_path;
pub const Buffer = fs.Buffer;

pub const Error = error{ NotAbsolute, NotFound, NameInvalid, NameTooLong };

/// The real path of `path`, which must be absolute. A path that does not
/// exist yet (a file about to be created) resolves through its parent: the
/// parent must exist and the last component is appended as given. The
/// result lives in `out`.
pub fn canonicalize(path: []const u8, out: *Buffer) Error![]const u8 {
    if (!std.fs.path.isAbsolute(path)) return error.NotAbsolute;
    if (resolveExisting(path, out)) |real| return real;
    return canonicalizeEntry(path, out);
}

/// Like canonicalize, but the last component is kept as given, not
/// followed: renaming, moving or deleting a symbolic link acts on the link,
/// not on what it points to. Only the parent folder is resolved.
pub fn canonicalizeEntry(path: []const u8, out: *Buffer) Error![]const u8 {
    if (!std.fs.path.isAbsolute(path)) return error.NotAbsolute;
    const trimmed = std.mem.trimEnd(u8, path, separators);
    const name = std.fs.path.basename(trimmed);
    if (!isPlainName(name)) return error.NameInvalid;
    const parent = std.fs.path.dirname(trimmed) orelse return error.NotFound;
    const real_parent = resolveExisting(parent, out) orelse return error.NotFound;
    // A root ("/", "C:\\") already ends in its separator.
    const separator: usize = if (fs.isSeparator(real_parent[real_parent.len - 1])) 0 else 1;
    const len = real_parent.len + separator + name.len;
    if (len >= max_path) return error.NameTooLong;
    if (separator == 1) out[real_parent.len] = fs.sep;
    @memcpy(out[real_parent.len + separator ..][0..name.len], name);
    return out[0..len];
}

/// The real path of an existing path, or null.
fn resolveExisting(path: []const u8, out: *Buffer) ?[]const u8 {
    return fs.realPath(path, out);
}

/// Whether an existing canonical path is a directory.
pub const isDirectory = fs.isDirectory;

/// The separators trimmed off the end of a path.
const separators = if (builtin.os.tag == .windows) "/\\" else "/";

/// A single file name: not empty, not `.` or `..`, no separator or NUL;
/// on Windows, none of the characters it forbids in names either.
pub fn isPlainName(name: []const u8) bool {
    if (name.len == 0) return false;
    if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) return false;
    const forbidden = if (builtin.os.tag == .windows) "/\\:*?\"<>|\x00" else "/\x00";
    return std.mem.indexOfAny(u8, name, forbidden) == null;
}

/// Whether canonical `path` is `root` or below it. Compares whole
/// components: /work does not contain /workshop. Both come from
/// canonicalize, so on Windows they carry the disk's own case and compare
/// byte for byte.
pub fn isWithin(root: []const u8, path: []const u8) bool {
    if (!std.mem.startsWith(u8, path, root)) return false;
    if (path.len == root.len) return true;
    if (fs.isSeparator(root[root.len - 1])) return true;
    return fs.isSeparator(path[root.len]);
}

const testing = std.testing;

test "isWithin compares whole components" {
    try testing.expect(isWithin("/work", "/work"));
    try testing.expect(isWithin("/work", "/work/a/b"));
    try testing.expect(!isWithin("/work", "/workshop"));
    try testing.expect(!isWithin("/work", "/wor"));
    try testing.expect(isWithin("/", "/etc"));
}

test "plain names reject dots and slashes" {
    try testing.expect(isPlainName("main.zig"));
    try testing.expect(isPlainName(".gitignore"));
    try testing.expect(!isPlainName(".."));
    try testing.expect(!isPlainName("a/b"));
    try testing.expect(!isPlainName(""));
}

test "canonicalize resolves dots and keeps a missing last component" {
    // Mac paths; fs.zig tests the same resolution with a temporary folder.
    if (builtin.os.tag != .macos) return error.SkipZigTest;
    var buf: Buffer = undefined;
    // /tmp is a link to /private/tmp on macOS.
    const real = try canonicalize("/tmp/../tmp/./", &buf);
    try testing.expectEqualStrings("/private/tmp", real);
    const missing = try canonicalize("/tmp/cadex-does-not-exist", &buf);
    try testing.expectEqualStrings("/private/tmp/cadex-does-not-exist", missing);
    try testing.expectError(error.NotAbsolute, canonicalize("tmp", &buf));
    try testing.expectError(error.NotFound, canonicalize("/tmp/missing-dir/file", &buf));
    try testing.expectError(error.NameInvalid, canonicalize("/tmp/missing-dir/..", &buf));
}

test "canonicalizeEntry keeps the last component unresolved" {
    // Mac paths; fs.zig tests the same resolution with a temporary folder.
    if (builtin.os.tag != .macos) return error.SkipZigTest;
    var buf: Buffer = undefined;
    try testing.expectEqualStrings("/etc", try canonicalizeEntry("/etc", &buf));
    try testing.expectEqualStrings("/private/tmp/x", try canonicalizeEntry("/tmp/x/", &buf));
    try testing.expectError(error.NameInvalid, canonicalizeEntry("/", &buf));
}
