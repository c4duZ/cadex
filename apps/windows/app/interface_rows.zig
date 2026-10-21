//! The General page's interface rows (plan 15, phase D), as the Mac's
//! InterfaceRows.swift: zoom, density and the interface's font, apart from
//! the terminal's. They count when Cadex opens (looks.zig reads them once),
//! so a change offers "Reopen now", as the language does.

const std = @import("std");
const gfx = @import("gfx");
const ui = @import("ui");
const strings = @import("strings");
const settings = @import("settings");
const App = @import("app.zig").App;
const page = @import("settings_page.zig");
const relaunch = @import("relaunch.zig");
const looks = @import("looks.zig");

const t = strings.t;

var font_text: ui.TextBuffer = .{};
var font_scroll: ui.text_field.Scroll = .{};

/// The field starts with the saved font each time the page opens.
pub fn prepare(app: *App) void {
    font_text.set(app.gpa, app.settings.current.appearance.ui_font) catch {};
}

pub fn draw(app: *App, area: *gfx.Rect) void {
    const u = &app.u;
    var s = app.settings.current;
    page.heading(u, area, "Interface");
    var zoom_buf: [16]u8 = undefined;
    const zoom = std.fmt.bufPrint(&zoom_buf, "{d}", .{s.appearance.ui_zoom}) catch "1";
    const zooms = [_][2][]const u8{ .{ "0.8", "80%" }, .{ "0.9", "90%" }, .{ "1", "100%" }, .{ "1.1", "110%" }, .{ "1.25", "125%" }, .{ "1.5", "150%" } };
    if (page.choice(u, page.row(u, area, "Zoom", t("The size of everything around the terminal: tabs, the file tree, menus, Ctrl+Shift+K. The terminal keeps its own font size.", "O tamanho de tudo em volta do terminal: abas, árvore de arquivos, menus, Ctrl+Shift+K. O terminal fica com o tamanho de fonte dele.")), "uiZoom", zoom, &zooms)) |v| {
        s.appearance.ui_zoom = std.fmt.parseFloat(f64, v) catch 1;
        page.commit(app, s);
    }
    if (page.choice(u, page.row(u, area, t("Density", "Densidade"), t("Compact fits more rows in the file tree, the lists and the menus.", "Compacta cabe mais linhas na árvore de arquivos, nas listas e nos menus.")), "density", s.appearance.density, &.{ .{ "normal", "Normal" }, .{ "compact", t("Compact", "Compacta") } })) |v| {
        s.appearance.density = v;
        page.commit(app, s);
    }
    {
        const r = page.row(u, area, t("Interface font", "Fonte da interface"), t("The font of the tabs, the tree and the lists; empty is the system's. The terminal's is in Terminal.", "A fonte das abas, da árvore e das listas; vazio é a do sistema. A do terminal fica em Terminal."));
        const res = ui.text_field.textField(u, ui.id("settings.ui-font", 0), r.inset(0, u.px(4)), &font_text, &font_scroll, .{ .placeholder = "Segoe UI Variable Text" });
        if (res.submitted) {
            s.appearance.ui_font = std.mem.trim(u8, font_text.text(), " ");
            page.commit(app, s);
        }
    }
    if (page.stepper(u, page.row(u, area, t("Interface text size", "Tamanho do texto da interface"), t("From 9 to 24 points; 13 is the usual.", "De 9 a 24 pontos; 13 é o comum.")), 30, s.appearance.ui_font_size, 1, " pt")) |v| {
        s.appearance.ui_font_size = std.math.clamp(v, settings.model.ui_font_sizes[0], settings.model.ui_font_sizes[1]);
        page.commit(app, s);
    }
    // They count at launch: offer to reopen while they differ.
    if (looks.needsRelaunch(app.settings.current)) {
        const r = page.row(u, area, t("Reopen to use the new interface size or font", "Reabrir para usar o novo tamanho ou fonte da interface"), null);
        if (ui.widgets.button(u, ui.id("settings.relaunch-looks", 0), r.inset(0, u.px(6)), t("Reopen now", "Reabrir agora"), .{ .primary = true })) relaunch.request(app);
    }
}

test {
    @import("win32").refAllDeep(@This());
}
