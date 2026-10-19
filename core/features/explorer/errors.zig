//! The explorer's errors and how libc's errno maps onto them.

const std = @import("std");
const workspace = @import("../workspace/workspace.zig");

pub const Error = workspace.Error || error{
    PermissionDenied,
    AlreadyExists,
    IsDirectory,
    /// Moving or copying a folder into itself.
    IntoItself,
    /// Moving across volumes, which rename(2) cannot do.
    CrossDevice,
    TooLarge,
    Binary,
    Unexpected,
};

/// The error for the errno the last failed libc call left.
pub fn fromErrno() Error {
    const e: std.c.E = @enumFromInt(std.c._errno().*);
    return switch (e) {
        .NOENT => error.NotFound,
        .ACCES, .PERM => error.PermissionDenied,
        .EXIST, .NOTEMPTY => error.AlreadyExists,
        .NOTDIR => error.NotDirectory,
        .ISDIR => error.IsDirectory,
        .XDEV => error.CrossDevice,
        .NAMETOOLONG => error.NameTooLong,
        .NOMEM => error.OutOfMemory,
        else => error.Unexpected,
    };
}
