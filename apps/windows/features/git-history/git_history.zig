//! The git-history feature (docs/spec/git-history.md): a repository's log
//! with the lane graph in a pane. The app registers the commands with a
//! Host; git.history makes the HistoryDocument and hands it to the tabs.

pub const HistoryDocument = @import("document.zig").HistoryDocument;
pub const Host = @import("host.zig").Host;
pub const register = @import("commands.zig").register;

test {
    _ = @import("log.zig");
    _ = @import("dates.zig");
    _ = @import("worker.zig");
    _ = @import("jobs.zig");
    _ = @import("host.zig");
    _ = @import("document.zig");
    _ = @import("feed.zig");
    _ = @import("view.zig");
    _ = @import("rows.zig");
    _ = @import("graph.zig");
    _ = @import("details.zig");
    _ = @import("commands.zig");
}

test {
    @import("win32").refAllDeep(@This());
}
