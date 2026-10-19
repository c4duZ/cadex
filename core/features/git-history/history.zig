//! Entry point of the git-history feature: the log in pages with the graph
//! in lanes, a commit's details and its address on the remote, through the
//! user's `git` (docs/spec/git-history.md). The diff of a file in a commit
//! is source-control's (`diff.commitSides`), so the app has one diff tab.

pub const graph = @import("graph.zig");
pub const log = @import("log.zig");
pub const details = @import("details.zig");
pub const remote = @import("remote.zig");

test {
    _ = log;
    _ = details;
    _ = remote;
    _ = @import("graph_test.zig");
    _ = @import("history_test.zig");
}
