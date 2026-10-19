//! Entry point of the terminal feature. Other features and the C API use
//! only what is re-exported here.

pub const Model = @import("model.zig").Model;

test {
    @import("std").testing.refAllDecls(@This());
    _ = @import("model.zig");
}
