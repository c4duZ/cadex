//! Saving a file from the editor (docs/spec/editor.md): only inside an
//! authorized directory, written to a temporary file next to it and then
//! renamed over it, so a crash never leaves half a file. A symbolic link
//! stays a link; the file it points to is replaced.

const std = @import("std");
const c = std.c;
const workspace = @import("../workspace/workspace.zig");
const errors = @import("errors.zig");

const paths = workspace.paths;
pub const Error = errors.Error;

extern "c" fn fchmod(fd: c.fd_t, mode: c.mode_t) c_int;
extern "c" fn fsync(fd: c.fd_t) c_int;

pub fn writeText(registry: *workspace.Registry, path: []const u8, data: []const u8) Error!void {
    var buf: paths.Buffer = undefined;
    const real = try registry.resolve(path, &buf);
    var z_buf: paths.Buffer = undefined;
    const z = try paths.terminate(real, &z_buf);
    // Keep the permissions of the file being replaced (a script stays executable).
    var st: c.Stat = undefined;
    const mode: c.mode_t = if (c.fstatat(c.AT.FDCWD, z.ptr, &st, 0) == 0) st.mode & 0o7777 else 0o644;

    var tmp_buf: paths.Buffer = undefined;
    const dir = std.fs.path.dirname(real) orelse return error.NameInvalid;
    const tmp = std.fmt.bufPrintZ(&tmp_buf, "{s}/.{s}.cadex-save-{d}", .{ dir, std.fs.path.basename(real), c.getpid() }) catch return error.NameTooLong;
    const fd = c.open(tmp.ptr, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true, .CLOEXEC = true }, @as(c.mode_t, 0o600));
    if (fd < 0) return errors.fromErrno();
    var ok = false;
    defer if (!ok) {
        _ = c.unlink(tmp.ptr);
    };
    {
        defer _ = c.close(fd);
        var at: usize = 0;
        while (at < data.len) {
            const n = c.write(fd, data[at..].ptr, data.len - at);
            if (n < 0) {
                if (c.errno(n) == .INTR) continue;
                return errors.fromErrno();
            }
            at += @intCast(n);
        }
        if (fchmod(fd, mode) != 0 or fsync(fd) != 0) return errors.fromErrno();
    }
    if (c.rename(tmp.ptr, z.ptr) != 0) return errors.fromErrno();
    ok = true;
}

const testing = std.testing;
const TestDir = @import("../../shared/test_dir.zig").TestDir;

test "saves over a file keeping its mode, and refuses outside" {
    var dir = try TestDir.init();
    defer dir.deinit();
    try dir.writeFile("run.sh", "old");
    _ = c.chmod((try dir.join("run.sh")).ptr, 0o755);
    var registry = workspace.Registry.init(testing.allocator);
    defer registry.deinit();
    _ = try registry.authorize(dir.path());

    try writeText(&registry, try dir.join("run.sh"), "#!/bin/sh\necho new\n");
    const text = try @import("read.zig").readText(testing.allocator, &registry, try dir.join("run.sh"), 1024);
    defer testing.allocator.free(text);
    try testing.expectEqualStrings("#!/bin/sh\necho new\n", text);
    var st: c.Stat = undefined;
    try testing.expectEqual(@as(c_int, 0), c.fstatat(c.AT.FDCWD, (try dir.join("run.sh")).ptr, &st, 0));
    try testing.expectEqual(@as(c.mode_t, 0o755), st.mode & 0o777);
    try writeText(&registry, try dir.join("new.md"), "# new\n");
    try testing.expect(dir.exists("new.md"));
    try testing.expectError(error.Outside, writeText(&registry, "/private/tmp/cadex-outside.txt", "x"));
}
