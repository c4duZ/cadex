//! The commands of the tabs (ADR 0005), the Mac's ids and shortcuts, acting
//! on the tabs of the space on screen (the app's `current`).

const std = @import("std");
const gfx = @import("gfx");
const palette = @import("command-palette");
const controller = @import("controller.zig");
const bar = @import("bar.zig");

const Tabs = controller.Tabs;

/// Where the commands find the tabs on screen, the rename bar and the area
/// of the panes (for moving the focus by direction).
pub const Current = struct {
    context: *anyopaque,
    tabs: *const fn (context: *anyopaque) ?*Tabs,
    bar: *const fn (context: *anyopaque) *bar.Bar,
    ui: *const fn (context: *anyopaque) *@import("ui").Ui,
    panes_area: *const fn (context: *anyopaque) gfx.Rect,
};

var current: Current = undefined;

fn tabs() ?*Tabs {
    return current.tabs(current.context);
}

fn has(n: usize) bool {
    const t = tabs() orelse return false;
    return t.list.order.items.len >= n;
}

fn hasTabs(_: ?*anyopaque) bool {
    return has(1);
}
fn hasTwo(_: ?*anyopaque) bool {
    return has(2);
}
fn hasSplit(_: ?*anyopaque) bool {
    const t = tabs() orelse return false;
    const a = t.active() orelse return false;
    return a.tree.count() > 1;
}

fn newTab(_: ?*anyopaque) void {
    if (tabs()) |t| t.newTab(null);
}
fn closePane(_: ?*anyopaque) void {
    if (tabs()) |t| t.closeFocused();
}
fn rename(_: ?*anyopaque) void {
    if (tabs()) |t| current.bar(current.context).startRename(current.ui(current.context), t);
}
fn previousUsed(_: ?*anyopaque) void {
    const t = tabs() orelse return;
    if (t.list.previouslyUsed()) |id| t.select(id);
}
fn leastRecent(_: ?*anyopaque) void {
    const t = tabs() orelse return;
    if (t.list.leastRecentlyUsed()) |id| t.select(id);
}
fn splitRight(_: ?*anyopaque) void {
    if (tabs()) |t| t.split(.horizontal);
}
fn splitDown(_: ?*anyopaque) void {
    if (tabs()) |t| t.split(.vertical);
}
fn next(_: ?*anyopaque) void {
    if (tabs()) |t| t.cycleFocus(1);
}
fn previous(_: ?*anyopaque) void {
    if (tabs()) |t| t.cycleFocus(-1);
}

const directions = [_]struct { id: []const u8, title: []const u8, key: []const u8, dir: @import("pane_tree.zig").Direction }{
    .{ .id = "pane.focus-left", .title = "Ir para o painel à esquerda", .key = "cmd+opt+left", .dir = .left },
    .{ .id = "pane.focus-right", .title = "Ir para o painel à direita", .key = "cmd+opt+right", .dir = .right },
    .{ .id = "pane.focus-up", .title = "Ir para o painel acima", .key = "cmd+opt+up", .dir = .up },
    .{ .id = "pane.focus-down", .title = "Ir para o painel abaixo", .key = "cmd+opt+down", .dir = .down },
};
var direction_slots: [directions.len]usize = .{ 0, 1, 2, 3 };

fn focusDirection(context: ?*anyopaque) void {
    const i: *usize = @ptrCast(@alignCast(context.?));
    if (tabs()) |t| t.moveFocus(directions[i.*].dir, current.panes_area(current.context));
}

var position_slots: [9]usize = .{ 1, 2, 3, 4, 5, 6, 7, 8, 9 };

fn selectPosition(context: ?*anyopaque) void {
    const n: *usize = @ptrCast(@alignCast(context.?));
    const t = tabs() orelse return;
    if (t.list.atPosition(n.*)) |id| t.select(id);
}

fn hasPosition(context: ?*anyopaque) bool {
    const n: *usize = @ptrCast(@alignCast(context.?));
    return has(n.*);
}

pub fn register(registry: *palette.Registry, where: Current) void {
    current = where;
    registry.add(.{ .id = "tab.new", .title = "Nova aba", .keywords = &.{ "new tab", "terminal", "abrir" }, .shortcut = "cmd+t", .run = newTab });
    registry.add(.{ .id = "pane.close", .title = "Fechar painel", .keywords = &.{ "close", "fechar aba" }, .shortcut = "cmd+w", .run = closePane, .available = hasTabs });
    registry.add(.{ .id = "tab.rename", .title = "Renomear aba", .keywords = &.{ "rename", "nome" }, .run = rename, .available = hasTabs });
    registry.add(.{ .id = "tab.previous-used", .title = "Voltar para a aba anterior", .keywords = &.{ "recent", "alternar" }, .shortcut = "ctrl+tab", .run = previousUsed, .available = hasTwo });
    registry.add(.{ .id = "tab.least-recently-used", .title = "Ir para a aba usada há mais tempo", .keywords = &.{ "recent", "alternar" }, .shortcut = "ctrl+shift+tab", .run = leastRecent, .available = hasTwo });
    registry.add(.{ .id = "pane.split-right", .title = "Dividir à direita", .keywords = &.{ "split", "painel", "lado" }, .shortcut = "cmd+d", .run = splitRight, .available = hasTabs });
    registry.add(.{ .id = "pane.split-down", .title = "Dividir para baixo", .keywords = &.{ "split", "painel", "embaixo" }, .shortcut = "cmd+shift+d", .run = splitDown, .available = hasTabs });
    registry.add(.{ .id = "pane.next", .title = "Próximo painel", .keywords = &.{ "pane", "foco" }, .shortcut = "cmd+]", .run = next, .available = hasSplit });
    registry.add(.{ .id = "pane.previous", .title = "Painel anterior", .keywords = &.{ "pane", "foco" }, .shortcut = "cmd+[", .run = previous, .available = hasSplit });
    for (directions, 0..) |d, i| {
        registry.add(.{ .id = d.id, .title = d.title, .keywords = &.{ "pane", "foco" }, .shortcut = d.key, .context = &direction_slots[i], .run = focusDirection, .available = hasSplitAny });
    }
    inline for (1..10) |n| {
        registry.add(.{
            .id = std.fmt.comptimePrint("tab.select-{d}", .{n}),
            .title = std.fmt.comptimePrint("Ir para a aba {d}", .{n}),
            .keywords = &.{std.fmt.comptimePrint("tab {d}", .{n})},
            .shortcut = std.fmt.comptimePrint("cmd+{d}", .{n}),
            .context = &position_slots[n - 1],
            .run = selectPosition,
            .available = hasPosition,
        });
    }
}

fn hasSplitAny(_: ?*anyopaque) bool {
    return hasSplit(null);
}

test {
    std.testing.refAllDecls(@This());
}
