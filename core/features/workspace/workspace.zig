//! Entry point of the workspace feature: which directories the user opened,
//! and the check every file operation passes (docs/spec/workspace.md).

const std = @import("std");

pub const paths = @import("paths.zig");
pub const Registry = @import("authorized.zig").Registry;
pub const Error = @import("authorized.zig").Error;
pub const launchDirectory = @import("launch.zig").launchDirectory;
pub const wsl = @import("wsl.zig");

/// The registry of this process, shared by the C API, the explorer and the
/// search. The app has one set of authorized directories per run.
var process_registry: Registry = .init(std.heap.c_allocator);

pub fn registry() *Registry {
    return &process_registry;
}

test {
    _ = paths;
    _ = @import("authorized.zig");
    _ = @import("launch.zig");
    _ = @import("wsl.zig");
}
