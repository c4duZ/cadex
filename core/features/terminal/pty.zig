//! The pseudo-terminal the shell runs on: forkpty on the Mac
//! (`pty_posix.zig`), ConPTY on Windows (`pty_windows.zig`), picked here
//! once. Both give a Child with the same methods; session.zig uses only
//! these.

const std = @import("std");
const builtin = @import("builtin");

const impl = if (builtin.os.tag == .windows) @import("pty_windows.zig") else @import("pty_posix.zig");

pub const Size = struct {
    cols: u16,
    rows: u16,
    cell_width_px: u16 = 0,
    cell_height_px: u16 = 0,
};

pub const StartOptions = struct {
    size: Size,
    cwd: ?[]const u8 = null,
    /// Configured shell; empty or null falls back to the system's default.
    shell: ?[]const u8 = null,
};

/// start, read, write, resize, hasForegroundProcess, currentDirectory,
/// waitExitCode; closing is unblockReader (before joining the reader),
/// then finish. kill when the session fails to open.
pub const Child = impl.Child;
/// Scratch for Child.currentDirectory.
pub const DirectoryBuffer = impl.DirectoryBuffer;
/// The user's home folder, for links written as ~/path; may use `buf`.
pub const homeDirectory = impl.homeDirectory;

test {
    _ = impl;
}
