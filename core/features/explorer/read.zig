//! A file's text for the viewers, with limits: only inside an authorized
//! directory, up to a size, and not binary (docs/spec/explorer.md).

const std = @import("std");
const fs = @import("../../shared/fs.zig");
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
    const head = try read(gpa, registry, path, limit, false);
    return head.bytes;
}

pub const Head = struct { bytes: []u8, truncated: bool };

/// At most `limit` bytes from the start of the file, for showing a huge
/// file without reading all of it (docs/spec/editor.md). Binary as above.
pub fn readHead(gpa: std.mem.Allocator, registry: *workspace.Registry, path: []const u8, limit: u64) Error!Head {
    return read(gpa, registry, path, limit, true);
}

fn read(gpa: std.mem.Allocator, registry: *workspace.Registry, path: []const u8, limit: u64, head: bool) Error!Head {
    var buf: paths.Buffer = undefined;
    const file = try fs.File.openRead(try registry.resolve(path, &buf), .{});
    defer file.close();
    const found = try file.info();
    if (found.kind == .directory) return error.IsDirectory;
    const size = found.size;
    if (size > limit and !head) return error.TooLarge;

    const bytes = try gpa.alloc(u8, @intCast(@min(size, limit)));
    errdefer gpa.free(bytes);
    // The file may shrink while it is read: keep what was there.
    const got = try fs.readAll(file, bytes);
    if (std.mem.indexOfScalar(u8, bytes[0..@min(got, sniff_size)], 0) != null) return error.Binary;
    const truncated = size > limit;
    if (got == bytes.len) return .{ .bytes = bytes, .truncated = truncated };
    return .{ .bytes = try gpa.realloc(bytes, got), .truncated = truncated };
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
    const head = try readHead(testing.allocator, &registry, try dir.join("hello.txt"), 2);
    defer testing.allocator.free(head.bytes);
    try testing.expectEqualStrings("ol", head.bytes);
    try testing.expect(head.truncated);
}
