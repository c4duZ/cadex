//! The settings (Ctrl+Shift+, the Mac's ⌘,): one page over the window with
//! the Mac's tabs (General, Terminal, Themes, Shortcuts, About), each page in
//! sections whose rows say what they change (docs/spec/settings.md). Every
//! change is saved to settings.json at once and counts everywhere; the
//! language and the interface's zoom, density and font count when Cadex
//! reopens. The pages are in settings_rows.zig and themes_page.zig; they
//! scroll when taller than the window. settings.open-terminal and
//! settings.open-themes open it on that page (plan 15).

const std = @import("std");
const gfx = @import("gfx");
const ui = @import("ui");
const w = @import("win32");
const icons = @import("icons");
const settings = @import("settings");
const strings = @import("strings");
const App = @import("app.zig").App;
const wiring = @import("wiring.zig");
const rows = @import("settings_rows.zig");

const t = strings.t;

const Section = enum { general, terminal, themes, shortcuts, about };

var open = false;
var section: Section = .general;
/// The themes list's and the shortcuts list's scroll.
pub var scroll: ui.list.Scroll = .{};
/// The page's own scroll, and how tall it was last frame.
var page_scroll: ui.list.Scroll = .{};
var content_h: f32 = 0;

var app_ref: *App = undefined;

/// settings.open-terminal, settings.open-themes and terminal.toggle-ligatures,
/// as the Mac's SettingsWindowController.pageCommands.
pub fn register(app: *App) void {
    app_ref = app;
    const r = &app.registry;
    r.add(.{ .id = "settings.open-terminal", .title = t("Open Terminal Settings", "Abrir configurações do terminal"), .keywords = &.{ "font", "fonte", "line height", "altura da linha", "spacing", "espaçamento", "contrast", "contraste", "cursor" }, .run = openTerminal });
    r.add(.{ .id = "settings.open-themes", .title = t("Open Theme Settings", "Abrir configurações de temas"), .keywords = &.{ "theme", "tema", "accent", "destaque", "contrast", "contraste", "background", "fundo" }, .run = openThemes });
    r.add(.{ .id = "terminal.toggle-ligatures", .title = t("Turn Ligatures On or Off", "Ligar ou desligar as ligaduras"), .keywords = &.{ "ligatures", "ligaduras", "fira code", "font", "fonte" }, .run = toggleLigatures });
}

fn openTerminal(_: ?*anyopaque) void {
    show(app_ref, .terminal);
}

fn openThemes(_: ?*anyopaque) void {
    show(app_ref, .themes);
}

fn toggleLigatures(_: ?*anyopaque) void {
    @import("terminal_text_rows.zig").toggleLigatures(app_ref);
}

/// Opens the settings on `page_section` (or moves there when open).
fn show(app: *App, page_section: Section) void {
    if (!open) toggle(app);
    select(page_section);
    app.window.redraw();
}

fn select(next: Section) void {
    section = next;
    scroll = .{};
    page_scroll = .{};
}

pub fn toggle(app: *App) void {
    open = !open;
    if (open) {
        rows.prepare(app);
        app.u.focus = ui.id("settings.page", 0);
    } else app.u.focus = ui.context.none;
    app.window.redraw();
}

pub fn isOpen() bool {
    return open;
}

/// Whether the Themes page is on screen (it keeps the list of themes
/// only while it is).
pub fn showsThemes() bool {
    return open and section == .themes;
}

/// Saves `next` and applies it to every feature.
pub fn commit(app: *App, next: settings.Settings) void {
    app.settings.save(next);
    wiring.applySettings(app);
}

pub fn draw(app: *App) void {
    if (!open) return;
    const u = &app.u;
    const full: gfx.Rect = .{ .w = u.size.x, .h = u.size.y };
    u.beginOverlay(full);
    defer u.endOverlay();
    u.painter.fill(full, gfx.Color.black.alpha(0.35));
    const box_w = @min(u.px(820), u.size.x - u.px(40));
    const box_h = @min(u.px(620), u.size.y - u.px(60));
    const box: gfx.Rect = .{ .x = (u.size.x - box_w) / 2, .y = (u.size.y - box_h) / 2, .w = box_w, .h = box_h };
    u.painter.fillRounded(box.inset(-1, -1), u.px(12), u.style.panel_border);
    u.painter.fillRounded(box, u.px(12), u.style.panel);
    var inner = box.inset(u.px(16), u.px(14));
    var header = inner.takeTop(u.px(32));
    u.painter.text(t("Settings", "Configurações"), u.style.bold(), header.takeLeft(u.px(240)), u.style.text, .{});
    if (ui.widgets.iconButton(u, ui.id("settings.close", 0), header.takeRight(u.px(30)), icons.phosphor.x, .{ .icon_size = 14 })) toggle(app);
    _ = inner.takeTop(u.px(8));
    var nav = inner.takeLeft(u.px(160));
    _ = inner.takeLeft(u.px(16));
    const tabs = [_]struct { Section, []const u8, u21 }{
        .{ .general, t("General", "Geral"), icons.phosphor.gear_six },
        .{ .terminal, "Terminal", icons.phosphor.terminal_window },
        .{ .themes, t("Themes", "Temas"), icons.phosphor.palette },
        .{ .shortcuts, t("Shortcuts", "Atalhos"), icons.phosphor.keyboard },
        .{ .about, t("About", "Sobre"), icons.phosphor.info },
    };
    for (tabs, 0..) |entry, i| {
        const r = nav.takeTop(u.px(32));
        if (ui.widgets.button(u, ui.child(ui.id("settings.nav", 0), i), r, entry[1], .{ .icon = entry[2], .selected = section == entry[0], .@"align" = .{} })) select(entry[0]);
        _ = nav.takeTop(u.px(2));
    }
    switch (section) {
        .general => scrolled(app, inner, rows.general),
        .terminal => scrolled(app, inner, rows.terminal),
        .themes => scrolled(app, inner, @import("themes_page.zig").draw),
        .shortcuts => shortcutsSection(app, inner),
        .about => about(app, inner),
    }
    if (u.key(w.c.VK_ESCAPE, .{})) toggle(app);
}

/// A page taller than the window scrolls: it draws into a tall rectangle
/// moved up by the scroll, clipped to `area`, and says how tall it was.
/// Widgets scrolled out of view get no mouse (Ui.mouse_clip).
fn scrolled(app: *App, area: gfx.Rect, comptime drawPage: fn (*App, gfx.Rect, f32) f32) void {
    const u = &app.u;
    const before = page_scroll.offset;
    const tall: gfx.Rect = .{ .x = area.x, .y = area.y - page_scroll.offset, .w = area.w - u.px(12), .h = @max(content_h, area.h) + u.px(400) };
    u.painter.pushClip(area);
    const outer = u.mouse_clip;
    u.mouse_clip = area;
    content_h = drawPage(app, tall, area.h);
    u.mouse_clip = outer;
    u.painter.popClip();
    // After the page: a list inside it took the wheel first.
    ui.list.scrollArea(u, ui.id("settings.page-scroll", 0), area, content_h, &page_scroll);
    if (page_scroll.offset != before) app.window.redraw();
}

// ---- The pieces every page uses ----

/// A section title between groups of rows, in small capitals' place: a
/// little room above, the title in the secondary color.
pub fn heading(u: *ui.Ui, area: *gfx.Rect, title: []const u8) void {
    _ = area.takeTop(u.px(10));
    u.painter.text(title, u.style.bold(), area.takeTop(u.px(24)), u.style.secondary_text, .{});
}

/// A row: the title on the left, a one-line explanation under it when
/// given, the control's rectangle (returned) on the right.
pub fn row(u: *ui.Ui, area: *gfx.Rect, title: []const u8, explanation: ?[]const u8) gfx.Rect {
    var r = area.takeTop(u.px(if (explanation == null) 40 else 50));
    var left = r.takeLeft(r.w * 0.55);
    if (explanation) |n| {
        u.painter.text(title, u.style.ui(), left.takeTop(left.h * 0.55), u.style.text, .{ .vcenter = true });
        u.painter.text(n, u.style.small(), left, u.style.secondary_text, .{ .vcenter = false });
    } else {
        u.painter.text(title, u.style.ui(), left, u.style.text, .{});
    }
    return r.inset(0, u.px(if (explanation == null) 0 else 5));
}

/// A line to read, without a control (how the lid works with keep awake).
pub fn note(u: *ui.Ui, area: *gfx.Rect, text: []const u8) void {
    u.painter.text(text, u.style.small(), area.takeTop(u.px(26)), u.style.secondary_text, .{});
}

/// A choice among a few values, as segments; the new one when clicked.
pub fn choice(u: *ui.Ui, r: gfx.Rect, name: []const u8, value: []const u8, options: []const [2][]const u8) ?[]const u8 {
    var area = r.inset(0, u.px(6));
    const each = area.w / @as(f32, @floatFromInt(options.len));
    var picked: ?[]const u8 = null;
    for (options, 0..) |o, i| {
        const seg = area.takeLeft(each);
        const id = ui.child(ui.id("settings.choice", 0), std.hash.Wyhash.hash(0, name) +% i);
        if (ui.widgets.button(u, id, seg.inset(u.px(1), 0), o[1], .{ .selected = std.mem.eql(u8, o[0], value), .radius = 5 })) picked = o[0];
    }
    return picked;
}

pub fn stepper(u: *ui.Ui, r: gfx.Rect, name: usize, value: f64, step: f64, unit: []const u8) ?f64 {
    var area = r.inset(0, u.px(6));
    const minus = area.takeLeft(u.px(30));
    const plus = area.takeRight(u.px(30));
    var buf: [32]u8 = undefined;
    const label = std.fmt.bufPrint(&buf, "{d}{s}", .{ value, unit }) catch "";
    u.painter.text(label, u.style.ui(), area, u.style.text, .{ .@"align" = .center });
    if (ui.widgets.button(u, ui.child(ui.id("settings.step", 0), name * 2), minus, "−", .{})) return value - step;
    if (ui.widgets.button(u, ui.child(ui.id("settings.step", 0), name * 2 + 1), plus, "+", .{})) return value + step;
    return null;
}

// ---- Shortcuts and About ----

fn shortcutsSection(app: *App, area_in: gfx.Rect) void {
    const u = &app.u;
    var area = area_in;
    u.painter.text(t("Edit the \"shortcuts\" section of settings.json (the Mac's ⌘ is Ctrl+Shift here).", "Edite a seção \"shortcuts\" do settings.json (⌘ do Mac é Ctrl+Shift aqui)."), u.style.small(), area.takeTop(u.px(24)), u.style.secondary_text, .{});
    const commands = app.registry.commands.items;
    const view = ui.list.begin(u, ui.id("settings.shortcuts", 0), area, commands.len, u.px(30), &scroll);
    defer ui.list.end(u);
    var arena: std.heap.ArenaAllocator = .init(app.gpa);
    defer arena.deinit();
    for (view.first..view.last) |i| {
        const command = commands[i];
        var r = view.row(i);
        const label = @import("shortcuts").Shortcuts.label(&app.shortcuts, command.id, arena.allocator());
        if (label.len > 0) _ = ui.widgets.keys(u, r.takeRight(u.px(200)), &.{label});
        u.painter.text(command.title, u.style.ui(), r, u.style.text, .{});
    }
}

fn about(app: *App, area_in: gfx.Rect) void {
    const u = &app.u;
    var area = area_in;
    u.painter.text("Cadex", u.style.bold(), area.takeTop(u.px(30)), u.style.text, .{});
    note(u, &area, t("A terminal-centered development workspace, native, with its own code under the MIT license.", "Workspace de desenvolvimento centrado no terminal, nativo, com código próprio sob a licença MIT."));
    note(u, &area, t("The terminal model is libghostty-vt; the icons are Phosphor; full credits in the NOTICE file.", "O modelo do terminal é a libghostty-vt; os ícones são Phosphor; créditos completos no arquivo NOTICE."));
}

test {
    @import("win32").refAllDeep(@This());
}
