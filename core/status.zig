//! Status codes of the C API, shared by every feature's c_api.zig.
//! Keep in sync with the CADEX_* constants in include/cadex.h.

const std = @import("std");

pub const Code = i32;

pub const ok: Code = 0;
pub const invalid_argument: Code = 1;
pub const out_of_memory: Code = 2;
pub const spawn_failed: Code = 3;
pub const io_failed: Code = 4;
/// The path does not exist.
pub const not_found: Code = 5;
/// The path is outside every authorized directory (feature workspace).
pub const not_authorized: Code = 6;
pub const permission_denied: Code = 7;
/// The name is taken (create, rename, move).
pub const already_exists: Code = 8;
/// The file is above the size the caller accepts (feature explorer).
pub const too_large: Code = 9;
/// The file is not text (feature explorer).
pub const binary: Code = 10;

/// Maps a Zig error to the closest status the apps can act on.
pub fn fromError(err: anyerror) Code {
    return switch (err) {
        error.OutOfMemory => out_of_memory,
        error.ForkFailed => spawn_failed,
        error.NotFound, error.FileNotFound => not_found,
        error.Outside => not_authorized,
        error.PermissionDenied => permission_denied,
        error.AlreadyExists => already_exists,
        error.TooLarge => too_large,
        error.Binary => binary,
        error.NotAbsolute, error.NameInvalid, error.NameTooLong, error.NotDirectory, error.IsDirectory, error.IntoItself, error.InvalidPattern => invalid_argument,
        else => io_failed,
    };
}

/// Releases a buffer the core returned (cadex_terminal_copy_text, ...).
pub export fn cadex_free(ptr: ?*anyopaque) callconv(.c) void {
    std.c.free(ptr);
}

test "errors map to the statuses the apps act on" {
    try std.testing.expectEqual(out_of_memory, fromError(error.OutOfMemory));
    try std.testing.expectEqual(spawn_failed, fromError(error.ForkFailed));
    try std.testing.expectEqual(io_failed, fromError(error.WriteFailed));
    try std.testing.expectEqual(not_authorized, fromError(error.Outside));
    try std.testing.expectEqual(not_found, fromError(error.NotFound));
}
