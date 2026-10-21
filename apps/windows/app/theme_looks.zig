//! The themes page's rows and commands of plan 15, phases B and C, as the
//! Mac's ThemeLooksRows.swift and ThemeActions.swift: one theme for dark
//! mode and one for light, the accent color (Windows' color dialog in place
//! of the Mac's color well), high contrast and how dark the panes without
//! focus are.

const std = @import("std");
const gfx = @import("gfx");
const ui = @import("ui");
const w = @import("win32");
const strings = @import("strings");
const themes = @import("themes");
const App = @import("app.zig").App;
const page = @import("settings_page.zig");
const looks = @import("looks.zig");

const t = strings.t;

var app_ref: *App = undefined;

pub fn register(app: *App) void {
    app_ref = app;
    const r = &app.registry;
    r.add(.{ .id = "theme.accent", .title = t("Choose Accent Color", "Escolher cor de destaque"), .keywords = &.{ "accent", "destaque", "cor", "color", "highlight" }, .run = accentRun });
    r.add(.{ .id = "theme.accent-reset", .title = t("Use the Theme's Accent Color", "Usar a cor de destaque do tema"), .keywords = &.{ "accent", "destaque", "cor", "color", "reset" }, .run = resetRun, .available = hasAccent });
    r.add(.{ .id = "theme.toggle-high-contrast", .title = t("Turn High Contrast On or Off", "Ligar ou desligar o alto contraste"), .keywords = &.{ "contrast", "contraste", "accessibility", "acessibilidade", "legibilidade" }, .run = toggleHighContrast });
}

fn accentRun(_: ?*anyopaque) void {
    pickAccent(app_ref);
}

fn resetRun(_: ?*anyopaque) void {
    setAccent(app_ref, "");
}

fn hasAccent(_: ?*anyopaque) bool {
    return app_ref.settings.current.appearance.accent.len > 0;
}

fn toggleHighContrast(_: ?*anyopaque) void {
    var s = app_ref.settings.current;
    s.appearance.high_contrast = !s.appearance.high_contrast;
    page.commit(app_ref, s);
}

fn setAccent(app: *App, hex: []const u8) void {
    var s = app.settings.current;
    s.appearance.accent = hex;
    page.commit(app, s);
}

/// Windows' color dialog, starting at the accent in use; the pick is saved.
pub fn pickAccent(app: *App) void {
    const rgb = w.color_dialog.pick(app.window.hwnd, app.themes.current.interface.accent) orelse return;
    var buf: [7]u8 = undefined;
    setAccent(app, themes.contrast.formatHex(&buf, rgb));
}

// ---- The themes page's rows ----

/// "Dark and light": which theme each mode shows, and a button back to one.
pub fn pairRow(app: *App, area: *gfx.Rect) void {
    const u = &app.u;
    const a = app.settings.current.appearance;
    const dark = looks.inUseDark(a);
    const light = looks.inUseLight(a);
    var buf: [400]u8 = undefined;
    const names = .{ app.themes.dark.family.name, app.themes.light.family.name };
    const now = if (std.mem.eql(u8, dark, light))
        std.fmt.bufPrint(&buf, "{s} {s}.", .{ t("Now one theme for both:", "Agora um tema para os dois:"), names[0] }) catch ""
    else
        std.fmt.bufPrint(&buf, "{s} {s} {s} {s} {s}", .{ t("Now", "Agora"), names[0], t("in dark mode and", "no modo escuro e"), names[1], t("in light mode.", "no claro.") }) catch "";
    var r = page.row(u, area, t("Dark and light", "Escuro e claro"), now);
    const button = r.takeRight(u.px(150));
    const one = ui.widgets.button(u, ui.id("settings.one-theme", 0), button, t("Use One Theme", "Usar um tema só"), .{ .selected = true, .enabled = !std.mem.eql(u8, dark, light) });
    if (one and !std.mem.eql(u8, dark, light)) {
        var s = app.settings.current;
        s.appearance.theme = dark;
        s.appearance.dark_theme = "";
        s.appearance.light_theme = "";
        page.commit(app, s);
    }
    page.note(u, area, t("To pick a theme for one mode only, filter Dark or Light below and pick it there.", "Para escolher um tema só para um modo, filtre Escuros ou Claros abaixo e escolha lá."));
}

/// "Accent color": a swatch that opens the color dialog, and the theme's again.
pub fn accentRow(app: *App, area: *gfx.Rect) void {
    const u = &app.u;
    const a = app.settings.current.appearance;
    var r = page.row(u, area, t("Accent color", "Cor de destaque"), t("Paints the active tab, the selection, focus and icons that are on. Text over it turns black or white to stay readable.", "Pinta a aba ativa, a seleção, o foco e os ícones ligados. O texto por cima vira preto ou branco para continuar legível."));
    const well = r.takeRight(u.px(44));
    _ = r.takeRight(u.px(8));
    const reset = r.takeRight(u.px(90));
    if (ui.widgets.button(u, ui.id("settings.accent-reset", 0), reset, t("Theme's", "Do tema"), .{ .selected = true, .enabled = a.accent.len > 0 }) and a.accent.len > 0) setAccent(app, "");
    if (ui.widgets.button(u, ui.id("settings.accent", 0), well, "", .{ .selected = true })) pickAccent(app);
    u.painter.fillRounded(well.inset(u.px(6), u.px(5)), u.px(4), gfx.Color.rgb(app.themes.current.interface.accent));
}

/// "Reading": high contrast and the panes without focus.
pub fn readingRows(app: *App, area: *gfx.Rect) void {
    const u = &app.u;
    var s = app.settings.current;
    page.heading(u, area, t("Reading", "Leitura"));
    if (ui.widgets.toggle(u, ui.id("settings.high-contrast", 0), page.row(u, area, t("High contrast", "Alto contraste"), t("All text at 7:1, stronger borders and focus, no transparency. Also turns on with a contrast theme of Windows (Accessibility).", "Todo texto a 7:1, bordas e foco mais fortes, sem transparência. Liga também com um tema de contraste do Windows (Acessibilidade).")), s.appearance.high_contrast)) |v| {
        s.appearance.high_contrast = v;
        page.commit(app, s);
    }
    const r = page.row(u, area, t("Panes without focus", "Painéis sem foco"), t("How much darker the other panes of a tab are, so the one you type in stands out. 0 turns it off.", "O quanto os outros painéis de uma aba ficam mais escuros, para destacar aquele em que você digita. 0 desliga."));
    const percent = @round(s.tabs.unfocused_dim * 100);
    if (page.stepper(u, r, 20, percent, 2, "%")) |v| {
        s.tabs.unfocused_dim = std.math.clamp(v / 100, 0, 0.6);
        page.commit(app, s);
    }
}

test {
    @import("win32").refAllDeep(@This());
}
