//! Canonical paths and the "is this inside that" test the workspace rules
//! rest on (docs/spec/workspace.md). Every path is resolved with realpath
//! before it is compared, so `..`, `.` and symbolic links cannot leave a root.

const std = @import("std");
const c = std.c;

pub const max_path = c.PATH_MAX;
pub const Buffer = [max_path]u8;

pub const Error = error{ NotAbsolute, NotFound, NameInvalid, NameTooLong };

/// The real path of `path`, which must be absolute. A path that does not
/// exist yet (a file about to be created) resolves through its parent: the
/// parent must exist and the last component is appended as given. The
/// result lives in `out`.
pub fn canonicalize(path: []const u8, out: *Buffer) Error![]const u8 {
    if (path.len == 0 or path[0] != '/') return error.NotAbsolute;
    if (resolveExisting(path, out)) |real| return real;
    return canonicalizeEntry(path, out);
}

/// Like canonicalize, but the last component is kept as given, not
/// followed: renaming, moving or deleting a symbolic link acts on the link,
/// not on what it points to. Only the parent folder is resolved.
pub fn canonicalizeEntry(path: []const u8, out: *Buffer) Error![]const u8 {
    if (path.len == 0 or path[0] != '/') return error.NotAbsolute;
    const trimmed = std.mem.trimEnd(u8, path, "/");
    const name = std.fs.path.basename(trimmed);
    if (!isPlainName(name)) return error.NameInvalid;
    const parent = std.fs.path.dirname(trimmed) orelse return error.NotFound;
    const real_parent = resolveExisting(parent, out) orelse return error.NotFound;
    const separator: usize = if (std.mem.eql(u8, real_parent, "/")) 0 else 1;
    const len = real_parent.len + separator + name.len;
    if (len >= max_path) return error.NameTooLong;
    if (separator == 1) out[real_parent.len] = '/';
    @memcpy(out[real_parent.len + separator ..][0..name.len], name);
    return out[0..len];
}

/// realpath(3) of an existing path, or null.
fn resolveExisting(path: []const u8, out: *Buffer) ?[]const u8 {
    var z: Buffer = undefined;
    if (path.len >= max_path) return null;
    @memcpy(z[0..path.len], path);
    z[path.len] = 0;
    const real = c.realpath(@ptrCast(&z), out) orelse return null;
    return std.mem.span(real);
}

/// `path` NUL-terminated in `out`, for the libc calls.
pub fn terminate(path: []const u8, out: *Buffer) error{NameTooLong}![:0]const u8 {
    if (path.len >= max_path) return error.NameTooLong;
    @memcpy(out[0..path.len], path);
    out[path.len] = 0;
    return out[0..path.len :0];
}

/// Whether an existing canonical path is a directory.
pub fn isDirectory(real: []const u8) bool {
    var z: Buffer = undefined;
    if (real.len >= max_path) return false;
    @memcpy(z[0..real.len], real);
    z[real.len] = 0;
    const dir = c.opendir(@ptrCast(&z)) orelse return false;
    _ = c.closedir(dir);
    return true;
}

/// A single file name: not empty, not `.` or `..`, no slash or NUL.
pub fn isPlainName(name: []const u8) bool {
    if (name.len == 0) return false;
    if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) return false;
    return std.mem.indexOfAny(u8, name, "/\x00") == null;
}

/// Whether canonical `path` is `root` or below it. Compares whole
/// components: /work does not contain /workshop.
pub fn isWithin(root: []const u8, path: []const u8) bool {
    if (!std.mem.startsWith(u8, path, root)) return false;
    if (path.len == root.len) return true;
    if (std.mem.eql(u8, root, "/")) return true;
    return path[root.len] == '/';
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
    var buf: Buffer = undefined;
    try testing.expectEqualStrings("/etc", try canonicalizeEntry("/etc", &buf));
    try testing.expectEqualStrings("/private/tmp/x", try canonicalizeEntry("/tmp/x/", &buf));
    try testing.expectError(error.NameInvalid, canonicalizeEntry("/", &buf));
}
