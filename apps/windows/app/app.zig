//! The app: everything one window holds, wired together, and the frame
//! that draws it. Features are reached through their entry points only.

const std = @import("std");
const w = @import("win32");
const gfx = @import("gfx");
const ui = @import("ui");
const icons = @import("icons");
const strings = @import("strings");
const palette = @import("command-palette");
const shortcuts = @import("shortcuts");
const themes = @import("themes");
const settings = @import("settings");
const terminal = @import("terminal");
const tabs = @import("tabs");
const status_bar = @import("status-bar");
const power_mod = @import("power");
const explorer = @import("explorer");
const search = @import("search");
const sidebar = @import("sidebar.zig");
const spaces = @import("spaces");
const markdown = @import("markdown");
const source_control = @import("source-control");
const viewers = @import("viewers.zig");
const git_page = @import("git_page.zig");
const web = @import("web.zig");
const webview = @import("webview");
const window_mod = @import("window.zig");
const chrome = @import("chrome.zig");
const wiring = @import("wiring.zig");
const app_commands = @import("app_commands.zig");

const c = w.c;

pub const App = struct {
    gpa: std.mem.Allocator,
    window: window_mod.Window = .{},
    input: ui.Input = .{},
    u: ui.Ui = undefined,
    device: gfx.Device = undefined,
    surface: gfx.Surface = undefined,
    fonts: gfx.Fonts = undefined,
    painter: gfx.Painter = undefined,
    registry: palette.Registry = undefined,
    commands: palette.Commands = undefined,
    palette: palette.Palette = undefined,
    shortcuts: shortcuts.Shortcuts = undefined,
    themes: themes.Store = undefined,
    settings: settings.Store = undefined,
    term_font: terminal.SharedFont = undefined,
    /// The tabs of the space on screen (spaces.current()).
    tabs: *tabs.Tabs = undefined,
    spaces: spaces.Spaces = undefined,
    /// The window is closing: an empty space ends the window, not the space.
    closing_window: bool = false,
    /// A space emptied itself during a frame; removed after it.
    remove_space: bool = false,
    /// Closing the window with programs or unsaved files in any space asks once.
    quit_question: ?struct { unsaved: bool } = null,
    /// space.rename's field.
    space_rename: ?ui.TextBuffer = null,
    space_rename_scroll: ui.text_field.Scroll = .{},
    /// When the spaces are saved next (0: nothing to save).
    save_due_ms: i64 = 0,
    bar: tabs.Bar = .{},
    layout: tabs.Layout = .{},
    status: status_bar.StatusBar = .{},
    explorer: explorer.Explorer = undefined,
    search: search.Search = undefined,
    sidebar: sidebar.Sidebar = .{},
    markdown: markdown.Markdown = undefined,
    git: *source_control.SourceControl = undefined,
    /// Opens asked for while the frame drew, done after it (viewers.zig).
    deferred: std.ArrayList(viewers.Deferred) = .empty,
    /// The web panes' WebView2, made when the first one opens (web.zig).
    web_env: ?*webview.Environment = null,
    /// "Abrir no preview" for a terminal's local server, and those offered.
    offer: web.Offer = .{},
    offered: std.ArrayList([]u8) = .empty,
    /// Several items to the Recycle Bin wait for the user's answer.
    pending_trash: usize = 0,
    plus_menu: ui.menu.Menu = .{},
    /// Keep-awake (docs/spec/power.md) and the coffee's menu in the title bar.
    power: power_mod.Power = undefined,
    /// The title bar's buttons and tabs, last frame: not the caption.
    holes: std.ArrayList(gfx.Rect) = .empty,
    max_button: gfx.Rect = .{},
    title_h: f32 = 38,
    panes_area: gfx.Rect = .{},
    /// A paste of several lines waiting for the user's answer.
    pending_paste: ?terminal.paste.Plan = null,
    home: ?[]u8 = null,
    /// The environment new terminals open in: null is Windows ("Local"),
    /// else a WSL distribution (workspace.environment, Windows only).
    environment: ?[]u8 = null,
    next_view: u32 = 1,
    label_buf: [48]u8 = undefined,

    pub fn create(gpa: std.mem.Allocator) !*App {
        const self = try gpa.create(App);
        self.* = .{ .gpa = gpa };
        try self.init();
        return self;
    }

    fn init(self: *App) !void {
        const gpa = self.gpa;
        _ = c.CoInitializeEx(null, c.COINIT_APARTMENTTHREADED);
        self.home = homeFolder(gpa);
        self.settings = try settings.Store.init(gpa);
        // Before any text is made: every view reads its texts once (ADR 0015).
        strings.language = strings.Language.parse(self.settings.current.general.language);
        // The core's few texts too (a git message, the name of a pasted copy).
        @import("cadex").cadex_set_language(if (strings.language == .pt) "pt" else "en");
        self.themes = themes.Store.init(gpa);
        self.registry = .{ .gpa = gpa };
        self.shortcuts = shortcuts.Shortcuts.init(gpa, &self.registry);
        app_commands.translateOpeners();
        self.commands = .{
            .registry = &self.registry,
            .pins = &app_commands.openers,
            .shortcut_label = shortcuts.Shortcuts.label,
            .shortcut_context = &self.shortcuts,
            .section_icons = app_commands.section_icons,
            .recent_icon = icons.phosphor.arrow_counter_clockwise,
        };
        self.palette = palette.Palette.init(gpa, self.commands.source(icons.phosphor.command));

        self.device = try gfx.Device.create();
        self.fonts = try gfx.Fonts.init(gpa, self.device.dwrite, &.{ icons.font_bytes, icons.fill_font_bytes });
        self.term_font = .{ .gpa = gpa, .factory = self.device.dwrite };
        try self.window.create(gpa, &self.input, wiring.delegate(self));
        const size = self.window.size();
        self.surface = try gfx.Surface.create(&self.device, self.window.hwnd, @intFromFloat(size.x), @intFromFloat(size.y));
        self.painter = try gfx.Painter.init(self.surface.context, self.device.dwrite, &self.fonts);
        self.u = .{ .gpa = gpa, .painter = &self.painter, .style = .{}, .input = &self.input, .hwnd = self.window.hwnd };

        self.spaces = .{ .gpa = gpa, .host = wiring.spacesHost(self) };
        self.explorer = explorer.Explorer.init(gpa, wiring.explorerHost(self));
        self.search = .{ .gpa = gpa, .host = wiring.searchHost(self) };
        self.markdown = markdown.Markdown.init(gpa, viewers.markdownHost(self));
        try git_page.create(self);
        app_commands.register(self);
        @import("environments.zig").register(self);
        self.explorer.register(&self.registry, wiring.explorerWiring(self));
        self.search.register(&self.registry);
        self.spaces.register(&self.registry);
        viewers.register(self);
        web.register(self);
        git_page.register(self);
        self.power = .{ .host = wiring.powerHost(self), .keep_display_on = self.settings.current.power.keep_display_on };
        power_mod.commands.register(&self.registry, &self.power);
        @import("theme_commands.zig").register(self);
        self.palette.addPrefix(.{ .char = '/', .label = strings.t("files", "arquivos"), .source = self.search.filesSource() });
        self.palette.addPrefix(.{ .char = '#', .label = strings.t("text", "texto"), .source = self.search.contentSource() });
        self.palette.addPrefix(.{ .char = '@', .label = strings.t("tabs and spaces", "abas e spaces"), .source = @import("places_source.zig").source(self) });
        wiring.applySettings(self);
        // On at launch in the settings' mode, if they say so.
        if (self.settings.current.power.on_at_launch) self.power.set(power_mod.Mode.parse(self.settings.current.power.mode));
        terminal.paste.cleanOld(gpa);
    }

    /// Opens the first tab (in `folder`, or the user's folder) and shows the window.
    pub fn start(self: *App, folder: ?[]const u8, background: bool) void {
        const restored = self.spaces.restore();
        if (!restored) _ = self.spaces.add(null);
        self.tabs = self.spaces.current();
        // Without a folder on the command line, the workspace of last time.
        const workspace = folder orelse self.spaces.saved_folder orelse self.home;
        if (workspace) |f| sidebar.setWorkspace(self, f);
        self.explorer.launched_with_folder = folder != null;
        if (!restored or folder != null) self.tabs.newTab(folder orelse self.home);
        self.window.show(background);
        self.window.run();
    }

    // ---- The frame ----

    pub fn frame(self: *App) void {
        const size = self.window.size();
        self.surface.resize(@intFromFloat(size.x), @intFromFloat(size.y)) catch {};
        const u = &self.u;
        u.size = size;
        u.style = themes.style(self.themes.current, self.window.scale());
        u.beginFrame(@intCast(c.GetTickCount64()));
        self.surface.begin();
        const vibrancy = self.settings.current.appearance.vibrancy;
        self.painter.clear(if (vibrancy) gfx.Color.transparent else u.style.chrome);

        var area: gfx.Rect = .{ .w = size.x, .h = size.y };
        self.title_h = u.px(38);
        const title = area.takeTop(self.title_h);
        const status = area.takeBottom(u.px(26));
        const gap = u.px(6);
        var body = area.inset(gap, 0);
        self.holes.clearRetainingCapacity();
        chrome.titleBar(self, title);
        sidebar.followTerminal(self);
        if (self.sidebar.visible) {
            const side = body.takeLeft(u.px(sidebar.width_dips));
            _ = body.takeLeft(gap);
            sidebar.draw(self, side);
        }
        self.drawBody(body);
        self.drawStatus(status);
        git_page.frame(self);
        self.drawOverlays();

        u.endFrame();
        if (self.save_due_ms != 0) {
            const now: i64 = @intCast(c.GetTickCount64());
            if (now >= self.save_due_ms) {
                self.save_due_ms = 0;
                self.spaces.save();
            } else self.window.redrawIn(@intCast(self.save_due_ms - now));
        }
        if (self.remove_space) {
            self.remove_space = false;
            self.spaces.removeActive();
            self.tabs = self.spaces.current();
        }
        self.surface.end() catch |err| std.log.warn("o quadro não foi mostrado: {s}", .{@errorName(err)});
        web.endFrame(self);
        window_mod.Window.setCursor(u.cursor);
        if (u.ime_caret) |caret| self.window.placeIme(caret);
        if (u.wants_frame_in_ms) |ms| self.window.redrawIn(ms);
        if (self.palette.takePending()) |p| {
            defer self.gpa.free(p.id);
            p.source.choose(p.source.context, p.id, p.how);
            self.window.redraw();
        }
        viewers.runDeferred(self);
    }

    fn drawBody(self: *App, body: gfx.Rect) void {
        const u = &self.u;
        const radius = u.px(8);
        u.painter.fillRounded(body, radius, u.style.panel_border);
        const inner = body.inset(1, 1);
        u.painter.fillRounded(inner, radius, u.style.panel);
        self.panes_area = inner.inset(u.px(2), u.px(2));
        u.painter.pushClip(self.panes_area);
        defer u.painter.popClip();
        const s = self.settings.current;
        const font = self.term_font.get(s.terminal.font_family, @floatCast(s.terminal.font_size), self.window.scale());
        self.layout.draw(u, self.tabs, font, self.panes_area);
        self.dropFiles();
    }

    fn drawStatus(self: *App, area: gfx.Rect) void {
        var arena: std.heap.ArenaAllocator = .init(self.gpa);
        defer arena.deinit();
        const view = self.tabs.focusedTerminal();
        const folder = self.tabs.currentFolder(arena.allocator());
        const busy = if (view) |v| v.session.hasForegroundProcess() else true;
        var converted: [2048]u8 = undefined;
        const shown = if (folder) |f| (if (view) |v| @import("environments.zig").windowsFolder(v, f, &converted) else f) else null;
        const result = self.status.draw(&self.u, area, shown, self.home, @import("environments.zig").label(view), busy);
        if (result.go_to) |dir| if (view) |v| if (!busy) {
            const quoted = terminal.paste.quotePaths(self.gpa, &.{dir}) orelse return;
            defer self.gpa.free(quoted);
            const line = std.fmt.allocPrint(self.gpa, "cd {s}\r", .{quoted}) catch return;
            defer self.gpa.free(line);
            v.session.write(line);
        };
    }


    fn drawOverlays(self: *App) void {
        const u = &self.u;
        if (ui.menu.show(u, &self.plus_menu, ui.id("plus.menu", 0), &app_commands.plus_items)) |i| {
            _ = self.registry.run(app_commands.openers[i].id);
        }

        web.drawOffer(self);
        @import("settings_page.zig").draw(self);
        self.palette.draw(u);
        // The lists of every theme live only while they are on screen.
        @import("theme_commands.zig").releaseWhenClosed(self);
        @import("themes_page.zig").releaseWhenHidden(self);
        @import("space_ui.zig").draw(self);
        if (self.tabs.question) |q| {
            const buttons: []const []const u8 = if (q.unsaved) &.{ strings.t("Save", "Salvar"), strings.t("Discard", "Descartar"), strings.t("Cancel", "Cancelar") } else &.{ strings.t("Close", "Fechar"), strings.t("Cancel", "Cancelar") };
            if (ui.menu.ask(u, .{ .title = q.title, .message = q.message, .buttons = buttons })) |choice| self.tabs.answer(choice);
        }
        if (self.pending_trash > 0) {
            var buf: [64]u8 = undefined;
            const title = std.fmt.bufPrint(&buf, "{s} {d} {s}", .{ strings.t("Move", "Mover"), self.pending_trash, strings.t("items to the Trash?", "itens para a Lixeira?") }) catch strings.t("Move to the Trash?", "Mover para a Lixeira?");
            if (ui.menu.ask(u, .{ .title = title, .buttons = &.{ strings.t("Move to Trash", "Mover para a Lixeira"), strings.t("Cancel", "Cancelar") } })) |choice| {
                if (choice == 0) explorer.actions.trash(&self.explorer);
                self.pending_trash = 0;
            }
        }
        if (self.pending_paste) |plan| {
            if (ui.menu.ask(u, .{ .title = strings.t("Paste several lines?", "Colar várias linhas?"), .message = strings.t("The text may run commands as soon as it is pasted.", "O texto pode rodar comandos assim que for colado."), .buttons = &.{ strings.t("Paste", "Colar"), strings.t("Cancel", "Cancelar") } })) |choice| {
                if (choice == 0) if (self.tabs.focusedTerminal()) |v| terminal.paste.send(v.session, plan);
                plan.deinit(self.gpa);
                self.pending_paste = null;
            }
        }
    }

    fn dropFiles(self: *App) void {
        if (self.input.dropped.items.len == 0) return;
        const view = self.tabs.focusedTerminal() orelse return;
        const quoted = terminal.paste.quotePaths(self.gpa, self.input.dropped.items) orelse return;
        defer self.gpa.free(quoted);
        view.session.write(quoted);
    }

    /// Whether keys and text go straight to the focused terminal now.
    pub fn terminalHasKeys(self: *App) ?*terminal.View {
        if (self.palette.isOpen() or self.tabs.question != null or self.pending_paste != null or self.pending_trash > 0) return null;
        if (self.quit_question != null or self.space_rename != null or self.git.question != null) return null;
        if (@import("settings_page.zig").isOpen()) return null;
        if (self.plus_menu.owner != ui.context.none or self.status.menu.owner != ui.context.none) return null;
        if (self.bar.renaming != null) return null;
        const view = self.tabs.focusedTerminal() orelse return null;
        if (self.u.focus != view.id and self.u.focus != ui.context.none) return null;
        return view;
    }

    /// The keys of a command as shown ("Ctrl+Shift+K"), or "Buscar" without any.
    pub fn shortcutLabelOrEmpty(self: *App, id: []const u8) []const u8 {
        const combo = self.shortcuts.keymap.comboFor(id) orelse return strings.t("Search", "Buscar");
        return combo.label(&self.label_buf);
    }

    pub fn nextViewId(self: *App) ui.Id {
        defer self.next_view += 1;
        return ui.child(ui.id("terminal.view", 0), self.next_view);
    }
};

fn homeFolder(gpa: std.mem.Allocator) ?[]u8 {
    var buf: [1536]u8 = undefined;
    var wide: [512]u16 = undefined;
    const n = c.GetEnvironmentVariableW(w.L("USERPROFILE"), &wide, wide.len);
    if (n == 0 or n >= wide.len) return null;
    const len = std.unicode.wtf16LeToWtf8(&buf, wide[0..n]);
    return gpa.dupe(u8, buf[0..len]) catch null;
}

test {
    @import("win32").refAllDeep(@This());
}
