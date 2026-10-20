//! The environment of new terminals on Windows (docs/spec/workspace.md):
//! "Local" (Windows itself) or a WSL distribution, picked from a palette
//! list (workspace.environment, Windows only: the Mac has one environment).
//! A terminal in a distro reports Linux folders; they become
//! \\wsl.localhost\<distro>\... for the tree and the status bar.

const std = @import("std");
const cadex = @import("cadex");
const icons = @import("icons");
const strings = @import("strings");
const palette = @import("command-palette");
const terminal = @import("terminal");
const App = @import("app.zig").App;

var app_ref: *App = undefined;

pub fn source(app: *App) palette.Source {
    app_ref = app;
    return .{ .context = app, .placeholder = strings.t("Environment for new terminals", "Ambiente dos terminais novos"), .empty_text = strings.t("No environments", "Nenhum ambiente"), .icon = icons.phosphor.terminal_window, .search = search, .choose = choose };
}

fn search(context: *anyopaque, arena: std.mem.Allocator, query: []const u8, out: *std.ArrayList(palette.Item)) ?[]const u8 {
    const app: *App = @ptrCast(@alignCast(context));
    var names: std.ArrayList([]const u8) = .empty;
    names.append(arena, "Local") catch {};
    var raw: [*c]u8 = null;
    var len: usize = 0;
    if (cadex.cadex_workspace_wsl_distros(&raw, &len) == cadex.CADEX_OK and raw != null) {
        defer cadex.cadex_free(raw);
        var it = std.mem.tokenizeScalar(u8, raw[0..len], '\n');
        while (it.next()) |d| names.append(arena, arena.dupe(u8, d) catch continue) catch {};
    }
    const current = app.environment orelse "Local";
    for (names.items) |n| {
        if (query.len > 0 and std.ascii.indexOfIgnoreCase(n, query) == null) continue;
        out.append(arena, .{ .id = n, .title = n, .detail = if (std.mem.eql(u8, n, current)) strings.t("in use", "em uso") else if (std.mem.eql(u8, n, "Local")) "Windows" else "WSL", .icon = icons.phosphor.terminal_window }) catch {};
    }
    return if (names.items.len == 1) strings.t("WSL is not installed", "Sem WSL instalado") else null;
}

fn choose(context: *anyopaque, id: []const u8, _: palette.How) void {
    const app: *App = @ptrCast(@alignCast(context));
    if (app.environment) |e| app.gpa.free(e);
    app.environment = if (std.mem.eql(u8, id, "Local")) null else app.gpa.dupe(u8, id) catch null;
}

fn open(_: ?*anyopaque) void {
    app_ref.palette.toggle(&app_ref.u, source(app_ref));
}

pub fn register(app: *App) void {
    app_ref = app;
    app.registry.add(.{ .id = "workspace.environment", .title = strings.t("Choose Terminal Environment (Local or WSL)", "Escolher o ambiente dos terminais (Local ou WSL)"), .keywords = &.{ "wsl", "linux", "ubuntu", "ambiente", "environment" }, .run = open });
}

/// The name the status bar shows for the focused terminal.
pub fn label(view: ?*terminal.View) []const u8 {
    if (view) |v| if (v.environment) |e| return e;
    return "Local";
}

/// A folder of `view` as Windows sees it, in `out` (a WSL terminal's
/// /home/x is \\wsl.localhost\<distro>\home\x); itself otherwise.
pub fn windowsFolder(view: *terminal.View, folder: []const u8, out: []u8) []const u8 {
    const distro = view.environment orelse return folder;
    if (folder.len == 0 or folder[0] != '/') return folder;
    var distro_z: [128]u8 = undefined;
    const dz = std.fmt.bufPrintZ(&distro_z, "{s}", .{distro}) catch return folder;
    var path_z: [2048]u8 = undefined;
    const pz = std.fmt.bufPrintZ(&path_z, "{s}", .{folder}) catch return folder;
    var raw: [*c]u8 = null;
    var len: usize = 0;
    if (cadex.cadex_workspace_wsl_path(dz.ptr, pz.ptr, false, &raw, &len) != cadex.CADEX_OK or raw == null) return folder;
    defer cadex.cadex_free(raw);
    if (len > out.len) return folder;
    @memcpy(out[0..len], raw[0..len]);
    return out[0..len];
}

test {
    @import("win32").refAllDeep(@This());
}
