//! The web panes of the app (docs/adr/0014-webview2-on-windows.md): one
//! WebView2 environment for the window, made on first use, and the hosts
//! of preview, media-preview and markdown-rendered; the opener's makers
//! for media and the rendered note; the terminal's "Abrir no preview" offer.

const std = @import("std");
const w = @import("win32");
const ui = @import("ui");
const gfx = @import("gfx");
const icons = @import("icons");
const strings = @import("strings");
const tabs = @import("tabs");
const webview = @import("webview");
const preview = @import("preview");
const media_preview = @import("media-preview");
const markdown_rendered = @import("markdown-rendered");
const shortcuts = @import("shortcuts");
const terminal = @import("terminal");
const viewers = @import("viewers.zig");
const opener = @import("opener.zig");
const palette = @import("command-palette");
const window_mod = @import("window.zig");
const App = @import("app.zig").App;

const c = w.c;

fn of(context: *anyopaque) *App {
    return @ptrCast(@alignCast(context));
}

/// The terminal's offer of a local server, shown for a few seconds.
pub const Offer = struct {
    url: [256]u8 = undefined,
    len: usize = 0,
    until_ms: i64 = 0,
};

const offer_ms = 6000;

pub fn environment(app: *App) ?*webview.Environment {
    if (app.web_env) |e| return e;
    app.web_env = webview.Environment.create(app.gpa, .{ .context = app, .wake = wake, .is_shortcut = isShortcut }, app.window.hwnd) catch return null;
    return app.web_env;
}

pub fn deinit(app: *App) void {
    if (app.web_env) |e| e.destroy();
    app.web_env = null;
    for (app.offered.items) |u| app.gpa.free(u);
    app.offered.deinit(app.gpa);
}

/// After every frame: pages of panes not drawn hide.
pub fn endFrame(app: *App) void {
    if (app.web_env) |e| e.endFrame();
}

pub fn moved(context: *anyopaque) void {
    if (of(context).web_env) |e| e.parentMoved();
}

/// Inside WebView2 callbacks: only ask for a frame.
fn wake(context: *anyopaque) void {
    _ = c.PostMessageW(of(context).window.hwnd, window_mod.WM_APP_WAKE, 0, 0);
}

/// A key in a page that the app takes: a shortcut of a command that can
/// run now, never the edit keys, which are the page's.
fn isShortcut(context: *anyopaque, vk: u16, mods: ui.Mods) bool {
    const app = of(context);
    const combo: shortcuts.KeyCombo = .{ .vk = vk, .ctrl = mods.ctrl, .shift = mods.shift, .alt = mods.alt };
    const id = app.shortcuts.keymap.commandFor(combo) orelse return false;
    if (std.mem.startsWith(u8, id, "edit.")) return false;
    return app.registry.isAvailable(id);
}

fn onKey(context: *anyopaque, vk: u16, mods: ui.Mods) void {
    const app = of(context);
    _ = app.shortcuts.handle(.{ .vk = vk, .mods = mods });
    app.window.redraw();
}

fn openExternal(context: *anyopaque, target: []const u8) void {
    opener.systemOpen(of(context), target);
}

fn onChange(context: *anyopaque) void {
    of(context).window.redraw();
}

pub fn register(app: *App) void {
    opener.makers.set(.image, makeMedia);
    opener.makers.set(.video, makeMedia);
    opener.makers.set(.audio, makeMedia);
    opener.makers.set(.pdf, makeMedia);
    opener.rendered = makeRendered;
    preview.register(&app.registry, .{ .context = app, .focused = viewers.focusedDocument, .open = openPreview });
    media_preview.register(&app.registry, .{ .context = app, .focused = viewers.focusedDocument });
}

fn previewHost(app: *App) preview.Host {
    return .{ .context = app, .open_external = openExternal, .on_change = onChange, .on_key = onKey };
}

/// preview.open and the offer: a preview of `url`, or the pane that
/// already shows it.
fn openPreview(context: *anyopaque, url: []const u8, how: palette.How) void {
    const app = of(context);
    const env = environment(app) orelse return;
    const doc = preview.open(app.gpa, previewHost(app), env, url) catch return;
    viewers.defer_(app, .{ .document = .{ .doc = doc, .how = how } });
}

fn makeMedia(app: *App, path: []const u8, _: u32) ?tabs.Document {
    const env = environment(app) orelse return null;
    const host: media_preview.Host = .{ .context = app, .open_externally = openExternal, .on_key = onKey, .background = app.u.style.panel };
    return (media_preview.open(app.gpa, host, env, path) catch null) orelse null;
}

fn makeRendered(app: *App, path: []const u8, _: u32) ?tabs.Document {
    const env = environment(app) orelse return null;
    const t = app.themes.current.terminal;
    const s = app.u.style.secondary_text;
    const secondary: u32 = @as(u32, @intFromFloat(s.r * 255)) << 16 | @as(u32, @intFromFloat(s.g * 255)) << 8 | @as(u32, @intFromFloat(s.b * 255));
    const look = markdown_rendered.Look.fromTheme(t.background, t.foreground, secondary, t.ansi, editorFamily(app));
    return markdown_rendered.open(app.gpa, .{ .context = app, .open_link = openLink, .on_key = onKey }, env, path, null, look) catch null;
}

fn editorFamily(app: *App) []const u8 {
    const font = @import("looks.zig").terminalFont(app) orelse return "Cascadia Mono";
    return font.family;
}

/// A click in a rendered note: notes and files through markdown's index,
/// the web in the browser.
fn openLink(context: *anyopaque, link: markdown_rendered.Link, from: []const u8) void {
    const app = of(context);
    switch (link) {
        .web => |url| opener.systemOpen(app, url),
        .wiki => |name| app.markdown.openDestination(from, name, true),
        .file => |f| {
            var buf: [2048]u8 = undefined;
            const destination = if (f.fragment) |frag| std.fmt.bufPrint(&buf, "{s}#{s}", .{ f.path, frag }) catch f.path else f.path;
            app.markdown.openDestination(from, destination, false);
        },
    }
}

// ---- The terminal's offer ----

/// A terminal saw a local server: offer it once per address.
pub fn localServer(app: *App, session: *terminal.Session) void {
    var buf: [256]u8 = undefined;
    const url = session.localUrl(&buf);
    if (url.len == 0) return;
    for (app.offered.items) |seen| if (std.mem.eql(u8, seen, url)) return;
    const copy = app.gpa.dupe(u8, url) catch return;
    app.offered.append(app.gpa, copy) catch return app.gpa.free(copy);
    @memcpy(app.offer.url[0..url.len], url);
    app.offer.len = url.len;
    app.offer.until_ms = @as(i64, @intCast(c.GetTickCount64())) + offer_ms;
    app.window.redraw();
}

/// In the bottom right corner of the panes, while it lasts.
pub fn drawOffer(app: *App) void {
    const u = &app.u;
    if (app.offer.len == 0) return;
    if (u.now_ms >= app.offer.until_ms) {
        app.offer.len = 0;
        return;
    }
    u.requestFrame(@intCast(app.offer.until_ms - u.now_ms));
    const url = app.offer.url[0..app.offer.len];
    var label_buf: [300]u8 = undefined;
    const label = std.fmt.bufPrint(&label_buf, "{s}  {s}", .{ strings.t("Open in preview", "Abrir no preview"), url }) catch strings.t("Open in preview", "Abrir no preview");
    const width = @min(u.px(360), app.panes_area.w - u.px(24));
    const r: gfx.Rect = .{ .x = app.panes_area.right() - width - u.px(12), .y = app.panes_area.bottom() - u.px(44), .w = width, .h = u.px(32) };
    if (ui.widgets.button(u, ui.id("preview.offer", 0), r, label, .{ .icon = icons.phosphor.globe, .icon_size = 14 })) {
        app.offer.len = 0;
        openPreview(app, url, .normal);
    }
}

test {
    w.refAllDeep(@This());
}
