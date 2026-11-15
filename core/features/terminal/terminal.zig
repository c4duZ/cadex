//! Entry point of the terminal feature. Other features and the C API use
//! only what is re-exported here.

const builtin = @import("builtin");
const session = @import("session.zig");

pub const Session = session.Session;
pub const Options = session.Options;
pub const Callbacks = session.Callbacks;
pub const Size = session.Size;
pub const Frame = session.Frame;
pub const Key = @import("input.zig").Key;
pub const Mods = @import("input.zig").Mods;
pub const Pointer = session.Pointer;
pub const Autoscroll = session.Autoscroll;
pub const quotePaths = @import("paste.zig").quotePaths;
/// Scrolling, selection, find and links on a Session (session_view.zig).
pub const view = @import("session_view.zig");

test {
    _ = @import("model.zig");
    _ = @import("shell_env.zig");
    _ = @import("shell_windows.zig");
    _ = @import("pty.zig");
    _ = @import("session.zig");
    _ = @import("session_test.zig");
    _ = @import("render.zig");
    _ = @import("render_test.zig");
    _ = @import("input.zig");
    _ = @import("selection.zig");
    _ = @import("selection_test.zig");
    _ = @import("paste.zig");
    _ = @import("link_detect.zig");
    _ = @import("links.zig");
    _ = @import("search.zig");
    _ = @import("search_test.zig");
    _ = @import("links_test.zig");
    _ = @import("agent_status_test.zig");
    _ = @import("mouse.zig");
    _ = @import("local_url.zig");
    // The daemon is the Mac's for now (docs/adr/0022-terminal-daemon.md).
    if (builtin.os.tag != .windows) {
        _ = @import("daemon_ring.zig");
        _ = @import("daemon_modes.zig");
        _ = @import("daemon_wire.zig");
        _ = @import("daemon_test.zig");
    }
}
