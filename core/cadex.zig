//! Root of the Cadex core and of its C API (include/cadex.h). Each feature
//! exports its C functions from its own c_api.zig; importing them here
//! puts them in the library.

pub const status = @import("status.zig");
pub const terminal = @import("features/terminal/terminal.zig");
pub const search = @import("features/search/search.zig");
pub const workspace = @import("features/workspace/workspace.zig");

comptime {
    _ = @import("features/terminal/c_api.zig");
    _ = @import("features/terminal/c_api_view.zig");
    _ = @import("features/search/c_api.zig");
    _ = @import("features/workspace/c_api.zig");
}

test {
    _ = status;
    _ = terminal;
    _ = search;
    _ = workspace;
    _ = @import("features/terminal/c_api_test.zig");
}
