//! Runs a program and collects what it prints (docs/plans/6-git.md): no
//! shell (arguments as given), a working folder, a time limit, a limit on
//! output, and extra environment variables. Used by source-control and
//! git-history to run the user's `git`. The terminal's shell is a PTY, not
//! this.

const std = @import("std");
const builtin = @import("builtin");

/// posix_spawn on the Mac, CreateProcessW in a Job Object on Windows.
const impl = if (builtin.os.tag == .windows) @import("process_windows.zig") else @import("process_posix.zig");

pub const Options = struct {
    cwd: ?[]const u8 = null,
    /// The program is killed (with its process group) after this long.
    timeout_ms: u32 = 30_000,
    /// Bytes kept of each of stdout and stderr; the rest is read and dropped.
    max_output: usize = 16 * 1024 * 1024,
    /// "NAME=value" added to the app's environment (later ones win).
    env: []const []const u8 = &.{},
    /// Bytes written to the program's stdin, then closed. Empty: /dev/null.
    stdin: []const u8 = "",
};

pub const Result = struct {
    /// Exit code; 128 + signal when killed; -1 when it could not start.
    code: i32,
    stdout: []u8,
    stderr: []u8,
    timed_out: bool,
    truncated: bool,

    pub fn deinit(self: *Result, gpa: std.mem.Allocator) void {
        gpa.free(self.stdout);
        gpa.free(self.stderr);
    }

    pub fn ok(self: Result) bool {
        return self.code == 0 and !self.timed_out;
    }
};

pub fn run(gpa: std.mem.Allocator, argv: []const []const u8, options: Options) !Result {
    return impl.run(gpa, argv, options);
}

// Each side tests itself with its own system's programs.
test {
    _ = impl;
}
