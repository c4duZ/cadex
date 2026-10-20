//! Web pages inside panes (docs/adr/0014-webview2-on-windows.md): WebView2
//! child windows over the Direct2D surface, for the preview, the rendered
//! Markdown and the media WebView2 plays (video, audio, PDF). Never the
//! interface of the app (docs/adr/0012-windows-zig-win32-d3d11.md).
//!
//! The app makes one Environment for its window, calls endFrame after
//! each frame and parentMoved when the window moves; each document makes a
//! View, places it every frame it draws and reads its events with poll.

pub const Environment = @import("environment.zig").Environment;
pub const Host = @import("environment.zig").Host;
pub const State = @import("environment.zig").State;
pub const View = @import("view.zig").View;
pub const Options = @import("view.zig").Options;
pub const Event = @import("events.zig").Event;
pub const Finished = @import("events.zig").Finished;
pub const Page = @import("events.zig").Page;
pub const Serve = @import("resources.zig").Serve;
pub const Served = @import("resources.zig").Served;
pub const mimeOf = @import("resources.zig").mimeOf;
pub const urls = @import("urls.zig");
pub const errors = @import("errors.zig");

test {
    _ = @import("com.zig");
    _ = @import("strings.zig");
    _ = @import("loader.zig");
    _ = @import("environment.zig");
    _ = @import("view.zig");
    _ = @import("handlers.zig");
    _ = @import("events.zig");
    _ = @import("resources.zig");
    _ = @import("urls.zig");
    _ = @import("errors.zig");
    _ = @import("sdk/iids.zig");
}

test {
    @import("win32").refAllDeep(@This());
}
