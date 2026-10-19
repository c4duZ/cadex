//! Entry point of the source-control feature: the repository's state and
//! the actions on it, through the user's `git` (docs/spec/source-control.md).

pub const git = @import("git.zig");
pub const status = @import("status.zig");
pub const actions = @import("actions.zig");
pub const diff = @import("diff.zig");

test {
    _ = status;
    _ = @import("repo_test.zig");
}
