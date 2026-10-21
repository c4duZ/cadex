//! The General and Terminal pages of the settings, in the Mac's
//! sections (apps/macos/features/settings/): General has the language, the
//! files, the file tree and keep awake; Terminal has the shell and the
//! questions (in General before 2026-10-20), the text and the cursor, the
//! history. Every row says what it changes, in English or Portuguese (ADR
//! 0015). The pieces (heading, row, choice) are in settings_page.zig.

const std = @import("std");
const gfx = @import("gfx");
const ui = @import("ui");
const strings = @import("strings");
const settings = @import("settings");
const App = @import("app.zig").App;
const page = @import("settings_page.zig");
const relaunch = @import("relaunch.zig");

const t = strings.t;

var shell_text: ui.TextBuffer = .{};
var shell_scroll: ui.text_field.Scroll = .{};
var font_text: ui.TextBuffer = .{};
var font_scroll: ui.text_field.Scroll = .{};

/// The text fields start with the saved values each time the page opens.
pub fn prepare(app: *App) void {
    const s = app.settings.current;
    shell_text.set(app.gpa, s.general.shell) catch {};
    font_text.set(app.gpa, s.terminal.font_family) catch {};
}

pub fn general(app: *App, area_in: gfx.Rect) void {
    const u = &app.u;
    var area = area_in;
    var s = app.settings.current;
    page.heading(u, &area, t("Language", "Idioma"));
    if (page.choice(u, page.row(u, &area, t("Language", "Idioma"), t("Cadex reopens in the new language, with your tabs and spaces.", "O Cadex reabre no idioma novo, com as suas abas e spaces.")), "language", s.general.language, &.{ .{ "en", "English" }, .{ "pt", "Português" } })) |v| {
        s.general.language = v;
        page.commit(app, s);
    }
    // The language counts at launch: offer to reopen while it differs.
    if (strings.Language.parse(s.general.language) != strings.language) {
        const r = page.row(u, &area, t("Reopen to use the new language", "Reabrir para usar o idioma novo"), null);
        if (ui.widgets.button(u, ui.id("settings.relaunch", 0), r.inset(0, u.px(6)), t("Reopen now", "Reabrir agora"), .{ .primary = true })) relaunch.request(app);
    }

    page.heading(u, &area, t("Files", "Arquivos"));
    if (page.choice(u, page.row(u, &area, t("Open files", "Abrir arquivos"), t("Next to the focused pane, or in a new tab.", "Ao lado do painel com foco, ou numa aba nova.")), "openFiles", s.general.open_files, &.{ .{ "beside", t("Beside", "Ao lado") }, .{ "tab", t("New tab", "Em nova aba") } })) |v| {
        s.general.open_files = v;
        page.commit(app, s);
    }
    if (page.choice(u, page.row(u, &area, t("Open Markdown as", "Abrir Markdown como"), t("The button in the tab's corner switches at any time.", "O botão no canto da aba troca a qualquer hora.")), "openAs", s.markdown.open_as, &.{ .{ "source", t("Source", "Código") }, .{ "rendered", t("Rendered", "Renderizado") } })) |v| {
        s.markdown.open_as = v;
        page.commit(app, s);
    }

    page.heading(u, &area, t("File tree", "Árvore de arquivos"));
    if (ui.widgets.toggle(u, ui.id("settings.follow", 0), page.row(u, &area, t("Follow the terminal", "Seguir o terminal"), t("A cd in the focused terminal takes the tree to that project.", "Um cd no terminal com foco leva a árvore àquele projeto.")), s.explorer.follow_terminal)) |v| {
        s.explorer.follow_terminal = v;
        page.commit(app, s);
    }
    if (ui.widgets.toggle(u, ui.id("settings.hidden", 0), page.row(u, &area, t("Show hidden files", "Mostrar arquivos ocultos"), t("Names that start with a dot, dimmed.", "Nomes que começam com ponto, apagados.")), s.explorer.show_hidden)) |v| {
        s.explorer.show_hidden = v;
        page.commit(app, s);
    }

    keepAwake(app, &area, &s);
}

/// Keep awake as a section of General, as on the Mac (docs/spec/power.md).
fn keepAwake(app: *App, area: *gfx.Rect, s: *settings.Settings) void {
    const u = &app.u;
    page.heading(u, area, t("Keep awake", "Manter acordado"));
    if (page.choice(u, page.row(u, area, t("Mode", "Modo"), t("Always, or only while a terminal runs a program.", "Sempre, ou só enquanto um terminal roda um programa.")), "keepAwake", s.power.mode, &.{ .{ "always", t("Always", "Sempre") }, .{ "running", t("While a program runs", "Com programa rodando") } })) |v| {
        s.power.mode = v;
        page.commit(app, s.*);
    }
    if (ui.widgets.toggle(u, ui.id("settings.keepDisplayOn", 0), page.row(u, area, t("Keep the screen on", "Manter a tela acesa"), t("Off, only the screen turns off; the computer keeps running.", "Desligado, só a tela apaga; o computador segue rodando.")), s.power.keep_display_on)) |v| {
        s.power.keep_display_on = v;
        page.commit(app, s.*);
    }
    if (ui.widgets.toggle(u, ui.id("settings.powerOnAtLaunch", 0), page.row(u, area, t("Turn on when Cadex opens", "Ligar ao abrir o Cadex"), t("In the mode above.", "No modo acima.")), s.power.on_at_launch)) |v| {
        s.power.on_at_launch = v;
        page.commit(app, s.*);
    }
    page.note(u, area, t("The coffee in the title bar and Ctrl+Shift+Alt+A turn it on and off. A closed lid follows Windows' own setting.", "O café na barra de título e o Ctrl+Shift+Alt+A ligam e desligam. A tampa fechada segue a opção do próprio Windows."));
}

pub fn terminal(app: *App, area_in: gfx.Rect) void {
    const u = &app.u;
    var area = area_in;
    var s = app.settings.current;
    page.heading(u, &area, "Shell");
    {
        const r = page.row(u, &area, "Shell", t("The program each new terminal runs; empty uses the default.", "O programa que cada terminal novo roda; vazio usa o padrão."));
        const res = ui.text_field.textField(u, ui.id("settings.shell", 0), r.inset(0, u.px(6)), &shell_text, &shell_scroll, .{ .placeholder = "pwsh, powershell.exe, cmd.exe" });
        if (res.submitted) {
            s.general.shell = shell_text.text();
            page.commit(app, s);
        }
    }
    if (ui.widgets.toggle(u, ui.id("settings.confirmClose", 0), page.row(u, &area, t("Ask before closing a running program", "Perguntar antes de fechar um programa rodando"), t("A pane, tab or window with a server or an agent running.", "Um painel, aba ou janela com um servidor ou agente rodando.")), s.general.confirm_close)) |v| {
        s.general.confirm_close = v;
        page.commit(app, s);
    }
    if (ui.widgets.toggle(u, ui.id("settings.confirmPaste", 0), page.row(u, &area, t("Ask before pasting several lines", "Perguntar antes de colar várias linhas"), t("Each line could run as a command.", "Cada linha poderia rodar como um comando.")), s.general.confirm_multiline_paste)) |v| {
        s.general.confirm_multiline_paste = v;
        page.commit(app, s);
    }

    page.heading(u, &area, t("Text and cursor", "Texto e cursor"));
    {
        const r = page.row(u, &area, t("Font", "Fonte"), null);
        const res = ui.text_field.textField(u, ui.id("settings.font", 0), r.inset(0, u.px(6)), &font_text, &font_scroll, .{ .placeholder = "Cascadia Mono" });
        if (res.submitted) {
            s.terminal.font_family = font_text.text();
            page.commit(app, s);
        }
    }
    if (page.stepper(u, page.row(u, &area, t("Size", "Tamanho"), null), 0, s.terminal.font_size, 1, " pt")) |v| {
        s.terminal.font_size = std.math.clamp(v, settings.model.font_sizes[0], settings.model.font_sizes[1]);
        page.commit(app, s);
    }
    if (page.choice(u, page.row(u, &area, t("Cursor", "Cursor"), null), "cursor", s.terminal.cursor, &.{ .{ "bar", t("Bar", "Barra") }, .{ "block", t("Block", "Bloco") }, .{ "underline", t("Underline", "Sublinhado") } })) |v| {
        s.terminal.cursor = v;
        page.commit(app, s);
    }
    if (ui.widgets.toggle(u, ui.id("settings.blink", 0), page.row(u, &area, t("Blinking cursor", "Cursor piscando"), null), s.terminal.cursor_blink)) |v| {
        s.terminal.cursor_blink = v;
        page.commit(app, s);
    }

    page.heading(u, &area, t("History and selection", "Histórico e seleção"));
    if (page.stepper(u, page.row(u, &area, t("History lines", "Linhas de histórico"), t("How far back you can scroll; new terminals.", "Até onde dá para rolar; terminais novos.")), 1, @floatFromInt(s.terminal.history_lines), 5000, "")) |v| {
        s.terminal.history_lines = @intFromFloat(std.math.clamp(v, 100, 100_000));
        page.commit(app, s);
    }
    if (ui.widgets.toggle(u, ui.id("settings.copySelect", 0), page.row(u, &area, t("Copy on select", "Copiar ao selecionar"), t("Off, only Ctrl+Shift+C copies.", "Desligado, só o Ctrl+Shift+C copia.")), s.terminal.copy_on_select)) |v| {
        s.terminal.copy_on_select = v;
        page.commit(app, s);
    }
}

test {
    @import("win32").refAllDeep(@This());
}
