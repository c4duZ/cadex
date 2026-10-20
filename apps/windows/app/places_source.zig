//! The palette's `@` list (the Mac's MergedSource of TabSource and the
//! spaces): the tabs of the space on screen, then the spaces; choosing one
//! goes there.

const std = @import("std");
const icons = @import("icons");
const palette = @import("command-palette");
const App = @import("app.zig").App;

pub fn source(app: *App) palette.Source {
    return .{ .context = app, .placeholder = "Ir para a aba ou o space", .empty_text = "Nenhuma aba ou space", .icon = icons.phosphor.stack, .search = search, .choose = choose };
}

fn matches(text: []const u8, query: []const u8) bool {
    return query.len == 0 or std.ascii.indexOfIgnoreCase(text, query) != null;
}

fn search(context: *anyopaque, arena: std.mem.Allocator, query: []const u8, out: *std.ArrayList(palette.Item)) ?[]const u8 {
    const app: *App = @ptrCast(@alignCast(context));
    var first = true;
    for (app.tabs.list.order.items, 0..) |id, i| {
        const t = app.tabs.tabs.get(id) orelse continue;
        const title = app.tabs.title(t, arena);
        if (!matches(title, query)) continue;
        out.append(arena, .{
            .id = std.fmt.allocPrint(arena, "t{d}", .{id}) catch continue,
            .title = title,
            .detail = std.fmt.allocPrint(arena, "aba {d} · {d} {s}", .{ i + 1, t.tree.count(), if (t.tree.count() == 1) "painel" else "painéis" }) catch "",
            .icon = icons.phosphor.terminal_window,
            .section = if (first) "Abas" else "",
        }) catch {};
        first = false;
    }
    first = true;
    for (app.spaces.list.items, 0..) |s, i| {
        if (!matches(s.name, query)) continue;
        out.append(arena, .{
            .id = std.fmt.allocPrint(arena, "s{d}", .{i}) catch continue,
            .title = s.name,
            .detail = if (i == app.spaces.active) "atual" else "",
            .icon = icons.phosphor.stack,
            .section = if (first) "Spaces" else "",
        }) catch {};
        first = false;
    }
    return null;
}

fn choose(context: *anyopaque, id: []const u8, _: palette.How) void {
    const app: *App = @ptrCast(@alignCast(context));
    const n = std.fmt.parseInt(u32, id[1..], 10) catch return;
    if (id[0] == 't') app.tabs.select(n) else app.spaces.select(n);
}

test {
    @import("win32").refAllDeep(@This());
}
