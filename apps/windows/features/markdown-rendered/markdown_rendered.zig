//! The rendered Markdown (docs/spec/markdown.md, docs/adr/0010-markdown-rendering.md):
//! the core's HTML in a WebView2 page, links back to the app. The editing
//! side (autocomplete, broken links, backlinks) and the commands that
//! switch between text and page (markdown.toggle-preview) belong to the
//! markdown feature, which makes a Rendered and draws it in its document.

const std = @import("std");
const tabs = @import("tabs");
const webview = @import("webview");

pub const Rendered = @import("rendered.zig").Rendered;
pub const Host = @import("rendered.zig").Host;
pub const Look = @import("look.zig").Look;
pub const Link = @import("links.zig").Link;
pub const classify = @import("links.zig").classify;

/// A rendered note as a pane of its own ("markdown.openAs": rendered);
/// `text` null reads the file.
pub fn open(gpa: std.mem.Allocator, host: Host, env: *webview.Environment, path: []const u8, text: ?[]const u8, look: Look) !tabs.Document {
    const r = try Rendered.create(gpa, host, env, path, text, look);
    return r.document();
}

test {
    _ = @import("look.zig");
    _ = @import("links.zig");
    _ = @import("rendered.zig");
}

test {
    @import("win32").refAllDeep(@This());
}
