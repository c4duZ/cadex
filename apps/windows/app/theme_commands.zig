//! The theme commands (ADR 0005), the Mac's ids and titles
//! (apps/macos/features/settings/ThemeActions.swift): choosing a theme in
//! ⌘K (for both modes, or for dark or light only), the mode, importing a
//! theme file and opening the user's themes folder. The themes page's
//! buttons run the same code; the accent and high contrast are in
//! theme_looks.zig.

const std = @import("std");
const w = @import("win32");
const icons = @import("icons");
const strings = @import("strings");
const palette = @import("command-palette");
const themes = @import("themes");
const App = @import("app.zig").App;
const page = @import("settings_page.zig");
const looks = @import("looks.zig");

const t = strings.t;
const c = w.c;

var app_ref: *App = undefined;

pub fn register(app: *App) void {
    app_ref = app;
    const r = &app.registry;
    r.add(.{ .id = "theme.choose", .title = t("Choose Theme", "Escolher tema"), .keywords = &.{ "theme", "tema", "cores", "colors", "palette", "aparência", "appearance" }, .run = choose });
    r.add(.{ .id = "theme.choose-dark", .title = t("Choose Theme for Dark Mode", "Escolher tema do modo escuro"), .keywords = &.{ "theme", "tema", "dark", "escuro", "noite" }, .run = chooseDark });
    r.add(.{ .id = "theme.choose-light", .title = t("Choose Theme for Light Mode", "Escolher tema do modo claro"), .keywords = &.{ "theme", "tema", "light", "claro", "dia" }, .run = chooseLight });
    r.add(.{ .id = "theme.import", .title = t("Import Theme…", "Importar tema…"), .keywords = &.{ "theme", "tema", "itermcolors", "ghostty", "base16", "import" }, .run = importRun });
    r.add(.{ .id = "theme.open-folder", .title = t("Open Themes Folder", "Abrir a pasta de temas"), .keywords = &.{ "theme", "tema", "pasta", "folder", "explorer" }, .run = openFolderRun });
    r.add(.{ .id = "theme.mode-system", .title = t("Theme Follows the System", "Tema segue o sistema"), .keywords = &.{ "theme", "tema", "mode", "modo", "system", "sistema", "auto" }, .run = modeSystem, .available = notSystem });
    r.add(.{ .id = "theme.mode-dark", .title = t("Always Dark Theme", "Tema sempre escuro"), .keywords = &.{ "theme", "tema", "mode", "modo", "dark", "escuro" }, .run = modeDark, .available = notDark });
    r.add(.{ .id = "theme.mode-light", .title = t("Always Light Theme", "Tema sempre claro"), .keywords = &.{ "theme", "tema", "mode", "modo", "light", "claro" }, .run = modeLight, .available = notLight });
}

// ---- The mode ----

fn setMode(value: []const u8) void {
    var s = app_ref.settings.current;
    s.appearance.mode = value;
    page.commit(app_ref, s);
}

fn modeIsNot(value: []const u8) bool {
    return !std.mem.eql(u8, app_ref.settings.current.appearance.mode, value);
}

fn modeSystem(_: ?*anyopaque) void {
    setMode("system");
}
fn modeDark(_: ?*anyopaque) void {
    setMode("dark");
}
fn modeLight(_: ?*anyopaque) void {
    setMode("light");
}
fn notSystem(_: ?*anyopaque) bool {
    return modeIsNot("system");
}
fn notDark(_: ?*anyopaque) bool {
    return modeIsNot("dark");
}
fn notLight(_: ?*anyopaque) bool {
    return modeIsNot("light");
}

/// Which theme a pick sets: one for both modes (and the per-mode ones
/// cleared), or the dark or light mode's only.
pub const Slot = enum { both, dark, light };

/// Uses the theme `id` (settings.json's appearance.theme, darkTheme or lightTheme).
pub fn setTheme(app: *App, id: []const u8, slot: Slot) void {
    var s = app.settings.current;
    switch (slot) {
        .both => {
            s.appearance.theme = id;
            s.appearance.dark_theme = "";
            s.appearance.light_theme = "";
        },
        .dark => s.appearance.dark_theme = id,
        .light => s.appearance.light_theme = id,
    }
    page.commit(app, s);
}

/// The theme the list marks for a slot: the dark one for both.
pub fn inUse(app: *App, slot: Slot) []const u8 {
    const a = app.settings.current.appearance;
    return if (slot == .light) looks.inUseLight(a) else looks.inUseDark(a);
}

// ---- ⌘K's list of themes ----

/// Every theme, read when the list opens and freed when the palette
/// closes (releaseWhenClosed), as the Mac's ThemeSource.
var listed: ?themes.library.List = null;
var slots = [_]Slot{ .both, .dark, .light };

fn choose(_: ?*anyopaque) void {
    openList(&slots[0], t("Choose a theme", "Escolher um tema"));
}

fn chooseDark(_: ?*anyopaque) void {
    openList(&slots[1], t("Choose the theme for dark mode", "Escolher o tema do modo escuro"));
}

fn chooseLight(_: ?*anyopaque) void {
    openList(&slots[2], t("Choose the theme for light mode", "Escolher o tema do modo claro"));
}

fn openList(slot: *Slot, placeholder: []const u8) void {
    app_ref.palette.toggle(&app_ref.u, .{
        .context = slot,
        .placeholder = placeholder,
        .empty_text = t("No themes found", "Nenhum tema encontrado"),
        .icon = icons.phosphor.palette,
        .search = search,
        .choose = chooseItem,
    });
}

/// The name or the description holds the query (case does not matter);
/// the theme in use first; for one mode, only themes with that version.
fn search(context: *anyopaque, arena: std.mem.Allocator, query: []const u8, out: *std.ArrayList(palette.Item)) ?[]const u8 {
    const slot: *Slot = @ptrCast(@alignCast(context));
    if (listed == null) listed = themes.library.all(app_ref.gpa, app_ref.themes.folder);
    const current = inUse(app_ref, slot.*);
    var count: usize = 0;
    for ([_]bool{ true, false }) |in_use_pass| {
        for (listed.?.families) |f| {
            if ((slot.* == .dark and f.dark == null) or (slot.* == .light and f.light == null)) continue;
            if (std.mem.eql(u8, f.id, current) != in_use_pass or !matches(f, query)) continue;
            out.append(arena, .{ .id = f.id, .title = f.name, .detail = if (in_use_pass) t("in use", "em uso") else versions(f), .icon = icons.phosphor.palette }) catch {};
            count += 1;
        }
    }
    return std.fmt.allocPrint(arena, "{d} {s}", .{ count, t("themes", "temas") }) catch null;
}

pub fn matches(f: themes.Family, query: []const u8) bool {
    if (query.len == 0) return true;
    return std.ascii.indexOfIgnoreCase(f.name, query) != null or std.ascii.indexOfIgnoreCase(f.description, query) != null;
}

pub fn versions(f: themes.Family) []const u8 {
    if (f.dark != null and f.light != null) return t("dark and light", "escuro e claro");
    return if (f.dark != null) t("dark", "escuro") else t("light", "claro");
}

fn chooseItem(context: *anyopaque, id: []const u8, _: palette.How) void {
    const slot: *Slot = @ptrCast(@alignCast(context));
    setTheme(app_ref, id, slot.*);
}

/// After the palette's frame: the list goes once the palette shows
/// something else or nothing (the chosen id is the palette's own copy).
pub fn releaseWhenClosed(app: *App) void {
    if (listed == null) return;
    if (app.palette.opened) |o| for (&slots) |*slot| {
        if (o.context == @as(*anyopaque, slot)) return;
    };
    listed.?.deinit();
    listed = null;
}

// ---- Importing and the folder ----

fn importRun(_: ?*anyopaque) void {
    importTheme(app_ref);
}

fn openFolderRun(_: ?*anyopaque) void {
    openFolder(app_ref);
}

/// Asks for a theme file, saves it in the themes folder and uses it.
pub fn importTheme(app: *App) void {
    const path = pickFile(app.gpa, app.window.hwnd) orelse return;
    defer app.gpa.free(path);
    var arena: std.heap.ArenaAllocator = .init(app.gpa);
    defer arena.deinit();
    var problem: themes.theme.Problem = .{};
    const id = save(app, arena.allocator(), path, &problem) catch |err| {
        tell(app, path, if (err == error.InvalidTheme) problem else .{ .field = "(file)", .message = @errorName(err) });
        return;
    };
    defer app.gpa.free(id);
    // The same name again replaces the file in use: read it anew.
    _ = app.themes.reload();
    @import("themes_page.zig").invalidate(app);
    setTheme(app, id, .both);
}

/// Reads `path` as a theme and saves it in the folder; its id, owned.
fn save(app: *App, arena: std.mem.Allocator, path: []const u8, problem: *themes.theme.Problem) ![]u8 {
    if (app.themes.folder.len == 0) return error.NoThemesFolder;
    const data = w.files.read(app.gpa, path, 1024 * 1024) orelse return error.Unreadable;
    defer app.gpa.free(data);
    const th = try themes.import.read(arena, app.gpa, path, data, problem);
    return themes.library.save(app.gpa, app.themes.folder, th);
}

/// The Mac's alert: the file is not a theme, and which field says so.
fn tell(app: *App, path: []const u8, problem: themes.theme.Problem) void {
    const base = std.fs.path.basenameWindows(path);
    const text = std.fmt.allocPrint(app.gpa, "{s}: {s}: {s}", .{ base, problem.field, problem.message }) catch return;
    defer app.gpa.free(text);
    const title = t("This file is not a theme Cadex can read", "Este arquivo não é um tema que o Cadex lê");
    const wide_text = std.unicode.wtf8ToWtf16LeAllocZ(app.gpa, text) catch return;
    defer app.gpa.free(wide_text);
    const wide_title = std.unicode.wtf8ToWtf16LeAllocZ(app.gpa, title) catch return;
    defer app.gpa.free(wide_title);
    _ = c.MessageBoxW(app.window.hwnd, wide_text.ptr, wide_title.ptr, c.MB_OK | c.MB_ICONWARNING);
}

/// The themes folder in File Explorer, made first if needed.
pub fn openFolder(app: *App) void {
    const dir = app.themes.folder;
    if (dir.len == 0) return;
    w.files.makeFolder(app.gpa, dir);
    const wide = std.unicode.wtf8ToWtf16LeAllocZ(app.gpa, dir) catch return;
    defer app.gpa.free(wide);
    _ = c.ShellExecuteW(null, w.L("open"), wide.ptr, null, null, c.SW_SHOWNORMAL);
}

/// The system's file picker (IFileOpenDialog), any file: Ghostty themes
/// have no extension.
fn pickFile(gpa: std.mem.Allocator, owner: c.HWND) ?[]u8 {
    const clsid = w.guid("dc1c5a9c-e88a-4dde-a5a1-60f82a20aef7"); // CLSID_FileOpenDialog
    const iid = w.guid("d57c7288-d4ad-4768-be02-9d969532d960"); // IID_IFileOpenDialog
    var raw: ?*anyopaque = null;
    if (c.CoCreateInstance(&clsid, null, c.CLSCTX_INPROC_SERVER, &iid, &raw) < 0) return null;
    const dialog: *c.IFileOpenDialog = @ptrCast(@alignCast(raw.?));
    defer w.release(dialog);
    const title = t("A theme from iTerm2 (.itermcolors), Ghostty, base16 or base24 (.yaml), or Cadex (.json)", "Um tema do iTerm2 (.itermcolors), do Ghostty, base16 ou base24 (.yaml), ou do Cadex (.json)");
    if (std.unicode.wtf8ToWtf16LeAllocZ(gpa, title)) |wide| {
        defer gpa.free(wide);
        _ = w.call(dialog, "SetTitle", .{wide.ptr});
    } else |_| {}
    var options: c.DWORD = 0;
    _ = w.call(dialog, "GetOptions", .{&options});
    _ = w.call(dialog, "SetOptions", .{options | c.FOS_FORCEFILESYSTEM | c.FOS_FILEMUSTEXIST});
    if (w.call(dialog, "Show", .{owner}) < 0) return null;
    var item: [*c]c.IShellItem = null;
    if (w.call(dialog, "GetResult", .{&item}) < 0) return null;
    defer w.release(item);
    var name: [*c]u16 = null;
    if (w.call(item, "GetDisplayName", .{ c.SIGDN_FILESYSPATH, &name }) < 0) return null;
    defer c.CoTaskMemFree(name);
    return std.unicode.wtf16LeToWtf8Alloc(gpa, std.mem.span(@as([*:0]u16, @ptrCast(name)))) catch null;
}

test {
    @import("win32").refAllDeep(@This());
}
