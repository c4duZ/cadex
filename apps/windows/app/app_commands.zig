//! The commands the app itself owns (the Mac's StandardCommands, the
//! palette's, the terminal's responder actions) and the registration of
//! every feature's. Edit commands go to whatever has the focus: the
//! terminal or the document of the focused pane.

const std = @import("std");
const w = @import("win32");
const gfx = @import("gfx");
const ui = @import("ui");
const icons = @import("icons");
const palette = @import("command-palette");
const terminal = @import("terminal");
const tabs = @import("tabs");
const App = @import("app.zig").App;

const c = w.c;
const p = icons.phosphor;

/// The ways to open things, first in the palette and in the "+" menu (the
/// Mac's openers).
pub const openers = [_]palette.Pin{
    .{ .id = "pane.split-right", .title = "Terminal ao lado", .icon = p.terminal_window },
    .{ .id = "search.files", .title = "Arquivo…", .icon = p.file },
    .{ .id = "preview.open", .title = "Preview web", .icon = p.globe },
    .{ .id = "git.history", .title = "Grafo do git", .icon = p.git_branch },
    .{ .id = "tab.new", .title = "Terminal em nova aba", .icon = p.plus },
};

pub const plus_items = blk: {
    var items: [openers.len]ui.menu.Item = undefined;
    for (openers, 0..) |o, i| items[i] = .{ .label = o.title, .icon = o.icon };
    break :blk items;
};

/// The icons of the palette's sections, in registry.sections' order, then "Cadex".
pub const section_icons = [_]u21{
    p.files, p.sidebar, p.folder, p.magnifying_glass, p.code, p.terminal_window,
    p.git_branch, p.globe, p.stack, p.keyboard, p.gear_six,
};

var app_ref: *App = undefined;

fn focusedView() ?*terminal.View {
    return app_ref.tabs.focusedTerminal();
}

fn openPalette(_: ?*anyopaque) void {
    app_ref.palette.toggle(&app_ref.u, app_ref.palette.commands);
}

fn openSettings(_: ?*anyopaque) void {
    @import("settings_page.zig").toggle(app_ref);
}

fn quit(_: ?*anyopaque) void {
    _ = c.PostMessageW(app_ref.window.hwnd, c.WM_CLOSE, 0, 0);
}

fn hide(_: ?*anyopaque) void {
    _ = c.ShowWindow(app_ref.window.hwnd, c.SW_MINIMIZE);
}

/// Another window is another Cadex process, in the focused pane's folder.
fn newWindow(_: ?*anyopaque) void {
    var path: [c.MAX_PATH + 1]u16 = undefined;
    const n = c.GetModuleFileNameW(null, &path, path.len);
    if (n == 0) return;
    path[n] = 0;
    _ = c.ShellExecuteW(null, w.L("open"), &path, null, null, c.SW_SHOWNORMAL);
}

const Edit = tabs.Document.EditAction;

fn edit(action: Edit) void {
    const app = app_ref;
    if (app.tabs.focusedDocument()) |d| {
        _ = d.edit(&app.u, action);
        return;
    }
    const view = focusedView() orelse return;
    switch (action) {
        .copy => _ = view.copySelection(&app.u),
        .paste => {
            const plan = terminal.paste.plan(app.gpa, app.window.hwnd, view.session, app.settings.current.general.confirm_multiline_paste) orelse return;
            if (plan.needs_confirmation) {
                app.pending_paste = plan;
            } else {
                terminal.paste.send(view.session, plan);
                plan.deinit(app.gpa);
            }
        },
        .select_all => view.selectAll(),
        .find => view.find.show(&app.u),
        .cut, .undo, .redo => {},
    }
    app.window.redraw();
}

fn copy(_: ?*anyopaque) void {
    edit(.copy);
}
fn cut(_: ?*anyopaque) void {
    edit(.cut);
}
fn paste(_: ?*anyopaque) void {
    edit(.paste);
}
fn selectAll(_: ?*anyopaque) void {
    edit(.select_all);
}
fn find(_: ?*anyopaque) void {
    edit(.find);
}
fn undo(_: ?*anyopaque) void {
    edit(.undo);
}
fn redo(_: ?*anyopaque) void {
    edit(.redo);
}

fn hasFocusTarget(_: ?*anyopaque) bool {
    return focusedView() != null or app_ref.tabs.focusedDocument() != null;
}

fn hasTerminal(_: ?*anyopaque) bool {
    return focusedView() != null;
}

fn clear(_: ?*anyopaque) void {
    if (focusedView()) |v| v.clear();
}
fn scrollTop(_: ?*anyopaque) void {
    if (focusedView()) |v| v.scrollTo(true);
}
fn scrollBottom(_: ?*anyopaque) void {
    if (focusedView()) |v| v.scrollTo(false);
}

pub fn register(app: *App) void {
    app_ref = app;
    const r = &app.registry;
    r.add(.{ .id = "palette.open", .title = "Abrir a paleta de comandos", .keywords = &.{ "comandos", "command palette" }, .shortcut = "cmd+k", .run = openPalette });
    r.add(.{ .id = "settings.open", .title = "Abrir configurações", .keywords = &.{ "settings", "preferências", "ajustes" }, .shortcut = "cmd+,", .run = openSettings });
    r.add(.{ .id = "app.quit", .title = "Sair do Cadex", .keywords = &.{ "quit", "fechar app" }, .shortcut = "cmd+q", .run = quit });
    r.add(.{ .id = "app.hide", .title = "Ocultar o Cadex", .keywords = &.{ "hide", "minimizar" }, .shortcut = "cmd+h", .run = hide });
    r.add(.{ .id = "window.new", .title = "Nova janela", .keywords = &.{ "new window", "janela" }, .shortcut = "cmd+n", .run = newWindow });
    r.add(.{ .id = "edit.undo", .title = "Desfazer", .keywords = &.{"undo"}, .shortcut = "cmd+z", .run = undo, .available = hasFocusTarget });
    r.add(.{ .id = "edit.redo", .title = "Refazer", .keywords = &.{"redo"}, .shortcut = "cmd+shift+z", .run = redo, .available = hasFocusTarget });
    r.add(.{ .id = "edit.cut", .title = "Recortar", .keywords = &.{"cut"}, .shortcut = "cmd+x", .run = cut, .available = hasFocusTarget });
    r.add(.{ .id = "edit.copy", .title = "Copiar", .keywords = &.{ "copy", "seleção" }, .shortcut = "cmd+c", .run = copy, .available = hasFocusTarget });
    r.add(.{ .id = "edit.paste", .title = "Colar", .keywords = &.{"paste"}, .shortcut = "cmd+v", .run = paste, .available = hasFocusTarget });
    r.add(.{ .id = "edit.find", .title = "Buscar", .keywords = &.{ "find", "procurar", "pesquisar" }, .shortcut = "cmd+f", .run = find, .available = hasFocusTarget });
    r.add(.{ .id = "edit.select-all", .title = "Selecionar tudo", .keywords = &.{"select all"}, .shortcut = "cmd+a", .run = selectAll, .available = hasFocusTarget });
    r.add(.{ .id = "terminal.clear", .title = "Limpar o terminal", .keywords = &.{ "clear", "cls", "tela" }, .shortcut = "cmd+l", .run = clear, .available = hasTerminal });
    r.add(.{ .id = "terminal.scroll-top", .title = "Ir ao topo do histórico", .keywords = &.{ "scroll", "rolar", "início" }, .shortcut = "cmd+up", .run = scrollTop, .available = hasTerminal });
    r.add(.{ .id = "terminal.scroll-bottom", .title = "Ir ao fim do histórico", .keywords = &.{ "scroll", "rolar", "final" }, .shortcut = "cmd+down", .run = scrollBottom, .available = hasTerminal });
    tabs.commands.register(r, .{
        .context = app,
        .tabs = currentTabs,
        .bar = currentBar,
        .ui = currentUi,
        .panes_area = panesArea,
    });
}

fn currentTabs(context: *anyopaque) ?*tabs.Tabs {
    return &@as(*App, @ptrCast(@alignCast(context))).tabs;
}
fn currentBar(context: *anyopaque) *tabs.Bar {
    return &@as(*App, @ptrCast(@alignCast(context))).bar;
}
fn currentUi(context: *anyopaque) *ui.Ui {
    return &@as(*App, @ptrCast(@alignCast(context))).u;
}
fn panesArea(context: *anyopaque) gfx.Rect {
    return @as(*App, @ptrCast(@alignCast(context))).panes_area;
}

test {
    @import("win32").refAllDeep(@This());
}
