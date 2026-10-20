//! The preview feature (docs/spec/preview.md): the page of a local server
//! or any web address in a tab, through WebView2 (shared/webview). The
//! offer "Abrir no preview" is the terminal's; the app routes it to `open`.

const std = @import("std");
const tabs = @import("tabs");
const webview = @import("webview");

pub const Preview = @import("document.zig").Preview;
pub const Host = @import("document.zig").Host;
pub const Current = @import("commands.zig").Current;
pub const register = @import("commands.zig").register;
pub const address = @import("address.zig");

/// A preview tab's document for `url` ("" for a blank one); the tabs own
/// it from here (Document.destroy).
pub fn open(gpa: std.mem.Allocator, host: Host, env: *webview.Environment, url: []const u8) !tabs.Document {
    const p = try Preview.create(gpa, host, env, url);
    return p.document();
}

/// The identity a preview of `url` would have, to find its tab before
/// opening another (the terminal's offer reloads the tab already there).
pub fn identityFor(gpa: std.mem.Allocator, url: []const u8) ![]u8 {
    return address.identity(gpa, url);
}

test {
    _ = @import("address.zig");
    _ = @import("document.zig");
    _ = @import("commands.zig");
}

test {
    @import("win32").refAllDeep(@This());
}
