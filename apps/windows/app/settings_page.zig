//! The settings (Ctrl+Shift+, the Mac's ⌘,): one page over the window, the
//! Mac's sections (Geral, Terminal, Aparência, Atalhos). Every change is
//! saved to settings.json at once and counts everywhere, with no Save
//! button (docs/spec/settings.md).

const std = @import("std");
const gfx = @import("gfx");
const ui = @import("ui");
const w = @import("win32");
const icons = @import("icons");
const settings = @import("settings");
const themes = @import("themes");
const App = @import("app.zig").App;
const wiring = @import("wiring.zig");

const Section = enum { general, terminal, appearance, shortcuts };

var open = false;
var section: Section = .general;
var scroll: ui.list.Scroll = .{};
var shell_text: ui.TextBuffer = .{};
var shell_scroll: ui.text_field.Scroll = .{};
var font_text: ui.TextBuffer = .{};
var font_scroll: ui.text_field.Scroll = .{};

pub fn toggle(app: *App) void {
    open = !open;
    if (open) {
        const s = app.settings.current;
        shell_text.set(app.gpa, s.general.shell) catch {};
        font_text.set(app.gpa, s.terminal.font_family) catch {};
        app.u.focus = ui.id("settings.page", 0);
    } else app.u.focus = ui.context.none;
    app.window.redraw();
}

pub fn isOpen() bool {
    return open;
}

/// Saves `next` and applies it to every feature.
fn commit(app: *App, next: settings.Settings) void {
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
    const box_w = @min(u.px(760), u.size.x - u.px(40));
    const box_h = @min(u.px(560), u.size.y - u.px(60));
    const box: gfx.Rect = .{ .x = (u.size.x - box_w) / 2, .y = (u.size.y - box_h) / 2, .w = box_w, .h = box_h };
    u.painter.fillRounded(box.inset(-1, -1), u.px(12), u.style.panel_border);
    u.painter.fillRounded(box, u.px(12), u.style.panel);
    var inner = box.inset(u.px(16), u.px(14));
    var header = inner.takeTop(u.px(32));
    u.painter.text("Configurações", u.style.bold(), header.takeLeft(u.px(200)), u.style.text, .{});
    if (ui.widgets.iconButton(u, ui.id("settings.close", 0), header.takeRight(u.px(30)), icons.phosphor.x, .{ .icon_size = 14 })) toggle(app);
    _ = inner.takeTop(u.px(8));
    var nav = inner.takeLeft(u.px(160));
    _ = inner.takeLeft(u.px(16));
    const sections = [_]struct { Section, []const u8, u21 }{
        .{ .general, "Geral", icons.phosphor.gear_six },
        .{ .terminal, "Terminal", icons.phosphor.terminal_window },
        .{ .appearance, "Aparência", icons.phosphor.palette },
        .{ .shortcuts, "Atalhos", icons.phosphor.keyboard },
    };
    for (sections, 0..) |entry, i| {
        const r = nav.takeTop(u.px(32));
        if (ui.widgets.button(u, ui.child(ui.id("settings.nav", 0), i), r, entry[1], .{ .icon = entry[2], .selected = section == entry[0], .@"align" = .{} })) {
            section = entry[0];
            scroll = .{};
        }
        _ = nav.takeTop(u.px(2));
    }
    switch (section) {
        .general => general(app, inner),
        .terminal => terminalSection(app, inner),
        .appearance => appearance(app, inner),
        .shortcuts => shortcutsSection(app, inner),
    }
    if (u.key(w.c.VK_ESCAPE, .{})) toggle(app);
}

fn row(u: *ui.Ui, area: *gfx.Rect, title: []const u8) gfx.Rect {
    var r = area.takeTop(u.px(40));
    u.painter.text(title, u.style.ui(), r.takeLeft(r.w * 0.5), u.style.text, .{});
    return r;
}

/// A choice among a few values, as segments; the new one when clicked.
fn choice(u: *ui.Ui, r: gfx.Rect, name: []const u8, value: []const u8, options: []const [2][]const u8) ?[]const u8 {
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

fn general(app: *App, area_in: gfx.Rect) void {
    const u = &app.u;
    var area = area_in;
    var s = app.settings.current;
    {
        const r = row(u, &area, "Shell (vazio usa o padrão)");
        const res = ui.text_field.textField(u, ui.id("settings.shell", 0), r.inset(0, u.px(6)), &shell_text, &shell_scroll, .{ .placeholder = "pwsh, powershell.exe, cmd.exe" });
        if (res.submitted) {
            s.general.shell = shell_text.text();
            commit(app, s);
        }
    }
    if (ui.widgets.toggle(u, ui.id("settings.confirmClose", 0), row(u, &area, "Perguntar antes de fechar com programa rodando"), s.general.confirm_close)) |v| {
        s.general.confirm_close = v;
        commit(app, s);
    }
    if (ui.widgets.toggle(u, ui.id("settings.confirmPaste", 0), row(u, &area, "Perguntar antes de colar várias linhas"), s.general.confirm_multiline_paste)) |v| {
        s.general.confirm_multiline_paste = v;
        commit(app, s);
    }
    if (choice(u, row(u, &area, "Abrir arquivos"), "openFiles", s.general.open_files, &.{ .{ "beside", "Ao lado" }, .{ "tab", "Em nova aba" } })) |v| {
        s.general.open_files = v;
        commit(app, s);
    }
    if (choice(u, row(u, &area, "Notas Markdown abrem como"), "openAs", s.markdown.open_as, &.{ .{ "source", "Código" }, .{ "rendered", "Renderizada" } })) |v| {
        s.markdown.open_as = v;
        commit(app, s);
    }
    if (choice(u, row(u, &area, "Manter acordado ao abrir"), "keepAwake", s.power.keep_awake, &.{ .{ "off", "Não" }, .{ "always", "Sempre" }, .{ "running", "Com programa" } })) |v| {
        s.power.keep_awake = v;
        commit(app, s);
    }
    if (ui.widgets.toggle(u, ui.id("settings.keepDisplayOn", 0), row(u, &area, "Manter a tela acesa"), s.power.keep_display_on)) |v| {
        s.power.keep_display_on = v;
        commit(app, s);
    }
    if (ui.widgets.toggle(u, ui.id("settings.follow", 0), row(u, &area, "A árvore segue a pasta do terminal"), s.explorer.follow_terminal)) |v| {
        s.explorer.follow_terminal = v;
        commit(app, s);
    }
    if (ui.widgets.toggle(u, ui.id("settings.hidden", 0), row(u, &area, "Mostrar arquivos ocultos"), s.explorer.show_hidden)) |v| {
        s.explorer.show_hidden = v;
        commit(app, s);
    }
}

fn stepper(u: *ui.Ui, r: gfx.Rect, name: usize, value: f64, step: f64, unit: []const u8) ?f64 {
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

fn terminalSection(app: *App, area_in: gfx.Rect) void {
    const u = &app.u;
    var area = area_in;
    var s = app.settings.current;
    {
        const r = row(u, &area, "Fonte");
        const res = ui.text_field.textField(u, ui.id("settings.font", 0), r.inset(0, u.px(6)), &font_text, &font_scroll, .{ .placeholder = "Cascadia Mono" });
        if (res.submitted) {
            s.terminal.font_family = font_text.text();
            commit(app, s);
        }
    }
    if (stepper(u, row(u, &area, "Tamanho"), 0, s.terminal.font_size, 1, " pt")) |v| {
        s.terminal.font_size = std.math.clamp(v, settings.model.font_sizes[0], settings.model.font_sizes[1]);
        commit(app, s);
    }
    if (choice(u, row(u, &area, "Cursor"), "cursor", s.terminal.cursor, &.{ .{ "bar", "Barra" }, .{ "block", "Bloco" }, .{ "underline", "Sublinhado" } })) |v| {
        s.terminal.cursor = v;
        commit(app, s);
    }
    if (ui.widgets.toggle(u, ui.id("settings.blink", 0), row(u, &area, "Cursor piscando"), s.terminal.cursor_blink)) |v| {
        s.terminal.cursor_blink = v;
        commit(app, s);
    }
    if (stepper(u, row(u, &area, "Linhas de histórico"), 1, @floatFromInt(s.terminal.history_lines), 5000, "")) |v| {
        s.terminal.history_lines = @intFromFloat(std.math.clamp(v, 100, 100_000));
        commit(app, s);
    }
    if (ui.widgets.toggle(u, ui.id("settings.copySelect", 0), row(u, &area, "Copiar ao selecionar"), s.terminal.copy_on_select)) |v| {
        s.terminal.copy_on_select = v;
        commit(app, s);
    }
}

fn appearance(app: *App, area_in: gfx.Rect) void {
    const u = &app.u;
    var area = area_in;
    var s = app.settings.current;
    if (choice(u, row(u, &area, "Modo"), "mode", s.appearance.mode, &.{ .{ "system", "Sistema" }, .{ "dark", "Escuro" }, .{ "light", "Claro" } })) |v| {
        s.appearance.mode = v;
        commit(app, s);
    }
    if (ui.widgets.toggle(u, ui.id("settings.vibrancy", 0), row(u, &area, "Mica atrás da moldura"), s.appearance.vibrancy)) |v| {
        s.appearance.vibrancy = v;
        commit(app, s);
    }
    _ = area.takeTop(u.px(8));
    u.painter.text("Tema", u.style.bold(), area.takeTop(u.px(24)), u.style.text, .{});
    const families = app.themes.families();
    const view = ui.list.begin(u, ui.id("settings.themes", 0), area, families.len, u.px(32), &scroll);
    defer ui.list.end(u);
    for (view.first..view.last) |i| {
        const f = families[i];
        const r = view.row(i);
        if (ui.widgets.button(u, ui.child(ui.id("settings.theme", 0), i), r.inset(0, u.px(1)), f.name, .{ .selected = std.mem.eql(u8, f.id, s.appearance.theme), .@"align" = .{} })) {
            s.appearance.theme = f.id;
            commit(app, s);
        }
        // The family's colors as swatches on the right.
        const t = f.theme(app.themes.current.dark);
        var sw = r.inset(u.px(8), u.px(9));
        for ([_]u32{ t.terminal.background, t.interface.accent, t.terminal.ansi[1], t.terminal.ansi[2], t.terminal.ansi[4] }) |color| {
            const dot = sw.takeRight(u.px(14));
            u.painter.fillRounded(dot, u.px(3), gfx.Color.rgb(color));
            _ = sw.takeRight(u.px(4));
        }
    }
}

fn shortcutsSection(app: *App, area_in: gfx.Rect) void {
    const u = &app.u;
    var area = area_in;
    u.painter.text("Edite a seção \"shortcuts\" do settings.json (⌘ do Mac é Ctrl+Shift aqui).", u.style.small(), area.takeTop(u.px(24)), u.style.secondary_text, .{});
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

test {
    @import("win32").refAllDeep(@This());
}
