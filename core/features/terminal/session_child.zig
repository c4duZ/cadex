//! What a session's program runs on: a pty the session started itself
//! (pty.zig), or, on the Mac with terminal.keepSessions, one the terminal
//! daemon keeps (daemon_child.zig, plan 19 phase E2). Same methods; this
//! picks.

const std = @import("std");
const builtin = @import("builtin");
const pty = @import("pty.zig");

pub const has_daemon = builtin.os.tag != .windows;
pub const Remote = if (has_daemon) @import("daemon_child.zig").Child else void;

/// Where a session kept by the daemon lives: the socket, its name, and
/// whether to take it back instead of opening it.
pub const Daemon = struct { socket: []const u8, id: []const u8, attach: bool };

/// A pty of its own, or the daemon's when `daemon` is given.
pub fn start(gpa: std.mem.Allocator, size: pty.Size, cwd: ?[]const u8, shell: ?[]const u8, daemon: ?Daemon) !Child {
    const d = daemon orelse return .{ .local = try pty.Child.start(gpa, .{ .size = size, .cwd = cwd, .shell = shell }) };
    if (!has_daemon) return error.Unsupported;
    return .{ .remote = try Remote.start(gpa, .{ .socket = d.socket, .id = d.id, .attach = d.attach, .size = size, .cwd = cwd, .shell = shell }) };
}

/// The output the daemon saved for a session before the Mac restarted
/// (at most 4 MiB), and the file goes: shown once. Null when none.
pub fn takeSaved(gpa: std.mem.Allocator, path: []const u8) ?[]u8 {
    if (comptime !has_daemon) return null;
    const fs = @import("../../shared/fs.zig");
    const file = fs.File.openRead(path, .{}) catch return null;
    defer file.close();
    var bytes: std.ArrayList(u8) = .empty;
    fs.appendUpTo(gpa, file, &bytes, 4 * 1024 * 1024) catch {
        bytes.deinit(gpa);
        return null;
    };
    var z: [fs.max_path + 1]u8 = undefined;
    if (path.len < z.len) {
        @memcpy(z[0..path.len], path);
        z[path.len] = 0;
        _ = std.c.unlink(z[0..path.len :0]);
    }
    return bytes.toOwnedSlice(gpa) catch null;
}

pub const Child = union(enum) {
    local: pty.Child,
    remote: Remote,

    pub fn read(self: *Child, buf: []u8, stop: *const std.atomic.Value(bool)) ?usize {
        return switch (self.*) {
            .local => |l| l.read(buf, stop),
            .remote => |*r| if (has_daemon) r.read(buf, stop) else unreachable,
        };
    }

    pub fn write(self: *Child, bytes: []const u8) error{WriteFailed}!void {
        return switch (self.*) {
            .local => |l| l.write(bytes),
            .remote => |*r| if (has_daemon) r.write(bytes) else unreachable,
        };
    }

    pub fn resize(self: *Child, size: pty.Size) error{ResizeFailed}!void {
        return switch (self.*) {
            .local => |l| l.resize(size),
            .remote => |*r| if (has_daemon) r.resize(size) else unreachable,
        };
    }

    pub fn hasForegroundProcess(self: *Child) bool {
        return switch (self.*) {
            .local => |l| l.hasForegroundProcess(),
            .remote => |*r| if (has_daemon) r.hasForegroundProcess() else unreachable,
        };
    }

    pub fn foregroundGroup(self: *Child) i32 {
        return switch (self.*) {
            .local => |l| l.foregroundGroup(),
            .remote => |*r| if (has_daemon) r.foregroundGroup() else unreachable,
        };
    }

    /// The shell's pid (0 on Windows): the app knows a `cadex claude`
    /// typed in one of its tabs by this pid among its ancestors (plan 22,
    /// phase C). The daemon's shells are real processes too, its children.
    pub fn shellPid(self: *Child) i32 {
        return switch (self.*) {
            .local => |l| if (has_daemon) @intCast(l.pid) else 0,
            .remote => |*r| if (has_daemon) @intCast(r.pty.pid) else unreachable,
        };
    }

    pub fn currentDirectory(self: *Child, buf: *pty.DirectoryBuffer) ?[]const u8 {
        return switch (self.*) {
            .local => |l| l.currentDirectory(buf),
            .remote => |*r| if (has_daemon) r.currentDirectory(buf) else unreachable,
        };
    }

    pub fn waitExitCode(self: *Child) i32 {
        return switch (self.*) {
            .local => |l| l.waitExitCode(),
            .remote => |*r| if (has_daemon) r.waitExitCode() else unreachable,
        };
    }

    pub fn unblockReader(self: *Child) void {
        switch (self.*) {
            .local => |l| l.unblockReader(),
            .remote => {},
        }
    }

    pub fn finish(self: *Child, reaped: bool) void {
        switch (self.*) {
            .local => |l| l.finish(reaped),
            .remote => |*r| if (has_daemon) r.finish(reaped) else unreachable,
        }
    }

    pub fn kill(self: *Child) void {
        switch (self.*) {
            .local => |l| l.kill(),
            .remote => |*r| if (has_daemon) r.kill() else unreachable,
        }
    }

    /// The daemon keeps the program when the session closes (no-op locally).
    pub fn setDetach(self: *Child) void {
        switch (self.*) {
            .local => {},
            .remote => |*r| if (has_daemon) {
                r.detach = true;
            },
        }
    }
};
