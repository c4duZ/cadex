//! Saving a file from the editor (docs/spec/editor.md): only inside an
//! authorized directory, written to a temporary file next to it and then
//! renamed over it, so a crash never leaves half a file. A symbolic link
//! stays a link; the file it points to is replaced.

const std = @import("std");
const builtin = @import("builtin");
const fs = @import("../../shared/fs.zig");
const workspace = @import("../workspace/workspace.zig");
const errors = @import("errors.zig");

const paths = workspace.paths;
pub const Error = errors.Error;

pub fn writeText(registry: *workspace.Registry, path: []const u8, data: []const u8) Error!void {
    var buf: paths.Buffer = undefined;
    const real = try registry.resolve(path, &buf);
    // Keep the permissions of the file being replaced (a script stays executable).
    const mode: u32 = if (fs.info(real, true)) |found| found.mode else 0o644;

    var tmp_buf: paths.Buffer = undefined;
    const dir = std.fs.path.dirname(real) orelse return error.NameInvalid;
    var tmp_name: [paths.max_path]u8 = undefined;
    const name = std.fmt.bufPrint(&tmp_name, ".{s}.cadex-save-{d}", .{ std.fs.path.basename(real), fs.processId() }) catch return error.NameTooLong;
    const tmp = try fs.join(&tmp_buf, dir, name);
    try fs.writeThenRename(tmp, real, data, mode);
}

const testing = std.testing;
const TestDir = @import("../../shared/test_dir.zig").TestDir;

test "saves over a file keeping its mode, and refuses outside" {
    var dir = try TestDir.init();
    defer dir.deinit();
    try dir.writeFile("run.sh", "old");
    if (builtin.os.tag != .windows) _ = std.c.chmod((try dir.join("run.sh")).ptr, 0o755);
    var registry = workspace.Registry.init(testing.allocator);
    defer registry.deinit();
    _ = try registry.authorize(dir.path());

    try writeText(&registry, try dir.join("run.sh"), "#!/bin/sh\necho new\n");
    const text = try @import("read.zig").readText(testing.allocator, &registry, try dir.join("run.sh"), 1024);
    defer testing.allocator.free(text);
    try testing.expectEqualStrings("#!/bin/sh\necho new\n", text);
    if (builtin.os.tag != .windows) try testing.expectEqual(@as(u32, 0o755), fs.info(try dir.join("run.sh"), true).?.mode & 0o777);
    try writeText(&registry, try dir.join("new.md"), "# new\n");
    try testing.expect(dir.exists("new.md"));
    var outside: paths.Buffer = undefined;
    try testing.expectError(error.Outside, writeText(&registry, try dir.joinInto(&outside, "../cadex-outside.txt"), "x"));
}
