//! One WebView2 environment per process (the browser process and the
//! profile), started on the first web pane. Creation is asynchronous:
//! views made before it is ready wait and start when it arrives.
//!
//! Threads: everything here runs on the window's thread, the one that
//! called CoInitializeEx(COINIT_APARTMENTTHREADED). WebView2 calls back on
//! that same thread, from inside its message loop; a callback only records
//! what happened and calls Host.wake, and the panes read it on the next
//! frame (View.poll), so no pane is closed under a WebView2 call.

const std = @import("std");
const w = @import("win32");
const ui = @import("ui");
const c = w.c;
const com = @import("com.zig");
const iids = @import("sdk/iids.zig");
const loader = @import("loader.zig");
const View = @import("view.zig").View;

/// What the app gives the web panes.
pub const Host = struct {
    context: *anyopaque,
    /// Something was queued for a pane: ask for a frame (PostMessage or
    /// InvalidateRect), nothing more. Called inside WebView2 callbacks.
    wake: *const fn (context: *anyopaque) void,
    /// A key went down while a page has the keyboard: true when it is a
    /// shortcut of the app (Ctrl+K, Ctrl+W...). The page then does not get
    /// it, and the pane hands it over as Event.key. Null: the page gets all.
    is_shortcut: ?*const fn (context: *anyopaque, vk: u16, mods: ui.Mods) bool = null,
};

pub const State = union(enum) {
    starting,
    ready: *c.ICoreWebView2Environment,
    /// Why there will be no web panes, in Portuguese.
    failed: []const u8,
};

pub const Environment = struct {
    gpa: std.mem.Allocator,
    host: Host,
    /// The window the panes' child windows go in.
    parent: c.HWND,
    state: State = .starting,
    /// Every live view, to start them, hide the ones not drawn and tell
    /// them the window moved.
    views: std.ArrayList(*View) = .empty,
    /// Counts the app's frames (endFrame).
    frame: u64 = 1,
    refs: u32 = 1,
    created: Created = .{},

    const Created = com.Handler(c.ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler, &iids.ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler, Environment, "created", onCreated);

    /// Starts the browser process for the window `parent`. Never fails for
    /// a missing runtime: the state says so, and the panes show it.
    pub fn create(gpa: std.mem.Allocator, host: Host, parent: c.HWND) !*Environment {
        const self = try gpa.create(Environment);
        self.* = .{ .gpa = gpa, .host = host, .parent = parent };
        self.start();
        return self;
    }

    fn start(self: *Environment) void {
        const createEnvironment = loader.load() catch |err| return self.fail(err, 0);
        const folder = loader.userDataFolder(self.gpa) catch null;
        defer if (folder) |f| self.gpa.free(f);
        const hr = createEnvironment(null, if (folder) |f| f.ptr else null, null, self.created.ptr());
        if (hr < 0) self.fail(error.ComFailed, hr);
    }

    fn fail(self: *Environment, err: anyerror, hr: c.HRESULT) void {
        std.log.warn("WebView2 did not start: {s} 0x{x}", .{ @errorName(err), @as(u32, @bitCast(hr)) });
        self.state = .{ .failed = loader.failureMessage(err, hr) };
        for (self.views.items) |v| v.environmentFailed(self.state.failed);
        self.host.wake(self.host.context);
    }

    fn onCreated(self: *Environment, hr: c.HRESULT, env: [*c]c.ICoreWebView2Environment) c.HRESULT {
        if (hr < 0 or env == null) {
            self.fail(error.ComFailed, hr);
            return 0;
        }
        // The callback lends the environment; keep our own reference.
        _ = w.call(env, "AddRef", .{});
        self.state = .{ .ready = env };
        // A copy: starting a view may not change the list, but be safe.
        const waiting = self.gpa.dupe(*View, self.views.items) catch return 0;
        defer self.gpa.free(waiting);
        for (waiting) |v| v.startController();
        self.host.wake(self.host.context);
        return 0;
    }

    /// The app is closing: the views must be destroyed first.
    pub fn destroy(self: *Environment) void {
        if (self.state == .ready) w.release(self.state.ready);
        self.state = .{ .failed = "" };
        self.release();
    }

    pub fn retain(self: *Environment) void {
        self.refs += 1;
    }

    pub fn release(self: *Environment) void {
        self.refs -= 1;
        if (self.refs > 0) return;
        self.views.deinit(self.gpa);
        self.gpa.destroy(self);
    }

    pub fn add(self: *Environment, view: *View) void {
        self.views.append(self.gpa, view) catch {};
    }

    pub fn remove(self: *Environment, view: *View) void {
        for (self.views.items, 0..) |v, i| if (v == view) {
            _ = self.views.swapRemove(i);
            return;
        };
    }

    /// After the app drew a frame: the pages of panes not drawn in it (a
    /// tab in the background, a closed split) are hidden, since their child
    /// windows would otherwise stay on top of whatever is there now.
    pub fn endFrame(self: *Environment) void {
        for (self.views.items) |v| v.endFrame(self.frame);
        self.frame += 1;
    }

    /// WM_MOVE / WM_WINDOWPOSCHANGED of the window: the pages' popups (a
    /// <select>, a tooltip) follow it.
    pub fn parentMoved(self: *Environment) void {
        for (self.views.items) |v| v.parentMoved();
    }

    pub fn ready(self: *const Environment) ?*c.ICoreWebView2Environment {
        return switch (self.state) {
            .ready => |e| e,
            else => null,
        };
    }
};

test {
    @import("win32").refAllDeep(@This());
}
