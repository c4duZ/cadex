//! Entry point of the worktrees feature: a task's worktree, made and taken
//! away through the user's `git`, with the files outside git it needs
//! (docs/spec/worktrees.md, plan 19 phase D).

pub const tasks = @import("tasks.zig");
pub const include = @import("include.zig");

test {
    _ = include;
    _ = @import("worktrees_test.zig");
}
