//! A web page in a pane: a WebView2 controller whose child window sits over
//! the window's Direct2D surface, where the pane's document places it each
//! frame. Calls made before the controller exists (it is created
//! asynchronously) are kept and applied when it arrives: the last
//! navigation, the bounds, the visibility, the folder mappings.
//!
//! Lifetime: the document calls destroy(); the memory goes when WebView2
//! has released the last handler it held (com.zig), so a callback that
//! arrives late finds the view closed instead of freed.

const std = @import("std");
const w = @import("win32");
const gfx = @import("gfx");
const ui = @import("ui");
const c = w.c;
const com = @import("com.zig");
const iids = @import("sdk/iids.zig");
const strings = @import("strings.zig");
const handlers = @import("handlers.zig");
const resources = @import("resources.zig");
const Environment = @import("environment.zig").Environment;

pub const Event = handlers.Event;
pub const Serve = resources.Serve;
pub const Served = resources.Served;

pub const Options = struct {
    /// InPrivate: cookies and storage only while the app is open (preview).
    private: bool = false,
    scripts: bool = true,
    /// "Inspecionar elemento" in the page's menu.
    devtools: bool = false,
    context_menus: bool = true,
    /// window.chrome.webview.postMessage reaches the pane as Event.message.
    web_messages: bool = false,
    /// What a navigation the page starts (a click) does: `web` lets http
    /// and https go on and hands other schemes over as Event.external;
    /// `route` cancels it and hands it over as Event.link.
    links: enum { web, route } = .web,
    /// Painted while the page loads, instead of white.
    background: ?gfx.Color = null,
    /// Requests under this address are answered by `serve` (resources.zig).
    serve: ?Serve = null,
};

const Pending = union(enum) {
    none,
    url: [:0]u16,
    html: [:0]u16,
};

const Mapping = struct { host: [:0]u16, folder: [:0]u16 };

pub const View = struct {
    gpa: std.mem.Allocator,
    env: *Environment,
    options: Options,
    refs: u32 = 1,
    closed: bool = false,
    controller: ?*c.ICoreWebView2Controller = null,
    web: ?*c.ICoreWebView2 = null,
    pending: Pending = .none,
    mappings: std.ArrayList(Mapping) = .empty,
    bounds: c.RECT = .{ .left = 0, .top = 0, .right = 0, .bottom = 0 },
    /// What the document asked for (setVisible), and what the window shows.
    wanted_visible: bool = true,
    shown: bool = false,
    placed_frame: u64 = 0,
    /// The pane had the keys last frame (show), to hand them over once.
    had_keys: bool = false,
    /// Navigations the view itself started, still to be seen in
    /// NavigationStarting: they are never routed as clicks.
    own_navigations: u32 = 0,
    /// The page's state, kept current by handlers.zig.
    page: handlers.Page = .{},
    events: std.ArrayList(Event) = .empty,
    /// The string of the event poll() returned last, freed on the next poll.
    popped: ?[]u8 = null,
    tokens: handlers.Tokens = .{},

    created: Created = .{},
    on: handlers.Set = .{},

    const Created = com.Handler(c.ICoreWebView2CreateCoreWebView2ControllerCompletedHandler, &iids.ICoreWebView2CreateCoreWebView2ControllerCompletedHandler, View, "created", onCreated);

    pub fn create(gpa: std.mem.Allocator, env: *Environment, options: Options) !*View {
        const self = try gpa.create(View);
        self.* = .{ .gpa = gpa, .env = env, .options = options };
        env.retain();
        env.add(self);
        switch (env.state) {
            .ready => self.startController(),
            .failed => |why| self.environmentFailed(why),
            .starting => {},
        }
        return self;
    }

    /// The pane is gone: the page closes now, the memory when WebView2 lets go.
    pub fn destroy(self: *View) void {
        if (self.closed) return;
        self.closed = true;
        self.env.remove(self);
        if (self.controller) |ctl| {
            handlers.unregister(self);
            _ = w.call(ctl, "Close", .{});
        }
        self.release();
    }

    pub fn retain(self: *View) void {
        self.refs += 1;
    }

    pub fn release(self: *View) void {
        self.refs -= 1;
        if (self.refs > 0) return;
        if (self.web) |v| w.release(v);
        if (self.controller) |ctl| w.release(ctl);
        self.clearPending();
        for (self.mappings.items) |m| {
            self.gpa.free(m.host);
            self.gpa.free(m.folder);
        }
        self.mappings.deinit(self.gpa);
        for (self.events.items) |e| handlers.freeEvent(self.gpa, e);
        self.events.deinit(self.gpa);
        if (self.popped) |p| self.gpa.free(p);
        self.page.deinit(self.gpa);
        const env = self.env;
        self.gpa.destroy(self);
        env.release();
    }

    pub fn startController(self: *View) void {
        if (self.closed or self.controller != null) return;
        const env = self.env.ready() orelse return;
        self.retain(); // for the creation callback, released in onCreated
        const hr = if (self.options.private) self.createPrivate(env) else w.call(env, "CreateCoreWebView2Controller", .{ self.env.parent, self.created.ptr() });
        if (hr < 0) {
            self.release();
            self.environmentFailed("Não foi possível abrir a página");
        }
    }

    /// ICoreWebView2Environment10 (runtime 101+); older runtimes get a normal profile.
    fn createPrivate(self: *View, env: *c.ICoreWebView2Environment) c.HRESULT {
        const env10 = w.query(env, c.ICoreWebView2Environment10, &iids.ICoreWebView2Environment10) catch
            return w.call(env, "CreateCoreWebView2Controller", .{ self.env.parent, self.created.ptr() });
        defer w.release(env10);
        var opts: [*c]c.ICoreWebView2ControllerOptions = null;
        if (w.call(env10, "CreateCoreWebView2ControllerOptions", .{&opts}) < 0 or opts == null)
            return w.call(env, "CreateCoreWebView2Controller", .{ self.env.parent, self.created.ptr() });
        defer w.release(opts);
        _ = w.call(opts, "put_IsInPrivateModeEnabled", .{1});
        return w.call(env10, "CreateCoreWebView2ControllerWithOptions", .{ self.env.parent, opts, self.created.ptr() });
    }

    fn onCreated(self: *View, hr: c.HRESULT, controller: [*c]c.ICoreWebView2Controller) c.HRESULT {
        defer self.release();
        if (self.closed) {
            if (controller != null) _ = w.call(controller, "Close", .{});
            return 0;
        }
        if (hr < 0 or controller == null) {
            self.environmentFailed("Não foi possível abrir a página");
            return 0;
        }
        _ = w.call(controller, "AddRef", .{});
        self.controller = controller;
        var web: [*c]c.ICoreWebView2 = null;
        if (w.call(controller, "get_CoreWebView2", .{&web}) < 0 or web == null) {
            self.environmentFailed("Não foi possível abrir a página");
            return 0;
        }
        self.web = web;
        handlers.configure(self);
        handlers.register(self);
        for (self.mappings.items) |m| self.applyMapping(m);
        _ = w.call(controller, "put_Bounds", .{self.bounds});
        // A new controller is visible: start from that, so hiding applies.
        self.shown = true;
        self.applyVisible(self.wanted_visible and self.placed_frame + 1 >= self.env.frame);
        self.applyPending();
        self.push(.ready);
        return 0;
    }

    pub fn environmentFailed(self: *View, why: []const u8) void {
        self.page.failure = why;
        self.push(.{ .failed = why });
    }

    // ---- What the document asks -----------------------------------------

    /// Loads `url` (already normalized by the feature).
    pub fn navigate(self: *View, url: []const u8) void {
        const text = strings.wide(self.gpa, url) catch return;
        self.clearPending();
        self.pending = .{ .url = text };
        self.applyPending();
    }

    /// Shows `html` (a page the app made: the media player).
    pub fn navigateToString(self: *View, html: []const u8) void {
        const text = strings.wide(self.gpa, html) catch return;
        self.clearPending();
        self.pending = .{ .html = text };
        self.applyPending();
    }

    pub fn reload(self: *View) void {
        const web = self.web orelse return;
        self.own_navigations += 1;
        self.page.failed_status = null;
        _ = w.call(web, "Reload", .{});
    }

    pub fn goBack(self: *View) void {
        if (self.web) |web| _ = w.call(web, "GoBack", .{});
    }

    pub fn goForward(self: *View) void {
        if (self.web) |web| _ = w.call(web, "GoForward", .{});
    }

    pub fn stop(self: *View) void {
        if (self.web) |web| _ = w.call(web, "Stop", .{});
    }

    /// https://<host>/ serves `folder` (ICoreWebView2_3): the media player
    /// reads the file this way, with seeking, which a served stream lacks.
    pub fn mapFolder(self: *View, host: []const u8, folder: []const u8) void {
        const m: Mapping = .{
            .host = strings.wide(self.gpa, host) catch return,
            .folder = strings.wide(self.gpa, folder) catch return,
        };
        self.mappings.append(self.gpa, m) catch return;
        if (self.web != null) self.applyMapping(m);
    }

    /// Where the page goes, in window client pixels, for this frame. A view
    /// not placed in a frame is hidden by Environment.endFrame.
    pub fn place(self: *View, r: gfx.Rect) void {
        self.placed_frame = self.env.frame;
        const rect: c.RECT = .{
            .left = @intFromFloat(@round(r.x)),
            .top = @intFromFloat(@round(r.y)),
            .right = @intFromFloat(@round(r.x + r.w)),
            .bottom = @intFromFloat(@round(r.y + r.h)),
        };
        if (rect.left != self.bounds.left or rect.top != self.bounds.top or rect.right != self.bounds.right or rect.bottom != self.bounds.bottom) {
            self.bounds = rect;
            if (self.controller) |ctl| _ = w.call(ctl, "put_Bounds", .{rect});
        }
        self.applyVisible(self.wanted_visible);
    }

    /// Hides the page now, until the next show(): a child window covers
    /// anything Direct2D draws. Overlays drawn with ui.beginOverlay already
    /// hide it through show(); this is for what is not one.
    pub fn setVisible(self: *View, visible: bool) void {
        self.wanted_visible = visible;
        if (!visible) self.applyVisible(false);
    }

    /// What a document's draw does with its page each frame: places it in
    /// `area`, hidden while an overlay (the palette, a menu) covers any of
    /// it, and hands it the keyboard when the pane gets the keys.
    pub fn show(self: *View, u: *ui.Ui, area: gfx.Rect, wants_keys: bool) void {
        var covered = false;
        for (u.overlay_rects.items) |o| {
            const both = o.intersect(area);
            if (both.w > 0 and both.h > 0) covered = true;
        }
        self.wanted_visible = !covered;
        self.place(area);
        if (covered) self.applyVisible(false);
        if (wants_keys and !self.had_keys) self.focus();
        self.had_keys = wants_keys;
    }

    /// The pane draws but not the page this frame (it shows an error
    /// instead): hidden, and counted as drawn for endFrame.
    pub fn hide(self: *View) void {
        self.placed_frame = self.env.frame;
        self.applyVisible(false);
        self.had_keys = false;
    }

    /// Gives the page the keyboard (the pane got the focus).
    pub fn focus(self: *View) void {
        if (self.controller) |ctl| _ = w.call(ctl, "MoveFocus", .{c.COREWEBVIEW2_MOVE_FOCUS_REASON_PROGRAMMATIC});
    }

    /// The next thing that happened, or null. A string in it is valid until
    /// the next call.
    pub fn poll(self: *View) ?Event {
        if (self.popped) |p| self.gpa.free(p);
        self.popped = null;
        if (self.events.items.len == 0) return null;
        const e = self.events.orderedRemove(0);
        self.popped = handlers.eventString(e);
        return e;
    }

    pub fn state(self: *const View) *const handlers.Page {
        return &self.page;
    }

    // ---- Inside -----------------------------------------------------------

    pub fn push(self: *View, event: Event) void {
        self.events.append(self.gpa, event) catch return handlers.freeEvent(self.gpa, event);
        self.env.host.wake(self.env.host.context);
    }

    pub fn endFrame(self: *View, frame: u64) void {
        if (self.placed_frame != frame) self.applyVisible(false);
    }

    pub fn parentMoved(self: *View) void {
        if (self.controller) |ctl| _ = w.call(ctl, "NotifyParentWindowPositionChanged", .{});
    }

    fn applyVisible(self: *View, visible: bool) void {
        if (visible == self.shown) return;
        const ctl = self.controller orelse return;
        self.shown = visible;
        _ = w.call(ctl, "put_IsVisible", .{@intFromBool(visible)});
    }

    fn applyMapping(self: *View, m: Mapping) void {
        const web = self.web orelse return;
        const web3 = w.query(web, c.ICoreWebView2_3, &iids.ICoreWebView2_3) catch return;
        defer w.release(web3);
        // DENY_CORS: the player page (from NavigateToString, another
        // origin) may use the files as <video src>, nothing may fetch them.
        _ = w.call(web3, "SetVirtualHostNameToFolderMapping", .{ m.host.ptr, m.folder.ptr, c.COREWEBVIEW2_HOST_RESOURCE_ACCESS_KIND_DENY_CORS });
    }

    fn applyPending(self: *View) void {
        const web = self.web orelse return;
        switch (self.pending) {
            .none => return,
            .url => |u| {
                self.own_navigations += 1;
                self.page.failed_status = null;
                if (w.call(web, "Navigate", .{u.ptr}) < 0) {
                    self.own_navigations -= 1;
                    self.push(.{ .finished = .{ .ok = false, .status = c.COREWEBVIEW2_WEB_ERROR_STATUS_UNKNOWN } });
                }
            },
            .html => |h| {
                self.own_navigations += 1;
                _ = w.call(web, "NavigateToString", .{h.ptr});
            },
        }
        self.clearPending();
    }

    fn clearPending(self: *View) void {
        switch (self.pending) {
            .none => {},
            .url, .html => |t| self.gpa.free(t),
        }
        self.pending = .none;
    }
};

test {
    @import("win32").refAllDeep(@This());
}
