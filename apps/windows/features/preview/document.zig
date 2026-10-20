//! A web page in a tab (docs/spec/preview.md), the Mac's PreviewDocument:
//! back, forward, reload and the address on a bar, the page under it
//! (WebView2, shared/webview), a thin progress line while it loads and
//! "Couldn't connect to <address>" with the reason when it fails.
//! The page is isolated: InPrivate (data only while the app runs), no
//! bridge to the app, file: refused, other schemes and new windows to the
//! system browser, "Inspecionar" in the page's menu.

const std = @import("std");
const gfx = @import("gfx");
const ui = @import("ui");
const strings = @import("strings");
const icons = @import("icons");
const tabs = @import("tabs");
const webview = @import("webview");
const address = @import("address.zig");

/// What the preview needs from the app.
pub const Host = struct {
    context: *anyopaque,
    /// An address for the system browser (ShellExecute): a link that
    /// opens a new window, mailto:.
    open_external: *const fn (context: *anyopaque, url: []const u8) void,
    /// The title changed: redraw the tab bar.
    on_change: *const fn (context: *anyopaque) void,
    /// A shortcut of the app pressed while the page had the keyboard
    /// (webview.Host.is_shortcut said yes): run it as if typed in the window.
    on_key: *const fn (context: *anyopaque, vk: u16, mods: ui.Mods) void,
};

pub const Preview = struct {
    gpa: std.mem.Allocator,
    host: Host,
    view: *webview.View,
    identity: []u8,
    field: ui.TextBuffer = .{},
    scroll: ui.text_field.Scroll = .{},
    /// The address on the bar when the error appeared.
    message: ?[]u8 = null,
    title_buf: [256]u8 = undefined,
    id: ui.Id,

    var next_id: usize = 1;

    pub fn create(gpa: std.mem.Allocator, host: Host, env: *webview.Environment, url: []const u8) !*Preview {
        const self = try gpa.create(Preview);
        errdefer gpa.destroy(self);
        const view = try webview.View.create(gpa, env, .{ .private = true, .devtools = true, .links = .web });
        errdefer view.destroy();
        self.* = .{ .gpa = gpa, .host = host, .view = view, .identity = try address.identity(gpa, url), .id = ui.id("preview", next_id) };
        next_id += 1;
        if (url.len > 0) self.load(url);
        return self;
    }

    pub fn document(self: *Preview) tabs.Document {
        return .{ .ptr = self, .vtable = &vtable };
    }

    /// The preview behind a pane's document, if it is one.
    pub fn of(doc: tabs.Document) ?*Preview {
        return if (doc.vtable == &vtable) @ptrCast(@alignCast(doc.ptr)) else null;
    }

    /// Loads what was typed (http:// for local servers, https:// for the rest).
    pub fn load(self: *Preview, typed: []const u8) void {
        const url = (address.normalize(self.gpa, typed) catch null) orelse return;
        defer self.gpa.free(url);
        self.field.set(self.gpa, url) catch {};
        self.clearMessage();
        self.view.navigate(url);
    }

    pub fn reload(self: *Preview) void {
        self.clearMessage();
        // An address that never loaded has nothing to reload: load it again.
        if (self.view.state().source.len == 0) return self.load(self.field.text());
        self.view.reload();
    }

    pub fn goBack(self: *Preview) void {
        self.view.goBack();
    }

    pub fn goForward(self: *Preview) void {
        self.view.goForward();
    }

    fn clearMessage(self: *Preview) void {
        if (self.message) |m| self.gpa.free(m);
        self.message = null;
    }

    fn showFailure(self: *Preview, reason: []const u8) void {
        self.clearMessage();
        self.message = (if (strings.language == .pt)
            std.fmt.allocPrint(self.gpa, "Não foi possível conectar a {s}\n{s}", .{ self.field.text(), reason })
        else
            std.fmt.allocPrint(self.gpa, "Couldn't connect to {s}\n{s}", .{ self.field.text(), reason })) catch null;
    }

    /// What happened in the page since the last frame.
    fn takeEvents(self: *Preview, u: *ui.Ui) void {
        while (self.view.poll()) |event| switch (event) {
            .title => self.host.on_change(self.host.context),
            .source => {
                // Not while the user is typing an address.
                if (u.focus != self.fieldId()) self.field.set(self.gpa, self.view.state().source) catch {};
                self.host.on_change(self.host.context);
            },
            .loading => self.clearMessage(),
            .finished => |f| if (!f.ok) self.showFailure(webview.errors.reason(f.status)),
            .failed => |why| {
                self.clearMessage();
                self.message = self.gpa.dupe(u8, why) catch null;
            },
            .external => |url| self.host.open_external(self.host.context, url),
            .key => |k| self.host.on_key(self.host.context, k.vk, k.mods),
            .ready, .history, .link, .message => {},
        };
    }

    fn fieldId(self: *const Preview) ui.Id {
        return ui.child(self.id, 1);
    }

    fn draw(self: *Preview, u: *ui.Ui, area: gfx.Rect, focused: bool) void {
        self.takeEvents(u);
        var rest = area;
        u.painter.fill(area, u.style.panel);
        const bar = rest.takeTop(u.px(36));
        self.drawBar(u, bar);
        const progress = rest.takeTop(u.px(2));
        if (self.view.state().loading) u.painter.fill(.{ .x = progress.x, .y = progress.y, .w = progress.w * 0.3, .h = progress.h }, u.style.accent);
        if (self.message) |m| {
            self.view.hide();
            u.painter.text(m, u.style.ui(), rest.inset(u.px(20), 0), u.style.secondary_text, .{ .@"align" = .center, .ellipsis = false });
            return;
        }
        // The keys go to the page when the pane has them and the address does not.
        self.view.show(u, rest, focused and u.focus != self.fieldId());
    }

    fn drawBar(self: *Preview, u: *ui.Ui, bar: gfx.Rect) void {
        var r = bar.inset(u.px(8), u.px(6));
        const size = u.px(24);
        const page = self.view.state();
        if (ui.widgets.iconButton(u, ui.child(self.id, 2), r.takeLeft(size), icons.phosphor.arrow_left, .{ .enabled = page.can_back, .icon_size = 14 })) self.goBack();
        _ = r.takeLeft(u.px(4));
        if (ui.widgets.iconButton(u, ui.child(self.id, 3), r.takeLeft(size), icons.phosphor.arrow_right, .{ .enabled = page.can_forward, .icon_size = 14 })) self.goForward();
        _ = r.takeLeft(u.px(4));
        if (ui.widgets.iconButton(u, ui.child(self.id, 4), r.takeLeft(size), icons.phosphor.arrow_clockwise, .{ .icon_size = 14 })) self.reload();
        _ = r.takeLeft(u.px(6));
        const result = ui.text_field.textField(u, self.fieldId(), r, &self.field, &self.scroll, .{ .placeholder = "http://localhost:3000" });
        if (result.submitted) {
            self.load(self.field.text());
            u.focus = self.id;
        } else if (result.cancelled) {
            self.field.set(self.gpa, page.source) catch {};
            u.focus = self.id;
        }
    }

    fn title(self: *Preview) []const u8 {
        const page = self.view.state();
        if (page.title.len > 0) return page.title;
        return address.fallbackTitle(&self.title_buf, if (page.source.len > 0) page.source else self.field.text());
    }

    fn destroy(self: *Preview) void {
        self.view.destroy();
        self.clearMessage();
        self.field.deinit(self.gpa);
        self.gpa.free(self.identity);
        self.gpa.destroy(self);
    }

    const vtable: tabs.Document.VTable = .{
        .title = struct {
            fn f(p: *anyopaque) []const u8 {
                return cast(p).title();
            }
        }.f,
        .identity = struct {
            fn f(p: *anyopaque) []const u8 {
                return cast(p).identity;
            }
        }.f,
        .icon = struct {
            fn f(_: *anyopaque) u21 {
                return icons.phosphor.globe;
            }
        }.f,
        .unsaved = struct {
            fn f(_: *anyopaque) bool {
                return false;
            }
        }.f,
        .draw = struct {
            fn f(p: *anyopaque, u: *ui.Ui, area: gfx.Rect, focused: bool) void {
                cast(p).draw(u, area, focused);
            }
        }.f,
        .focus_id = struct {
            fn f(p: *anyopaque) ui.Id {
                const self = cast(p);
                // A blank preview starts with the address ready to type.
                return if (self.field.text().len == 0) self.fieldId() else self.id;
            }
        }.f,
        .destroy = struct {
            fn f(p: *anyopaque) void {
                cast(p).destroy();
            }
        }.f,
    };

    fn cast(p: *anyopaque) *Preview {
        return @ptrCast(@alignCast(p));
    }
};

test {
    @import("win32").refAllDeep(@This());
}
