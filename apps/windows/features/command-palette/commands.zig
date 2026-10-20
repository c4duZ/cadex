//! The commands as a palette list: with the field empty, "Abrir" first
//! (the ways to open things, as the "+" menu), then the recent ones, then
//! one section per area, alphabetical; typing ranks every available
//! command by its title, then by its keywords. Commands that cannot run
//! now are not listed (docs/spec/command-palette.md).

const std = @import("std");
const gfx = @import("gfx");
const registry_mod = @import("registry.zig");
const source_mod = @import("source.zig");

const Registry = registry_mod.Registry;
const Item = source_mod.Item;

/// A command shown first, under "Abrir", with its own name and icon.
pub const Pin = struct {
    id: []const u8,
    title: []const u8,
    icon: u21,
};

pub const Commands = struct {
    registry: *Registry,
    pins: []const Pin = &.{},
    /// The keys of a command as shown ("Ctrl+Shift+D"), from the shortcuts.
    shortcut_label: *const fn (context: ?*anyopaque, id: []const u8, arena: std.mem.Allocator) []const u8,
    shortcut_context: ?*anyopaque = null,
    /// The icon of a section (by index of registry.sections; the last is "Cadex").
    section_icons: [registry_mod.sections.len + 1]u21,
    recent_icon: u21,

    pub fn source(self: *Commands, icon: u21) source_mod.Source {
        return .{
            .context = self,
            .placeholder = "Buscar comandos",
            .empty_text = "Nenhum comando encontrado",
            .icon = icon,
            .search = search,
            .choose = choose,
        };
    }

    fn item(self: *Commands, arena: std.mem.Allocator, command: *const registry_mod.Command, section: []const u8) Item {
        return .{
            .id = command.id,
            .title = command.title,
            .icon = self.section_icons[registry_mod.sectionOf(command.id)],
            .shortcut = self.shortcut_label(self.shortcut_context, command.id, arena),
            .section = section,
        };
    }

    fn search(context: *anyopaque, arena: std.mem.Allocator, query: []const u8, out: *std.ArrayList(Item)) ?[]const u8 {
        const self: *Commands = @ptrCast(@alignCast(context));
        if (query.len == 0) self.listSections(arena, out) catch {} else self.listRanked(arena, query, out) catch {};
        return null;
    }

    fn listSections(self: *Commands, arena: std.mem.Allocator, out: *std.ArrayList(Item)) !void {
        const r = self.registry;
        var first = true;
        for (self.pins) |pin| {
            if (!r.isAvailable(pin.id)) continue;
            const command = r.find(pin.id).?;
            var row = self.item(arena, command, if (first) "Abrir" else "");
            row.title = pin.title;
            row.icon = pin.icon;
            try out.append(arena, row);
            first = false;
        }
        first = true;
        for (r.recent.items) |id| {
            if (!r.isAvailable(id)) continue;
            var row = self.item(arena, r.find(id).?, if (first) "Recentes" else "");
            row.icon = self.recent_icon;
            try out.append(arena, row);
            first = false;
        }
        // One section per area, each alphabetical by title.
        var by_section: [registry_mod.sections.len + 1]std.ArrayList(*const registry_mod.Command) = @splat(.empty);
        for (r.commands.items) |*command| {
            if (command.available) |f| if (!f(command.context)) continue;
            try by_section[registry_mod.sectionOf(command.id)].append(arena, command);
        }
        for (&by_section, 0..) |*list, s| {
            std.mem.sort(*const registry_mod.Command, list.items, {}, struct {
                fn lessThan(_: void, a: *const registry_mod.Command, b: *const registry_mod.Command) bool {
                    return std.mem.order(u8, a.title, b.title) == .lt;
                }
            }.lessThan);
            for (list.items, 0..) |command, i| {
                try out.append(arena, self.item(arena, command, if (i == 0) registry_mod.sectionTitle(s) else ""));
            }
        }
    }

    fn listRanked(self: *Commands, arena: std.mem.Allocator, query: []const u8, out: *std.ArrayList(Item)) !void {
        var commands: std.ArrayList(*const registry_mod.Command) = .empty;
        var titles: std.ArrayList([]const u8) = .empty;
        var keywords: std.ArrayList([]const u8) = .empty;
        for (self.registry.commands.items) |*command| {
            if (command.available) |f| if (!f(command.context)) continue;
            try commands.append(arena, command);
            try titles.append(arena, command.title);
            try keywords.append(arena, try std.mem.join(arena, " ", command.keywords));
        }
        const seen = try arena.alloc(bool, commands.items.len);
        @memset(seen, false);
        for (try source_mod.rank(arena, query, titles.items)) |m| {
            seen[m.index] = true;
            var row = self.item(arena, commands.items[m.index], "");
            row.bold = m.bold;
            try out.append(arena, row);
        }
        for (try source_mod.rank(arena, query, keywords.items)) |m| {
            if (seen[m.index]) continue;
            try out.append(arena, self.item(arena, commands.items[m.index], ""));
        }
    }

    fn choose(context: *anyopaque, id: []const u8, _: source_mod.How) void {
        const self: *Commands = @ptrCast(@alignCast(context));
        _ = self.registry.run(id);
    }
};

test {
    @import("win32").refAllDeep(@This());
}
