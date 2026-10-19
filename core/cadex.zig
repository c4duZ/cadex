//! Root of the Cadex core and of its C API (include/cadex.h). Each feature
//! exports its C functions from its own c_api.zig; importing them here
//! puts them in the library.

pub const status = @import("status.zig");
pub const terminal = @import("features/terminal/terminal.zig");
pub const search = @import("features/search/search.zig");
pub const workspace = @import("features/workspace/workspace.zig");
pub const explorer = @import("features/explorer/explorer.zig");

comptime {
    _ = @import("features/terminal/c_api.zig");
    _ = @import("features/terminal/c_api_view.zig");
    _ = @import("features/search/c_api.zig");
    _ = @import("features/search/c_api_files.zig");
    _ = @import("features/search/c_api_content.zig");
    _ = @import("features/workspace/c_api.zig");
    _ = @import("features/explorer/c_api.zig");
    _ = @import("features/explorer/c_api_watch.zig");
}

test {
    _ = status;
    _ = terminal;
    _ = search;
    _ = workspace;
    _ = explorer;
    _ = @import("features/terminal/c_api_test.zig");
    _ = @import("shared/c_buffer.zig");
    _ = @import("shared/glob.zig");
    _ = @import("shared/ignore.zig");
}
