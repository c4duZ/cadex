//! An image, a video, an audio file or a PDF in a tab
//! (docs/spec/media-preview.md), the Mac's MediaDocument: read only after
//! the core says the file is inside the workspace; a file the system
//! cannot show says so, with "Open in Default App".

const std = @import("std");
const cadex = @import("cadex");
const gfx = @import("gfx");
const ui = @import("ui");
const strings = @import("strings");
const icons = @import("icons");
const tabs = @import("tabs");
const webview = @import("webview");
const Kind = @import("kind.zig").Kind;
const Image = @import("image.zig").Image;
const page = @import("page.zig");

/// What a media tab needs from the app.
pub const Host = struct {
    context: *anyopaque,
    /// "Open in Default App" (ShellExecute "open").
    open_externally: *const fn (context: *anyopaque, path: []const u8) void,
    /// A shortcut of the app pressed while the player or the PDF had the
    /// keyboard: run it as if typed in the window.
    on_key: *const fn (context: *anyopaque, vk: u16, mods: ui.Mods) void,
    /// Behind the player and the image (the theme's panel color).
    background: gfx.Color = gfx.Color.rgb(0x111111),
};

pub const Media = struct {
    gpa: std.mem.Allocator,
    host: Host,
    path: []u8,
    kind: Kind,
    image: ?Image = null,
    view: ?*webview.View = null,
    /// Why nothing is shown (Portuguese), with the button to open outside.
    message: ?[]const u8 = null,
    /// The last area the image was drawn in, for the zoom commands.
    area: gfx.Rect = .{},
    id: ui.Id,

    var next_id: usize = 1;

    pub fn create(gpa: std.mem.Allocator, host: Host, env: *webview.Environment, path: []const u8, kind: Kind) !*Media {
        const self = try gpa.create(Media);
        errdefer gpa.destroy(self);
        self.* = .{ .gpa = gpa, .host = host, .path = try gpa.dupe(u8, path), .kind = kind, .id = ui.id("media", next_id) };
        next_id += 1;
        if (!authorized(gpa, path)) {
            self.message = strings.t("The file is outside the open folder", "O arquivo está fora da pasta aberta");
            return self;
        }
        if (kind == .image) {
            self.image = Image.load(gpa, self.path);
            if (self.image == null) self.message = strings.t("Can't show this image", "Não é possível mostrar esta imagem");
        } else {
            self.openPage(env) catch {
                self.message = strings.t("Can't show this file", "Não é possível mostrar este arquivo");
            };
        }
        return self;
    }

    fn openPage(self: *Media, env: *webview.Environment) !void {
        const view = try webview.View.create(self.gpa, env, .{
            .scripts = true,
            .web_messages = true,
            .links = .route,
            .background = self.host.background,
        });
        self.view = view;
        view.mapFolder(page.host_name, webview.urls.folderOf(self.path));
        try self.loadPage();
    }

    fn loadPage(self: *Media) !void {
        const view = self.view orelse return;
        const url = try page.fileUrl(self.gpa, self.path);
        defer self.gpa.free(url);
        if (try page.html(self.gpa, self.kind, url, self.host.background)) |html| {
            defer self.gpa.free(html);
            view.navigateToString(html);
        } else {
            view.navigate(url);
        }
    }

    pub fn document(self: *Media) tabs.Document {
        return .{ .ptr = self, .vtable = &vtable };
    }

    pub fn of(doc: tabs.Document) ?*Media {
        return if (doc.vtable == &vtable) @ptrCast(@alignCast(doc.ptr)) else null;
    }

    pub fn zoomable(self: *const Media) bool {
        return self.kind.zoomable() and self.image != null;
    }

    pub fn zoomIn(self: *Media) void {
        if (self.image) |*i| i.zoomIn(self.area);
    }
    pub fn zoomOut(self: *Media) void {
        if (self.image) |*i| i.zoomOut(self.area);
    }
    pub fn zoomToFit(self: *Media) void {
        if (self.image) |*i| i.zoom.fit();
    }
    pub fn actualSize(self: *Media) void {
        if (self.image) |*i| i.zoom.actualSize();
    }

    /// The file changed on disk (the explorer's watcher): show it again.
    pub fn diskMayHaveChanged(self: *Media) void {
        if (self.image) |*i| {
            if (!i.reload()) self.message = strings.t("Can't show this image", "Não é possível mostrar esta imagem");
        } else if (self.view) |v| {
            if (self.kind == .pdf) v.reload() else self.loadPage() catch {};
        }
    }

    fn takeEvents(self: *Media) void {
        const view = self.view orelse return;
        while (view.poll()) |event| switch (event) {
            .message => |m| if (std.mem.eql(u8, m, "error")) {
                self.message = if (self.kind == .web_image) strings.t("Can't show this image", "Não é possível mostrar esta imagem") else strings.t("Can't play this file", "Não é possível tocar este arquivo");
            },
            .failed => |why| self.message = why,
            .finished => |f| if (!f.ok) {
                self.message = strings.t("Can't show this file", "Não é possível mostrar este arquivo");
            },
            .key => |k| self.host.on_key(self.host.context, k.vk, k.mods),
            // A link inside a PDF goes to the system browser.
            .link, .external => |url| if (std.ascii.startsWithIgnoreCase(url, "http")) self.host.open_externally(self.host.context, url),
            .ready, .loading, .title, .source, .history => {},
        };
    }

    fn draw(self: *Media, u: *ui.Ui, area: gfx.Rect, focused: bool) void {
        self.takeEvents();
        u.painter.fill(area, self.host.background);
        if (self.message) |m| {
            if (self.view) |v| v.hide();
            self.drawMessage(u, area, m);
            return;
        }
        if (self.image) |*i| {
            self.area = area;
            i.draw(u, area);
        } else if (self.view) |v| {
            v.show(u, area, focused);
        }
    }

    fn drawMessage(self: *Media, u: *ui.Ui, area: gfx.Rect, message: []const u8) void {
        const c = area.center();
        const text_rect: gfx.Rect = .{ .x = area.x, .y = c.y - u.px(30), .w = area.w, .h = u.px(24) };
        u.painter.text(message, u.style.font(14), text_rect, u.style.secondary_text, .{ .@"align" = .center });
        const label = strings.t("Open in Default App", "Abrir no app padrão");
        const bw = u.painter.measure(label, u.style.ui()) + u.px(24);
        const button: gfx.Rect = .{ .x = c.x - bw / 2, .y = c.y + u.px(4), .w = bw, .h = u.px(28) };
        u.painter.fillRounded(button, u.px(6), u.style.field);
        if (ui.widgets.button(u, ui.child(self.id, 1), button, label, .{})) self.host.open_externally(self.host.context, self.path);
    }

    fn destroy(self: *Media) void {
        if (self.view) |v| v.destroy();
        if (self.image) |*i| i.deinit();
        self.gpa.free(self.path);
        self.gpa.destroy(self);
    }

    fn title(self: *Media) []const u8 {
        return webview.urls.fileName(self.path);
    }

    const vtable: tabs.Document.VTable = .{
        .title = struct {
            fn f(p: *anyopaque) []const u8 {
                return cast(p).title();
            }
        }.f,
        .identity = struct {
            fn f(p: *anyopaque) []const u8 {
                return cast(p).path;
            }
        }.f,
        .icon = struct {
            fn f(p: *anyopaque) u21 {
                return icons.forFileNamed(cast(p).title());
            }
        }.f,
        .icon_color = struct {
            fn f(p: *anyopaque) ?gfx.Color {
                return icons.colorForFileNamed(cast(p).title());
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

    fn cast(p: *anyopaque) *Media {
        return @ptrCast(@alignCast(p));
    }
};

/// The core decides (cadex_workspace_is_authorized), as on the Mac.
fn authorized(gpa: std.mem.Allocator, path: []const u8) bool {
    const z = gpa.dupeZ(u8, path) catch return false;
    defer gpa.free(z);
    return cadex.cadex_workspace_is_authorized(z.ptr);
}

test {
    @import("win32").refAllDeep(@This());
}
