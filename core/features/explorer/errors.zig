//! The explorer's errors: the workspace's, the file system's (which maps
//! errno or GetLastError onto them, `core/shared/fs.zig`) and its own.

const workspace = @import("../workspace/workspace.zig");
const fs = @import("../../shared/fs.zig");

pub const Error = workspace.Error || fs.Error || error{
    /// Moving or copying a folder into itself.
    IntoItself,
    TooLarge,
    Binary,
};

