//! What a page reports to its document: the queued Events (View.poll) and
//! the Page state its bar draws from, both filled by handlers.zig.

const std = @import("std");
const ui = @import("ui");

pub const Finished = struct {
    ok: bool,
    /// COREWEBVIEW2_WEB_ERROR_STATUS_* when not ok.
    status: c_int,
};

pub const Key = struct { vk: u16, mods: ui.Mods };

pub const Event = union(enum) {
    /// The page exists; earlier calls were applied.
    ready,
    /// No page will come (no runtime, no loader): why, in Portuguese.
    failed: []const u8,
    /// A new page started showing: an older error no longer applies
    /// (it stayed over the next page on the Mac, 2026-10-19).
    loading,
    finished: Finished,
    title,
    source,
    /// Back and forward changed.
    history,
    /// An address for the system browser (a new window, mailto:).
    external: []u8,
    /// A click the document routes itself (Options.links = .route).
    link: []u8,
    /// window.chrome.webview.postMessage("...") from the app's own pages.
    message: []u8,
    /// A shortcut of the app pressed in the page (Host.is_shortcut).
    key: Key,
};

pub fn eventString(e: Event) ?[]u8 {
    return switch (e) {
        .external, .link, .message => |s| s,
        else => null,
    };
}

pub fn freeEvent(gpa: std.mem.Allocator, e: Event) void {
    if (eventString(e)) |s| gpa.free(s);
}

/// What the document reads to draw its bar.
pub const Page = struct {
    title: []u8 = &.{},
    source: []u8 = &.{},
    can_back: bool = false,
    can_forward: bool = false,
    loading: bool = false,
    /// The last navigation failed with this status (cleared on the next load).
    failed_status: ?c_int = null,
    /// No page at all (Event.failed).
    failure: ?[]const u8 = null,

    pub fn deinit(self: *Page, gpa: std.mem.Allocator) void {
        gpa.free(self.title);
        gpa.free(self.source);
    }
};

test {
    @import("win32").refAllDeep(@This());
}
