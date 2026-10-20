//! The events of a page: what WebView2 reports, kept in the view's Page
//! and queued as Events for its document (View.poll). Each callback runs on
//! the window's thread inside WebView2's message handling; it records,
//! queues and wakes the app, and never calls into a feature.

const std = @import("std");
const w = @import("win32");
const ui = @import("ui");
const c = w.c;
const com = @import("com.zig");
const iids = @import("sdk/iids.zig");
const strings = @import("strings.zig");
const resources = @import("resources.zig");
const View = @import("view.zig").View;
const events = @import("events.zig");

pub const Event = events.Event;
pub const Key = events.Key;
pub const Page = events.Page;
pub const eventString = events.eventString;
pub const freeEvent = events.freeEvent;

pub const Tokens = struct {
    starting: c.EventRegistrationToken = .{},
    completed: c.EventRegistrationToken = .{},
    title: c.EventRegistrationToken = .{},
    source: c.EventRegistrationToken = .{},
    history: c.EventRegistrationToken = .{},
    loading: c.EventRegistrationToken = .{},
    new_window: c.EventRegistrationToken = .{},
    resource: c.EventRegistrationToken = .{},
    message: c.EventRegistrationToken = .{},
    key: c.EventRegistrationToken = .{},
};

/// The handlers of one view, counting on the view's references.
pub const Set = struct {
    starting: Starting = .{},
    completed: Completed = .{},
    title: Title = .{},
    source: Source = .{},
    history: History = .{},
    loading: Loading = .{},
    new_window: NewWindow = .{},
    resource: Resource = .{},
    message: Message = .{},
    key: KeyPressed = .{},

    const Starting = com.Handler(c.ICoreWebView2NavigationStartingEventHandler, &iids.ICoreWebView2NavigationStartingEventHandler, Set, "starting", onStarting);
    const Completed = com.Handler(c.ICoreWebView2NavigationCompletedEventHandler, &iids.ICoreWebView2NavigationCompletedEventHandler, Set, "completed", onCompleted);
    const Title = com.Handler(c.ICoreWebView2DocumentTitleChangedEventHandler, &iids.ICoreWebView2DocumentTitleChangedEventHandler, Set, "title", onTitle);
    const Source = com.Handler(c.ICoreWebView2SourceChangedEventHandler, &iids.ICoreWebView2SourceChangedEventHandler, Set, "source", onSource);
    const History = com.Handler(c.ICoreWebView2HistoryChangedEventHandler, &iids.ICoreWebView2HistoryChangedEventHandler, Set, "history", onHistory);
    const Loading = com.Handler(c.ICoreWebView2ContentLoadingEventHandler, &iids.ICoreWebView2ContentLoadingEventHandler, Set, "loading", onLoading);
    const NewWindow = com.Handler(c.ICoreWebView2NewWindowRequestedEventHandler, &iids.ICoreWebView2NewWindowRequestedEventHandler, Set, "new_window", onNewWindow);
    const Resource = com.Handler(c.ICoreWebView2WebResourceRequestedEventHandler, &iids.ICoreWebView2WebResourceRequestedEventHandler, Set, "resource", onResource);
    const Message = com.Handler(c.ICoreWebView2WebMessageReceivedEventHandler, &iids.ICoreWebView2WebMessageReceivedEventHandler, Set, "message", onMessage);
    const KeyPressed = com.Handler(c.ICoreWebView2AcceleratorKeyPressedEventHandler, &iids.ICoreWebView2AcceleratorKeyPressedEventHandler, Set, "key", onKey);

    fn view(self: *Set) *View {
        return @alignCast(@fieldParentPtr("on", self));
    }
    pub fn retain(self: *Set) void {
        self.view().retain();
    }
    pub fn release(self: *Set) void {
        self.view().release();
    }
};

/// The page's settings, from the view's options.
pub fn configure(v: *View) void {
    const web = v.web.?;
    var settings: [*c]c.ICoreWebView2Settings = null;
    if (w.call(web, "get_Settings", .{&settings}) >= 0 and settings != null) {
        defer w.release(settings);
        _ = w.call(settings, "put_IsScriptEnabled", .{@intFromBool(v.options.scripts)});
        _ = w.call(settings, "put_AreDevToolsEnabled", .{@intFromBool(v.options.devtools)});
        _ = w.call(settings, "put_AreDefaultContextMenusEnabled", .{@intFromBool(v.options.context_menus)});
        _ = w.call(settings, "put_IsWebMessageEnabled", .{@intFromBool(v.options.web_messages)});
        // No bridge from a page to the app (docs/spec/preview.md).
        _ = w.call(settings, "put_AreHostObjectsAllowed", .{0});
        // The pane says what failed itself; Edge's page would sit over it.
        _ = w.call(settings, "put_IsBuiltInErrorPageEnabled", .{0});
    }
    if (v.options.background) |bg| {
        const ctl2 = w.query(v.controller.?, c.ICoreWebView2Controller2, &iids.ICoreWebView2Controller2) catch return;
        defer w.release(ctl2);
        const color: c.COREWEBVIEW2_COLOR = .{ .A = 255, .R = channel(bg.r), .G = channel(bg.g), .B = channel(bg.b) };
        _ = w.call(ctl2, "put_DefaultBackgroundColor", .{color});
    }
}

fn channel(value: f32) u8 {
    return @intFromFloat(@round(std.math.clamp(value, 0, 1) * 255));
}

pub fn register(v: *View) void {
    const web = v.web.?;
    const t = &v.tokens;
    const s = &v.on;
    _ = w.call(web, "add_NavigationStarting", .{ s.starting.ptr(), &t.starting });
    _ = w.call(web, "add_NavigationCompleted", .{ s.completed.ptr(), &t.completed });
    _ = w.call(web, "add_DocumentTitleChanged", .{ s.title.ptr(), &t.title });
    _ = w.call(web, "add_SourceChanged", .{ s.source.ptr(), &t.source });
    _ = w.call(web, "add_HistoryChanged", .{ s.history.ptr(), &t.history });
    _ = w.call(web, "add_ContentLoading", .{ s.loading.ptr(), &t.loading });
    _ = w.call(web, "add_NewWindowRequested", .{ s.new_window.ptr(), &t.new_window });
    _ = w.call(web, "add_WebMessageReceived", .{ s.message.ptr(), &t.message });
    _ = w.call(v.controller.?, "add_AcceleratorKeyPressed", .{ s.key.ptr(), &t.key });
    if (v.options.serve) |serve| resources.register(v, serve, s.resource.ptr(), &t.resource);
}

pub fn unregister(v: *View) void {
    const web = v.web orelse return;
    const t = v.tokens;
    _ = w.call(web, "remove_NavigationStarting", .{t.starting});
    _ = w.call(web, "remove_NavigationCompleted", .{t.completed});
    _ = w.call(web, "remove_DocumentTitleChanged", .{t.title});
    _ = w.call(web, "remove_SourceChanged", .{t.source});
    _ = w.call(web, "remove_HistoryChanged", .{t.history});
    _ = w.call(web, "remove_ContentLoading", .{t.loading});
    _ = w.call(web, "remove_NewWindowRequested", .{t.new_window});
    _ = w.call(web, "remove_WebMessageReceived", .{t.message});
    _ = w.call(v.controller.?, "remove_AcceleratorKeyPressed", .{t.key});
    if (v.options.serve != null) _ = w.call(web, "remove_WebResourceRequested", .{t.resource});
}

/// Only web addresses stay in a page; file: never loads, and mailto: or
/// another app's scheme goes to the system (the Mac's rule).
pub fn staysInPage(url: []const u8) bool {
    const colon = std.mem.indexOfScalar(u8, url, ':') orelse return false;
    const scheme = url[0..colon];
    for ([_][]const u8{ "http", "https", "about", "blob", "data" }) |s| {
        if (std.ascii.eqlIgnoreCase(scheme, s)) return true;
    }
    return false;
}

fn onStarting(s: *Set, _: [*c]c.ICoreWebView2, args: [*c]c.ICoreWebView2NavigationStartingEventArgs) c.HRESULT {
    const v = s.view();
    var redirected: c.BOOL = 0;
    _ = w.call(args, "get_IsRedirected", .{&redirected});
    if (v.own_navigations > 0 and redirected == 0) v.own_navigations -= 1 else if (redirected == 0) {
        var raw: c.LPWSTR = null;
        _ = w.call(args, "get_Uri", .{&raw});
        const url = strings.take(v.gpa, raw) orelse return 0;
        switch (v.options.links) {
            .web => if (!staysInPage(url)) {
                _ = w.call(args, "put_Cancel", .{1});
                if (std.ascii.startsWithIgnoreCase(url, "file:")) v.gpa.free(url) else v.push(.{ .external = url });
                return 0;
            } else v.gpa.free(url),
            .route => {
                _ = w.call(args, "put_Cancel", .{1});
                v.push(.{ .link = url });
                return 0;
            },
        }
    }
    v.page.loading = true;
    return 0;
}

fn onCompleted(s: *Set, _: [*c]c.ICoreWebView2, args: [*c]c.ICoreWebView2NavigationCompletedEventArgs) c.HRESULT {
    const v = s.view();
    var ok: c.BOOL = 0;
    var status: c.COREWEBVIEW2_WEB_ERROR_STATUS = c.COREWEBVIEW2_WEB_ERROR_STATUS_UNKNOWN;
    _ = w.call(args, "get_IsSuccess", .{&ok});
    _ = w.call(args, "get_WebErrorStatus", .{&status});
    v.page.loading = false;
    // Cancelled: a new address replaced it, not a failure (as on the Mac).
    if (ok == 0 and status == c.COREWEBVIEW2_WEB_ERROR_STATUS_OPERATION_CANCELED) return 0;
    v.page.failed_status = if (ok != 0) null else @intCast(status);
    v.push(.{ .finished = .{ .ok = ok != 0, .status = @intCast(status) } });
    return 0;
}

fn onTitle(s: *Set, sender: [*c]c.ICoreWebView2, _: [*c]c.IUnknown) c.HRESULT {
    const v = s.view();
    var raw: c.LPWSTR = null;
    _ = w.call(sender, "get_DocumentTitle", .{&raw});
    const title = strings.take(v.gpa, raw) orelse return 0;
    v.gpa.free(v.page.title);
    v.page.title = title;
    v.push(.title);
    return 0;
}

fn onSource(s: *Set, sender: [*c]c.ICoreWebView2, _: ?*c.ICoreWebView2SourceChangedEventArgs) c.HRESULT {
    const v = s.view();
    var raw: c.LPWSTR = null;
    _ = w.call(sender, "get_Source", .{&raw});
    const source = strings.take(v.gpa, raw) orelse return 0;
    v.gpa.free(v.page.source);
    v.page.source = source;
    v.push(.source);
    return 0;
}

fn onHistory(s: *Set, sender: [*c]c.ICoreWebView2, _: [*c]c.IUnknown) c.HRESULT {
    const v = s.view();
    var back: c.BOOL = 0;
    var forward: c.BOOL = 0;
    _ = w.call(sender, "get_CanGoBack", .{&back});
    _ = w.call(sender, "get_CanGoForward", .{&forward});
    v.page.can_back = back != 0;
    v.page.can_forward = forward != 0;
    v.push(.history);
    return 0;
}

fn onLoading(s: *Set, _: [*c]c.ICoreWebView2, _: ?*c.ICoreWebView2ContentLoadingEventArgs) c.HRESULT {
    const v = s.view();
    v.page.failed_status = null;
    v.push(.loading);
    return 0;
}

/// A link that opens a new window goes to the browser (docs/spec/preview.md).
fn onNewWindow(s: *Set, _: [*c]c.ICoreWebView2, args: [*c]c.ICoreWebView2NewWindowRequestedEventArgs) c.HRESULT {
    const v = s.view();
    _ = w.call(args, "put_Handled", .{1});
    var raw: c.LPWSTR = null;
    _ = w.call(args, "get_Uri", .{&raw});
    const url = strings.take(v.gpa, raw) orelse return 0;
    if (std.ascii.startsWithIgnoreCase(url, "file:")) {
        v.gpa.free(url);
        return 0;
    }
    v.push(.{ .external = url });
    return 0;
}

fn onResource(s: *Set, _: [*c]c.ICoreWebView2, args: [*c]c.ICoreWebView2WebResourceRequestedEventArgs) c.HRESULT {
    resources.answer(s.view(), args);
    return 0;
}

fn onMessage(s: *Set, _: [*c]c.ICoreWebView2, args: [*c]c.ICoreWebView2WebMessageReceivedEventArgs) c.HRESULT {
    const v = s.view();
    var raw: c.LPWSTR = null;
    if (w.call(args, "TryGetWebMessageAsString", .{&raw}) < 0) return 0;
    const text = strings.take(v.gpa, raw) orelse return 0;
    v.push(.{ .message = text });
    return 0;
}

fn onKey(s: *Set, _: [*c]c.ICoreWebView2Controller, args: [*c]c.ICoreWebView2AcceleratorKeyPressedEventArgs) c.HRESULT {
    const v = s.view();
    const is_shortcut = v.env.host.is_shortcut orelse return 0;
    var kind: c.COREWEBVIEW2_KEY_EVENT_KIND = 0;
    _ = w.call(args, "get_KeyEventKind", .{&kind});
    if (kind != c.COREWEBVIEW2_KEY_EVENT_KIND_KEY_DOWN and kind != c.COREWEBVIEW2_KEY_EVENT_KIND_SYSTEM_KEY_DOWN) return 0;
    var vk: c.UINT = 0;
    _ = w.call(args, "get_VirtualKey", .{&vk});
    const mods: ui.Mods = .{ .shift = held(c.VK_SHIFT), .ctrl = held(c.VK_CONTROL), .alt = held(c.VK_MENU), .super = held(c.VK_LWIN) or held(c.VK_RWIN) };
    const key: Key = .{ .vk = @truncate(vk), .mods = mods };
    if (!is_shortcut(v.env.host.context, key.vk, key.mods)) return 0;
    _ = w.call(args, "put_Handled", .{1});
    v.push(.{ .key = key });
    return 0;
}

fn held(vk: c_int) bool {
    return c.GetKeyState(vk) < 0;
}

test "only web schemes stay in the page" {
    try std.testing.expect(staysInPage("https://example.com"));
    try std.testing.expect(staysInPage("HTTP://localhost:3000"));
    try std.testing.expect(staysInPage("about:blank"));
    try std.testing.expect(!staysInPage("file:///C:/Windows/win.ini"));
    try std.testing.expect(!staysInPage("mailto:a@b.c"));
    try std.testing.expect(!staysInPage("javascript:alert(1)"));
    try std.testing.expect(!staysInPage("nada"));
}

test {
    @import("win32").refAllDeep(@This());
}
