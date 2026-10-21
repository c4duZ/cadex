//! The Themes page of the settings, as the Mac's ThemesPage.swift: the mode,
//! Mica, the user's themes (open the folder, import), a search with an
//! All/Dark/Light filter, the files of the folder that could not be read,
//! and the themes as a list that draws only the rows in view. Picking one
//! changes the theme at once (docs/spec/themes.md).
//!
//! The list of every theme is read when the page shows and freed when it
//! does not (releaseWhenHidden, after each frame): hundreds of themes must
//! not weigh on the app (plan 15).

const std = @import("std");
const gfx = @import("gfx");
const ui = @import("ui");
const strings = @import("strings");
const themes = @import("themes");
const App = @import("app.zig").App;
const page = @import("settings_page.zig");
const commands = @import("theme_commands.zig");

const t = strings.t;

var list: ?themes.library.List = null;
/// Indices in list.families that pass the search and the filter.
var shown: std.ArrayList(usize) = .empty;
var stale = true;
var query: ui.TextBuffer = .{};
var query_scroll: ui.text_field.Scroll = .{};
/// "all", "dark" or "light", as the filter's segments name them.
var filter: []const u8 = "all";
var placeholder_buf: [64]u8 = undefined;

pub fn draw(app: *App, area_in: gfx.Rect) void {
    const u = &app.u;
    var area = area_in;
    var s = app.settings.current;
    if (page.choice(u, page.row(u, &area, t("Mode", "Modo"), t("The theme's light or dark version, or the system's.", "A versão clara ou escura do tema, ou a do sistema.")), "mode", s.appearance.mode, &.{ .{ "system", t("System", "Sistema") }, .{ "dark", t("Dark", "Escuro") }, .{ "light", t("Light", "Claro") } })) |v| {
        s.appearance.mode = v;
        page.commit(app, s);
    }
    if (ui.widgets.toggle(u, ui.id("settings.vibrancy", 0), page.row(u, &area, t("Mica behind the frame", "Mica atrás da moldura"), t("The frame shows the desktop, blurred; panels stay solid.", "A moldura mostra a área de trabalho, desfocada; os painéis seguem sólidos.")), s.appearance.vibrancy)) |v| {
        s.appearance.vibrancy = v;
        page.commit(app, s);
    }
    yourThemes(app, &area);
    page.heading(u, &area, t("Theme", "Tema"));
    const l = loaded(app);
    toolbar(app, &area, l.families.len);
    problems(u, &area, l.problems);
    themeList(app, area, l.families);
}

/// Opening the themes folder and importing a theme file.
fn yourThemes(app: *App, area: *gfx.Rect) void {
    const u = &app.u;
    var r = page.row(u, area, t("Your themes", "Seus temas"), t("From iTerm2, Ghostty, base16 or base24; .json files in the folder show first.", "Do iTerm2, Ghostty, base16 ou base24; arquivos .json da pasta aparecem primeiro."));
    r = r.inset(0, u.px(1));
    const import_r = r.takeRight(u.px(110));
    _ = r.takeRight(u.px(6));
    const folder_r = r.takeRight(u.px(110));
    if (ui.widgets.button(u, ui.id("settings.theme-import", 0), import_r, t("Import…", "Importar…"), .{ .selected = true })) commands.importTheme(app);
    if (ui.widgets.button(u, ui.id("settings.theme-folder", 0), folder_r, t("Open Folder", "Abrir pasta"), .{ .selected = true })) commands.openFolder(app);
}

/// The search field and the All/Dark/Light filter.
fn toolbar(app: *App, area: *gfx.Rect, count: usize) void {
    const u = &app.u;
    var bar = area.takeTop(u.px(38));
    const kinds = bar.takeRight(u.px(240));
    _ = bar.takeRight(u.px(10));
    const placeholder = std.fmt.bufPrint(&placeholder_buf, "{s} {d} {s}", .{ t("Search", "Buscar entre"), count, t("themes", "temas") }) catch "";
    const result = ui.text_field.textField(u, ui.id("settings.theme-search", 0), bar.inset(0, u.px(4)), &query, &query_scroll, .{ .placeholder = placeholder });
    if (result.changed) stale = true;
    if (page.choice(u, kinds, "themeFilter", filter, &.{ .{ "all", t("All", "Todos") }, .{ "dark", t("Dark", "Escuros") }, .{ "light", t("Light", "Claros") } })) |v| {
        filter = v;
        stale = true;
        page.scroll = .{};
    }
    if (stale) refilter(app.gpa);
}

/// Files of the folder that could not be read, a few lines at most.
fn problems(u: *ui.Ui, area: *gfx.Rect, lines: []const []const u8) void {
    if (lines.len == 0) return;
    page.note(u, area, t("Themes in your folder that could not be read:", "Temas da sua pasta que não deu para ler:"));
    for (lines[0..@min(lines.len, 3)]) |line| page.note(u, area, line);
}

fn themeList(app: *App, area: gfx.Rect, families: []const themes.Family) void {
    const u = &app.u;
    var s = app.settings.current;
    const view = ui.list.begin(u, ui.id("settings.themes", 0), area, shown.items.len, u.px(44), &page.scroll);
    defer ui.list.end(u);
    for (view.first..view.last) |i| {
        const f = families[shown.items[i]];
        const r = view.row(i).inset(0, u.px(1));
        if (ui.widgets.button(u, ui.child(ui.id("settings.theme", 0), i), r, "", .{ .selected = std.mem.eql(u8, f.id, s.appearance.theme) })) {
            s.appearance.theme = f.id;
            page.commit(app, s);
        }
        var inner = r.inset(u.px(10), u.px(4));
        swatches(u, inner.takeRight(u.px(5 * 18)), f.theme(app.themes.current.dark));
        u.painter.text(f.name, u.style.ui(), inner.takeTop(inner.h * 0.5), u.style.text, .{});
        u.painter.text(f.description, u.style.small(), inner, u.style.secondary_text, .{});
    }
}

/// The family's colors as five dots: background, accent, red, green, blue.
fn swatches(u: *ui.Ui, area: gfx.Rect, th: themes.Theme) void {
    var sw = area.inset(0, (area.h - u.px(14)) / 2);
    for ([_]u32{ th.terminal.background, th.interface.accent, th.terminal.ansi[1], th.terminal.ansi[2], th.terminal.ansi[4] }) |color| {
        const dot = sw.takeRight(u.px(14));
        u.painter.fillRounded(dot, u.px(3), gfx.Color.rgb(color));
        _ = sw.takeRight(u.px(4));
    }
}

fn loaded(app: *App) *themes.library.List {
    if (list == null) {
        list = themes.library.all(app.gpa, app.themes.folder);
        stale = true;
    }
    return &list.?;
}

/// The families that pass the filter and hold the query in their name or
/// description (case does not matter), in the list's order.
fn refilter(gpa: std.mem.Allocator) void {
    stale = false;
    shown.clearRetainingCapacity();
    const l = list orelse return;
    for (l.families, 0..) |f, i| {
        if (std.mem.eql(u8, filter, "dark") and f.dark == null) continue;
        if (std.mem.eql(u8, filter, "light") and f.light == null) continue;
        if (!commands.matches(f, query.text())) continue;
        shown.append(gpa, i) catch return;
    }
}

/// The folder changed (an import): read the list again when shown.
pub fn invalidate(app: *App) void {
    if (list) |*l| l.deinit();
    list = null;
    shown.clearAndFree(app.gpa);
}

/// After each frame: the list goes when the page is not on screen.
pub fn releaseWhenHidden(app: *App) void {
    if (list != null and !page.showsThemes()) invalidate(app);
}

test {
    @import("win32").refAllDeep(@This());
}
