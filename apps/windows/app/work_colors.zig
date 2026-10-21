//! Colors for spaces and tabs (plan 15, phase D), as the Mac's
//! WorkColors.swift: a name saved in spaces.json, drawn as the theme's own
//! ANSI color so it fits any theme. The active tab's color, else the
//! space's, else the accent paints the window (theme, accent, space, tab:
//! each layer over the one before). space.set-color and tab.set-color
//! choose it in ⌘K.

const std = @import("std");
const gfx = @import("gfx");
const icons = @import("icons");
const strings = @import("strings");
const palette = @import("command-palette");
const App = @import("app.zig").App;

const t = strings.t;

pub const Color = struct {
    name: []const u8,
    /// Index in the theme's 16 ANSI colors.
    ansi: usize,
    title_en: []const u8,
    title_pt: []const u8,
};

/// The Mac's order (WorkColor.allCases).
pub const all = [_]Color{
    .{ .name = "red", .ansi = 1, .title_en = "Red", .title_pt = "Vermelho" },
    .{ .name = "yellow", .ansi = 3, .title_en = "Yellow", .title_pt = "Amarelo" },
    .{ .name = "green", .ansi = 2, .title_en = "Green", .title_pt = "Verde" },
    .{ .name = "cyan", .ansi = 6, .title_en = "Cyan", .title_pt = "Ciano" },
    .{ .name = "blue", .ansi = 4, .title_en = "Blue", .title_pt = "Azul" },
    .{ .name = "magenta", .ansi = 5, .title_en = "Magenta", .title_pt = "Magenta" },
};

pub fn find(name: []const u8) ?Color {
    for (all) |c| if (std.mem.eql(u8, c.name, name)) return c;
    return null;
}

/// The color painting the window now, from the theme in use.
pub fn current(app: *App) ?u32 {
    const name = activeTabColor(app) orelse app.spaces.activeColor() orelse return null;
    const c = find(name) orelse return null;
    return app.themes.current.terminal.ansi[c.ansi];
}

fn activeTabColor(app: *App) ?[]const u8 {
    const tab = app.tabs.active() orelse return null;
    return tab.color;
}

// ---- The commands and ⌘K's list ----

const Target = enum { space, tab };
var app_ref: *App = undefined;
var targets = [_]Target{ .space, .tab };

pub fn register(app: *App) void {
    app_ref = app;
    app.registry.add(.{ .id = "space.set-color", .title = t("Set Space Color", "Escolher a cor do space"), .keywords = &.{ "space", "color", "cor", "paint", "pintar" }, .run = setSpaceColor });
    app.registry.add(.{ .id = "tab.set-color", .title = t("Set Tab Color", "Escolher a cor da aba"), .keywords = &.{ "tab", "aba", "color", "cor", "paint", "pintar" }, .run = setTabColor, .available = hasTab });
}

fn setSpaceColor(_: ?*anyopaque) void {
    open(&targets[0]);
}

fn setTabColor(_: ?*anyopaque) void {
    open(&targets[1]);
}

fn hasTab(_: ?*anyopaque) bool {
    return app_ref.tabs.active() != null;
}

fn open(target: *Target) void {
    app_ref.palette.toggle(&app_ref.u, .{
        .context = target,
        .placeholder = t("Choose a color", "Escolher uma cor"),
        .empty_text = t("No such color", "Nenhuma cor assim"),
        .icon = icons.phosphor.palette,
        .search = search,
        .choose = choose,
    });
}

fn inUse(target: Target) ?[]const u8 {
    return switch (target) {
        .space => app_ref.spaces.activeColor(),
        .tab => activeTabColor(app_ref),
    };
}

/// None first, then the six, each as a dot of the theme's color.
fn search(context: *anyopaque, arena: std.mem.Allocator, query: []const u8, out: *std.ArrayList(palette.Item)) ?[]const u8 {
    const target: *Target = @ptrCast(@alignCast(context));
    const used = inUse(target.*);
    const none = t("No Color", "Sem cor");
    if (matches(none, "", query)) out.append(arena, .{ .id = "", .title = none, .icon = icons.phosphor.palette }) catch {};
    for (all) |c| {
        const title = t(c.title_en, c.title_pt);
        if (!matches(title, c.name, query)) continue;
        const in_use = if (used) |u| std.mem.eql(u8, u, c.name) else false;
        out.append(arena, .{
            .id = c.name,
            .title = title,
            .detail = if (in_use) t("in use", "em uso") else "",
            .icon = icons.phosphor.palette,
            .icon_color = gfx.Color.rgb(app_ref.themes.current.terminal.ansi[c.ansi]),
        }) catch {};
    }
    return null;
}

fn matches(title: []const u8, name: []const u8, query: []const u8) bool {
    if (query.len == 0) return true;
    return std.ascii.indexOfIgnoreCase(title, query) != null or (name.len > 0 and std.ascii.indexOfIgnoreCase(name, query) != null);
}

fn choose(context: *anyopaque, id: []const u8, _: palette.How) void {
    const target: *Target = @ptrCast(@alignCast(context));
    const name: ?[]const u8 = if (id.len == 0) null else id;
    switch (target.*) {
        .space => app_ref.spaces.setActiveColor(name),
        .tab => {
            const tab = app_ref.tabs.active() orelse return;
            tab.setColor(name);
            app_ref.tabs.host.on_change(app_ref.tabs.host.context);
        },
    }
    app_ref.window.redraw();
}

test "the six colors are the theme's ANSI red to cyan, as on the Mac" {
    try std.testing.expectEqual(@as(usize, 1), find("red").?.ansi);
    try std.testing.expectEqual(@as(usize, 6), find("cyan").?.ansi);
    try std.testing.expect(find("orange") == null);
}

test {
    @import("win32").refAllDeep(@This());
}
