//! Entry point of the terminal feature. Other features and the C API use
//! only what is re-exported here.

const session = @import("session.zig");

pub const Session = session.Session;
pub const Options = session.Options;
pub const Callbacks = session.Callbacks;
pub const Size = session.Size;
pub const Frame = session.Frame;

test {
    _ = @import("model.zig");
    _ = @import("shell_env.zig");
    _ = @import("pty.zig");
    _ = @import("session.zig");
    _ = @import("session_test.zig");
    _ = @import("render.zig");
    _ = @import("render_test.zig");
}
