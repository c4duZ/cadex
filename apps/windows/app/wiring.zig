//! How the app answers the window (keys, text, terminal notices, closing)
//! and the tabs (making terminals), and how the settings reach every
//! feature when they change.

const std = @import("std");
const w = @import("win32");
const ui = @import("ui");
const gfx = @import("gfx");
const cadex = @import("cadex");
const themes = @import("themes");
const terminal = @import("terminal");
const tabs = @import("tabs");
const shortcuts = @import("shortcuts");
const explorer = @import("explorer");
const search = @import("search");
const palette = @import("command-palette");
const strings = @import("strings");
const opener = @import("opener.zig");
const spaces = @import("spaces");
const window_mod = @import("window.zig");
const looks = @import("looks.zig");
const App = @import("app.zig").App;

const c = w.c;

fn of(context: *anyopaque) *App {
    return @ptrCast(@alignCast(context));
}

pub fn delegate(app: *App) window_mod.Delegate {
    return .{
        .context = app,
        .frame = frame,
        .key = key,
        .text = text,
        .terminal = terminalNotice,
        .close = close,
        .poll = poll,
        .wake = wakeDrain,
        .appearance = appearance,
        .caption_holes = holes,
        .maximize_button = maximizeButton,
        .title_height = titleHeight,
        .moved = @import("web.zig").moved,
    };
}

fn frame(context: *anyopaque) void {
    of(context).frame();
}

/// Every key press, before TranslateMessage: shortcuts first (the palette
/// opens even with the terminal focused), then the focused terminal.
fn key(context: *anyopaque, vk: u16, scan: u16, mods: ui.Mods) bool {
    const app = of(context);
    if (vk == c.VK_SHIFT or vk == c.VK_CONTROL or vk == c.VK_MENU) return false;
    if (app.shortcuts.handle(.{ .vk = vk, .mods = mods })) return true;
    const view = app.terminalHasKeys() orelse return false;
    return view.keyDown(&app.u, vk, scan, mods);
}

fn text(context: *anyopaque, utf8: []const u8) void {
    const app = of(context);
    if (app.terminalHasKeys()) |view| return view.typeText(utf8);
    app.input.text.appendSlice(app.gpa, utf8) catch {};
}

fn terminalNotice(context: *anyopaque, lparam: c.LPARAM, wparam: c.WPARAM) void {
    const app = of(context);
    const session: *terminal.Session = @ptrFromInt(@as(usize, @bitCast(lparam)));
    // A notice queued before its pane closed finds nothing: ignored. The
    // shells of hidden spaces keep running, so every space is searched.
    const found = findSession(app, session) orelse return;
    const event: terminal.Event = @enumFromInt(@as(u8, @intCast(wparam)));
    switch (event) {
        .output, .title => {},
        .local_url => @import("web.zig").localServer(app, session),
        .bell => found.found.view.bell(@intCast(c.GetTickCount64())),
        .exit => {
            const code = session.exitCode() orelse 0;
            // An error stays on screen with its code (docs/spec/terminal.md).
            if (code == 0) found.owner.closePaneNow(found.found.tab.id, found.found.pane) else found.found.view.exited = code;
        },
    }
    app.window.redraw();
}

const Found = struct { owner: *tabs.Tabs, found: @typeInfo(@typeInfo(@TypeOf(tabs.Tabs.find)).@"fn".return_type.?).optional.child };

fn findSession(app: *App, session: *terminal.Session) ?Found {
    for (app.spaces.list.items) |s| if (s.tabs.find(session)) |f| return .{ .owner = s.tabs, .found = f };
    return null;
}

/// The close button and Alt+F4: one question for every space (programs
/// running, unsaved files), then the spaces are saved and the window goes.
fn close(context: *anyopaque) bool {
    const app = of(context);
    if (app.closing_window) return true;
    var unsaved: usize = 0;
    var running: usize = 0;
    for (app.spaces.list.items) |s| s.tabs.tally(.all, &unsaved, &running);
    if (unsaved > 0 or (running > 0 and app.settings.current.general.confirm_close)) {
        app.quit_question = .{ .unsaved = unsaved > 0 };
        app.window.redraw();
        return false;
    }
    quitNow(app);
    return false;
}

/// After the question (or with nothing to ask): save the spaces and go.
pub fn quitNow(app: *App) void {
    app.spaces.save();
    app.closing_window = true;
    _ = c.DestroyWindow(app.window.hwnd);
}

fn wakeDrain(context: *anyopaque) void {
    _ = of(context).explorer.drain();
}

/// From any thread: the window drains the workers' news on its own thread.
fn wake(context: *anyopaque) void {
    _ = c.PostMessageW(of(context).window.hwnd, window_mod.WM_APP_WAKE, 0, 0);
}

fn poll(context: *anyopaque) void {
    const app = of(context);
    // Keep-awake's "com programa rodando" looks at the terminals each second.
    app.power.check(false);
    if (app.settings.poll()) {
        applySettings(app);
        app.window.redraw();
    }
}

/// What keep-awake needs: a program running in any space, and a redraw for
/// the title bar's coffee.
pub fn powerHost(app: *App) @import("power").Host {
    return .{ .context = app, .any_running = anyRunning, .changed = powerChanged };
}

fn anyRunning(context: *anyopaque) bool {
    const app = of(context);
    var unsaved: usize = 0;
    var running: usize = 0;
    for (app.spaces.list.items) |s| s.tabs.tally(.all, &unsaved, &running);
    return running > 0;
}

fn powerChanged(context: *anyopaque) void {
    of(context).window.redraw();
}

fn appearance(context: *anyopaque) void {
    const app = of(context);
    if (app.themes.refresh()) applyTheme(app);
}

fn holes(context: *anyopaque) []const gfx.Rect {
    return of(context).holes.items;
}

fn maximizeButton(context: *anyopaque) gfx.Rect {
    return of(context).max_button;
}

fn titleHeight(context: *anyopaque) f32 {
    return of(context).title_h;
}

// ---- The tabs' host ----

pub fn host(app: *App) tabs.Host {
    return .{
        .context = app,
        .make_terminal = makeTerminal,
        .home = home,
        .confirm_close = confirmClose,
        .on_empty = onEmpty,
        .on_change = onChange,
    };
}

fn cursorShape(name: []const u8) u8 {
    if (std.mem.eql(u8, name, "block")) return cadex.CADEX_CURSOR_BLOCK;
    if (std.mem.eql(u8, name, "underline")) return cadex.CADEX_CURSOR_UNDERLINE;
    return cadex.CADEX_CURSOR_BAR;
}

fn makeTerminal(context: *anyopaque, cwd: ?[]const u8) ?*terminal.View {
    const app = of(context);
    const s = app.settings.current;
    const prefs: terminal.Preferences = .{
        .shell = s.general.shell,
        .history_lines = s.terminal.history_lines,
        .cursor = cursorShape(s.terminal.cursor),
        .cursor_blink = s.terminal.cursor_blink,
    };
    var shell_buf: [1024]u8 = undefined;
    var session_prefs = prefs;
    if (app.environment) |distro| if (s.general.shell.len == 0) {
        // The distro's shell, starting in the same folder (wsl.exe takes
        // a Windows path for --cd).
        session_prefs.shell = if (cwd) |d|
            std.fmt.bufPrint(&shell_buf, "wsl.exe -d {s} --cd \"{s}\"", .{ distro, d }) catch prefs.shell
        else
            std.fmt.bufPrint(&shell_buf, "wsl.exe -d {s} --cd ~", .{distro}) catch prefs.shell;
    };
    const session = terminal.Session.open(app.gpa, cwd, 80, 24, session_prefs, .{ .context = app, .post = post }) catch |err| {
        std.log.warn("o shell não abriu: {s}", .{@errorName(err)});
        return null;
    };
    session.setColors(themes.terminalColors(app.themes.current));
    const view = app.gpa.create(terminal.View) catch {
        session.close();
        return null;
    };
    view.* = terminal.View.init(app.gpa, session, app.nextViewId());
    view.selection_color = app.themes.current.terminal.selection;
    view.min_contrast = looks.minContrast(app);
    view.copy_on_select = s.terminal.copy_on_select;
    view.hooks = .{ .context = app, .open_link = openLink };
    if (app.environment) |e| if (s.general.shell.len == 0) {
        view.environment = app.gpa.dupe(u8, e) catch null;
    };
    return view;
}

/// On the core's reader thread: only queue it for the window's thread.
fn post(context: *anyopaque, session: *terminal.Session, event: terminal.Event) void {
    const app = of(context);
    _ = c.PostMessageW(app.window.hwnd, window_mod.WM_APP_TERMINAL, @intFromEnum(event), @bitCast(@intFromPtr(session)));
}

/// Ctrl+click on a terminal link: a URL in the browser, a file in the Cadex.
fn openLink(context: ?*anyopaque, kind: u8, target: []const u8) void {
    const app = of(context.?);
    if (kind == cadex.CADEX_LINK_URL) return opener.systemOpen(app, target);
    opener.open(app, target, 0, .setting);
}

fn home(context: *anyopaque) ?[]const u8 {
    return of(context).home;
}

fn confirmClose(context: *anyopaque) bool {
    return of(context).settings.current.general.confirm_close;
}

/// The last tab of the space on screen closed: another space takes the
/// window; the only one closes it (docs/spec/spaces.md).
fn onEmpty(context: *anyopaque) void {
    const app = of(context);
    if (app.closing_window) return;
    if (app.spaces.list.items.len > 1) {
        // Inside a Tabs method: the space goes after the frame.
        app.remove_space = true;
        app.window.redraw();
        return;
    }
    quitNow(app);
}

fn onChange(context: *anyopaque) void {
    const app = of(context);
    app.save_due_ms = @as(i64, @intCast(c.GetTickCount64())) + 500;
    app.window.redraw();
}

// ---- Settings and theme ----

pub fn applySettings(app: *App) void {
    const s = app.settings.current;
    _ = app.themes.apply(looks.choice(s));
    looks.applyPanes(app);
    applyTheme(app);
    var prefs: std.ArrayList(shortcuts.Preference) = .empty;
    defer prefs.deinit(app.gpa);
    for (s.shortcuts) |sc| prefs.append(app.gpa, .{ .keys = sc.keys, .id = sc.id }) catch {};
    app.shortcuts.reload(app.gpa, prefs.items);
    app.explorer.setShowHidden(s.explorer.show_hidden);
    app.power.setDisplay(s.power.keep_display_on);
    app.power.default_mode = @import("power").Mode.parse(s.power.mode);
    if (app.explorer.root()) |r| app.search.setRoot(r, s.explorer.show_hidden);
    eachView(app, struct {
        fn apply(a: *App, v: *terminal.View) void {
            const cur = a.settings.current.terminal;
            v.copy_on_select = cur.copy_on_select;
            v.session.setCursor(cursorShape(cur.cursor), cur.cursor_blink);
        }
    }.apply);
}

fn applyTheme(app: *App) void {
    app.window.setDark(app.themes.current.dark);
    @import("viewers.zig").applyTheme(app);
    eachView(app, struct {
        fn apply(a: *App, v: *terminal.View) void {
            v.session.setColors(themes.terminalColors(a.themes.current));
            v.selection_color = a.themes.current.terminal.selection;
            v.min_contrast = looks.minContrast(a);
        }
    }.apply);
    app.window.redraw();
}

fn eachView(app: *App, comptime f: fn (*App, *terminal.View) void) void {
    for (app.spaces.list.items) |s| {
        var it = s.tabs.tabs.valueIterator();
        while (it.next()) |t| for (t.*.panes.values()) |p| switch (p) {
            .terminal => |v| f(app, v),
            .document => {},
        };
    }
}

// ---- Spaces ----

pub fn spacesHost(app: *App) spaces.Host {
    return .{
        .context = app,
        .make_tabs = makeTabs,
        .make_document = .{ .context = app, .make = makeDocument },
        .folder = workspaceFolder,
        .shown = spaceShown,
        .schedule_save = scheduleSave,
        .show_list = showList,
        .ask_name = askSpaceName,
    };
}

fn makeTabs(context: *anyopaque) ?*tabs.Tabs {
    const app = of(context);
    const t = app.gpa.create(tabs.Tabs) catch return null;
    t.* = tabs.Tabs.init(app.gpa, host(app));
    return t;
}

/// A saved document again (viewers.makeSaved).
fn makeDocument(context: *anyopaque, identity: []const u8) ?tabs.Document {
    return @import("viewers.zig").makeSaved(of(context), identity);
}

fn workspaceFolder(context: *anyopaque) ?[]const u8 {
    const app = of(context);
    return app.explorer.root() orelse app.home;
}

fn spaceShown(context: *anyopaque) void {
    const app = of(context);
    app.tabs = app.spaces.current();
    app.u.focus = ui.context.none;
    app.window.redraw();
}

fn scheduleSave(context: *anyopaque) void {
    onChange(context);
}

fn askSpaceName(context: *anyopaque, current: []const u8) void {
    const app = of(context);
    var buffer: ui.TextBuffer = .{};
    buffer.set(app.gpa, current) catch return;
    buffer.selectAll();
    app.space_rename = buffer;
    app.u.focus = ui.id("space.rename", 0);
}

test {
    @import("win32").refAllDeep(@This());
}

// ---- Explorer and search ----

pub fn explorerHost(app: *App) explorer.Host {
    return .{
        .context = app,
        .open_file = openFromExplorer,
        .open_in_terminal = cdTerminal,
        .terminal_folder = terminalFolder,
        .git_mark = @import("git_page.zig").mark,
        .wake = wake,
        .folders_changed = foldersChanged,
    };
}

/// The watcher saw folders change: editors reload, git reads the status.
fn foldersChanged(context: *anyopaque, paths: []const []const u8) void {
    const app = of(context);
    @import("viewers.zig").diskChanged(app, paths);
    @import("git_page.zig").diskChanged(app, paths);
}

fn openFromExplorer(context: *anyopaque, path: []const u8, how: explorer.OpenHow) void {
    opener.open(of(context), path, 0, switch (how) {
        .setting => .setting,
        .beside => .beside,
        .tab => .tab,
    });
}

fn cdTerminal(context: *anyopaque, folder: []const u8) void {
    const app = of(context);
    const view = app.tabs.focusedTerminal() orelse return app.tabs.newTab(folder);
    if (view.session.hasForegroundProcess()) return app.tabs.newTab(folder);
    const quoted = terminal.paste.quotePaths(app.gpa, &.{folder}) orelse return;
    defer app.gpa.free(quoted);
    const line = std.fmt.allocPrint(app.gpa, "cd {s}\r", .{quoted}) catch return;
    defer app.gpa.free(line);
    view.session.write(line);
}

fn terminalFolder(context: *anyopaque, out: []u8) ?[]const u8 {
    const app = of(context);
    const view = app.tabs.focusedTerminal() orelse return null;
    const dir = view.session.workingDirectory() orelse return null;
    defer dir.free();
    if (dir.bytes.len > out.len) return null;
    @memcpy(out[0..dir.bytes.len], dir.bytes);
    return out[0..dir.bytes.len];
}

pub fn explorerWiring(app: *App) explorer.commands.Wiring {
    return .{ .context = app, .ui = uiOf, .show = showFiles, .toggle_hidden = toggleHidden, .confirm_trash = confirmTrash };
}

fn uiOf(context: *anyopaque) *ui.Ui {
    return &of(context).u;
}

fn showFiles(context: *anyopaque) void {
    const app = of(context);
    app.sidebar.visible = true;
    app.sidebar.page = .files;
    app.u.focus = app.explorer.focus_id;
}

fn toggleHidden(context: *anyopaque) void {
    const app = of(context);
    var s = app.settings.current;
    s.explorer.show_hidden = !s.explorer.show_hidden;
    app.settings.save(s);
    applySettings(app);
}

fn confirmTrash(context: *anyopaque, count: usize) void {
    of(context).pending_trash = count;
}

pub fn searchHost(app: *App) search.Host {
    return .{ .context = app, .open = openFromSearch, .wake = wake, .show = showList, .content_open = contentOpen };
}

fn openFromSearch(context: *anyopaque, path: []const u8, line: u32, how: palette.How) void {
    opener.open(of(context), path, line, switch (how) {
        .normal => .setting,
        .beside => .beside,
        .new_tab => .tab,
    });
}

fn showList(context: *anyopaque, source: palette.Source) void {
    const app = of(context);
    app.palette.toggle(&app.u, source);
}

fn contentOpen(context: *anyopaque) bool {
    const app = of(context);
    const opened = app.palette.opened orelse return false;
    return opened.context == @as(*anyopaque, @ptrCast(&app.search)) and std.mem.eql(u8, opened.placeholder, strings.t("Find text in files", "Buscar texto nos arquivos"));
}
