//! The rendered note (docs/adr/0010-markdown-rendering.md), the Mac's
//! MarkdownPreview: the core's HTML (cadex_markdown_render) in a WebView2
//! page with JavaScript off and a strict content policy. The page has a
//! real address on the app's own server (https://note.cadex.example/<path>,
//! shared/webview/resources.zig), so relative images resolve against the
//! note's folder and #heading scrolls in the page; images are served only
//! from inside the workspace (the core says). A click never navigates: it
//! goes to Host.open_link (a note in the Cadex, the web in the browser).
//!
//! It draws by itself in a pane (`document`) or inside the markdown
//! editor's document, which calls draw, setText and destroy.

const std = @import("std");
const cadex = @import("cadex");
const w = @import("win32");
const gfx = @import("gfx");
const ui = @import("ui");
const icons = @import("icons");
const tabs = @import("tabs");
const webview = @import("webview");
const look_mod = @import("look.zig");
const links = @import("links.zig");

pub const Look = look_mod.Look;
pub const Link = links.Link;

pub const Host = struct {
    context: *anyopaque,
    /// A click in the page, from the note at `from`. The link is valid
    /// during the call; a wiki name goes through cadex_markdown_resolve, a
    /// file opens in the Cadex (at the heading of the fragment), web in
    /// the browser.
    open_link: *const fn (context: *anyopaque, link: Link, from: []const u8) void,
    /// A shortcut of the app pressed while the page had the keyboard.
    on_key: *const fn (context: *anyopaque, vk: u16, mods: ui.Mods) void,
};

pub const Rendered = struct {
    gpa: std.mem.Allocator,
    host: Host,
    view: *webview.View,
    path: []u8,
    /// The note's address on our server.
    url: []u8,
    markdown: std.ArrayList(u8) = .empty,
    look: Look,
    message: ?[]const u8 = null,
    id: ui.Id,

    var next_id: usize = 1;

    /// `text`: the editor's text, unsaved changes included; null reads the file.
    pub fn create(gpa: std.mem.Allocator, host: Host, env: *webview.Environment, path: []const u8, text: ?[]const u8, look: Look) !*Rendered {
        const self = try gpa.create(Rendered);
        errdefer gpa.destroy(self);
        const owned_path = try gpa.dupe(u8, path);
        errdefer gpa.free(owned_path);
        const url = try webview.urls.fileUrl(gpa, links.origin, path);
        errdefer gpa.free(url);
        self.* = .{ .gpa = gpa, .host = host, .view = undefined, .path = owned_path, .url = url, .look = look, .id = ui.id("markdown-rendered", next_id) };
        next_id += 1;
        self.view = try webview.View.create(gpa, env, .{
            .scripts = false,
            .links = .route,
            .background = look.background,
            .serve = .{ .prefix = links.origin, .context = self, .answer = answer },
        });
        if (text) |t| {
            try self.markdown.appendSlice(gpa, t);
        } else if (w.files.read(gpa, path, 10 * 1024 * 1024)) |bytes| {
            defer gpa.free(bytes);
            try self.markdown.appendSlice(gpa, bytes);
        } else {
            self.message = "Não foi possível ler a nota";
        }
        self.view.navigate(self.url);
        return self;
    }

    /// The editor's text changed (or a toggle back to the page): render again.
    pub fn setText(self: *Rendered, text: []const u8) void {
        self.markdown.clearRetainingCapacity();
        self.markdown.appendSlice(self.gpa, text) catch return;
        self.message = null;
        self.view.navigate(self.url);
    }

    /// The theme changed.
    pub fn setLook(self: *Rendered, look: Look) void {
        self.look = look;
        self.view.navigate(self.url);
    }

    pub fn document(self: *Rendered) tabs.Document {
        return .{ .ptr = self, .vtable = &vtable };
    }

    pub fn of(doc: tabs.Document) ?*Rendered {
        return if (doc.vtable == &vtable) @ptrCast(@alignCast(doc.ptr)) else null;
    }

    /// The page as the core renders it now.
    fn renderPage(self: *Rendered) ?[]u8 {
        var out: [*c]u8 = null;
        var len: usize = 0;
        if (cadex.cadex_markdown_render(self.markdown.items.ptr, self.markdown.items.len, &out, &len) != cadex.CADEX_OK) return null;
        defer cadex.cadex_free(out);
        const body: []const u8 = if (out) |o| o[0..len] else "";
        return look_mod.page(self.gpa, body, self.look, links.origin) catch null;
    }

    /// Our server (shared/webview Serve): the note itself, rendered, and
    /// the files it shows, only inside the workspace.
    fn answer(context: *anyopaque, gpa: std.mem.Allocator, url: []const u8) ?webview.Served {
        const self: *Rendered = @ptrCast(@alignCast(context));
        const local = (webview.urls.localPath(gpa, links.origin, url) catch return null) orelse return null;
        if (std.ascii.eqlIgnoreCase(local.path, self.path)) {
            gpa.free(local.path);
            const html = self.renderPage() orelse return null;
            return .{ .body = .{ .bytes = html }, .mime = "text/html; charset=utf-8" };
        }
        if (!authorized(gpa, local.path)) {
            gpa.free(local.path);
            return null;
        }
        return .{ .body = .{ .file = local.path }, .mime = webview.mimeOf(local.path) };
    }

    fn takeEvents(self: *Rendered) void {
        while (self.view.poll()) |event| switch (event) {
            .link, .external => |url| {
                const link = (links.classify(self.gpa, url) catch null) orelse continue;
                defer link.deinit(self.gpa);
                self.host.open_link(self.host.context, link, self.path);
            },
            .key => |k| self.host.on_key(self.host.context, k.vk, k.mods),
            .failed => |why| self.message = why,
            .ready, .loading, .finished, .title, .source, .history, .message => {},
        };
    }

    pub fn draw(self: *Rendered, u: *ui.Ui, area: gfx.Rect, focused: bool) void {
        self.takeEvents();
        u.painter.fill(area, self.look.background);
        if (self.message) |m| {
            self.view.hide();
            u.painter.text(m, u.style.ui(), area, u.style.secondary_text, .{ .@"align" = .center });
            return;
        }
        self.view.show(u, area, focused);
    }

    pub fn destroy(self: *Rendered) void {
        self.view.destroy();
        self.markdown.deinit(self.gpa);
        self.gpa.free(self.url);
        self.gpa.free(self.path);
        self.gpa.destroy(self);
    }

    const vtable: tabs.Document.VTable = .{
        .title = struct {
            fn f(p: *anyopaque) []const u8 {
                return webview.urls.fileName(cast(p).path);
            }
        }.f,
        .identity = struct {
            fn f(p: *anyopaque) []const u8 {
                return cast(p).path;
            }
        }.f,
        .icon = struct {
            fn f(_: *anyopaque) u21 {
                return icons.phosphor.file_md;
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
                return cast(p).id;
            }
        }.f,
        .folder = struct {
            fn f(p: *anyopaque) ?[]const u8 {
                return webview.urls.folderOf(cast(p).path);
            }
        }.f,
        .destroy = struct {
            fn f(p: *anyopaque) void {
                cast(p).destroy();
            }
        }.f,
    };

    fn cast(p: *anyopaque) *Rendered {
        return @ptrCast(@alignCast(p));
    }
};

fn authorized(gpa: std.mem.Allocator, path: []const u8) bool {
    const z = gpa.dupeZ(u8, path) catch return false;
    defer gpa.free(z);
    return cadex.cadex_workspace_is_authorized(z.ptr);
}

test {
    @import("win32").refAllDeep(@This());
}
