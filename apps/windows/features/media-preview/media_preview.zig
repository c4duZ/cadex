//! The media-preview feature (docs/spec/media-preview.md): images natively
//! (WIC and Direct2D), GIF, SVG, video, audio and PDF through WebView2
//! (docs/adr/0014-webview2-on-windows.md).

const std = @import("std");
const tabs = @import("tabs");
const webview = @import("webview");

pub const Media = @import("document.zig").Media;
pub const Host = @import("document.zig").Host;
pub const Kind = @import("kind.zig").Kind;
pub const Current = @import("commands.zig").Current;
pub const register = @import("commands.zig").register;
pub const formatBytes = @import("image.zig").formatBytes;

/// Which viewer `path` opens in, by extension; null: the editor's.
pub const kindOf = @import("kind.zig").of;

/// A media tab's document for `path` (absolute), or null when the file is
/// not media (kindOf); the tabs own it from here (Document.destroy).
pub fn open(gpa: std.mem.Allocator, host: Host, env: *webview.Environment, path: []const u8) !?tabs.Document {
    const kind = kindOf(path) orelse return null;
    const m = try Media.create(gpa, host, env, path, kind);
    return m.document();
}

test {
    _ = @import("kind.zig");
    _ = @import("zoom.zig");
    _ = @import("image.zig");
    _ = @import("page.zig");
    _ = @import("document.zig");
    _ = @import("commands.zig");
}

test {
    @import("win32").refAllDeep(@This());
}
