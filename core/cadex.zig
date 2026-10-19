//! Root of the Cadex core. The C API exported to the apps lives here and in
//! the entry point of each feature; see include/cadex.h.

pub const terminal = @import("features/terminal/terminal.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
