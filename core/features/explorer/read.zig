//! A file's text for the viewers, with limits: only inside an authorized
//! directory, up to a size, and not binary (docs/spec/explorer.md).

const std = @import("std");
const c = std.c;
const workspace = @import("../workspace/workspace.zig");
const errors = @import("errors.zig");

const paths = workspace.paths;
pub const Error = errors.Error;

/// What the viewers accept by default.
pub const max_text_size: u64 = 10 * 1024 * 1024;
/// A NUL byte in this much of the start means binary, as git decides.
const sniff_size = 8 * 1024;

/// The file's bytes, owned by the caller. TooLarge above `limit`; Binary
/// when a NUL byte shows up in the first 8 KB.
pub fn readText(gpa: std.mem.Allocator, registry: *workspace.Registry, path: []const u8, limit: u64) Error![]u8 {
    var buf: paths.Buffer = undefined;
    var z_buf: paths.Buffer = undefined;
    const z = try paths.terminate(try registry.resolve(path, &buf), &z_buf);
    const fd = c.open(z.ptr, .{ .ACCMODE = .RDONLY, .CLOEXEC = true });
    if (fd < 0) return errors.fromErrno();
    defer _ = c.close(fd);
    var st: c.Stat = undefined;
    if (c.fstat(fd, &st) != 0) return errors.fromErrno();
    if (st.mode & c.S.IFMT == c.S.IFDIR) return error.IsDirectory;
    const size: u64 = @intCast(st.size);
    if (size > limit) return error.TooLarge;

    const bytes = try gpa.alloc(u8, @intCast(size));
    errdefer gpa.free(bytes);
    // The file may shrink while it is read: keep what was there.
    const got = try readAll(fd, bytes);
    if (std.mem.indexOfScalar(u8, bytes[0..@min(got, sniff_size)], 0) != null) return error.Binary;
    if (got == bytes.len) return bytes;
    return gpa.realloc(bytes, got);
}

fn readAll(fd: c.fd_t, out: []u8) Error!usize {
    var at: usize = 0;
    while (at < out.len) {
        const n = c.read(fd, out[at..].ptr, out.len - at);
        if (n < 0) {
            if (c.errno(n) == .INTR) continue;
            return errors.fromErrno();
        }
        if (n == 0) break;
        at += @intCast(n);
    }
    return at;
}

const testing = std.testing;
const TestDir = @import("../../shared/test_dir.zig").TestDir;

test "reads text and refuses binary, oversized and outside files" {
    var dir = try TestDir.init();
    defer dir.deinit();
    try dir.writeFile("hello.txt", "olá\n");
    try dir.writeFile("image.bin", "PNG\x00\x01");
    try dir.writeFile("empty.txt", "");
    var registry = workspace.Registry.init(testing.allocator);
    defer registry.deinit();
    _ = try registry.authorize(dir.path());

    const text = try readText(testing.allocator, &registry, try dir.join("hello.txt"), max_text_size);
    defer testing.allocator.free(text);
    try testing.expectEqualStrings("olá\n", text);
    const empty = try readText(testing.allocator, &registry, try dir.join("empty.txt"), max_text_size);
    defer testing.allocator.free(empty);
    try testing.expectEqual(@as(usize, 0), empty.len);
    try testing.expectError(error.Binary, readText(testing.allocator, &registry, try dir.join("image.bin"), max_text_size));
    try testing.expectError(error.TooLarge, readText(testing.allocator, &registry, try dir.join("hello.txt"), 2));
    try testing.expectError(error.IsDirectory, readText(testing.allocator, &registry, dir.path(), max_text_size));
    try testing.expectError(error.Outside, readText(testing.allocator, &registry, "/etc/hosts", max_text_size));
}
