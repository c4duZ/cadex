//! Every action of the app is a command (docs/adr/0005-every-action-is-a-command.md):
//! an id the menus, buttons and shortcuts run, a Portuguese title the
//! palette finds, the area it belongs to, and whether it can run now. The
//! ids are the Mac's, so settings.json and the habits carry over.

const std = @import("std");

pub const Command = struct {
    /// Stable, English, feature-prefixed: "tab.new", "pane.split-right".
    id: []const u8,
    title: []const u8,
    /// Extra words the search matches ("limpar" also finds "clear").
    keywords: []const []const u8 = &.{},
    /// The default keys, in the Mac's notation ("cmd+shift+d"); the
    /// shortcuts feature turns ⌘ into Ctrl+Shift on Windows.
    shortcut: ?[]const u8 = null,
    context: ?*anyopaque = null,
    run: *const fn (context: ?*anyopaque) void,
    /// Null or true: can run now. The palette hides what cannot.
    available: ?*const fn (context: ?*anyopaque) bool = null,
};

pub const Registry = struct {
    gpa: std.mem.Allocator,
    commands: std.ArrayList(Command) = .empty,
    /// Most recent first, at most `max_recent`, by id.
    recent: std.ArrayList([]const u8) = .empty,

    const max_recent = 5;

    pub fn deinit(self: *Registry) void {
        self.commands.deinit(self.gpa);
        self.recent.deinit(self.gpa);
    }

    /// Adds a command; a second one with the same id replaces the first
    /// (a feature registering again after a settings change).
    pub fn add(self: *Registry, command: Command) void {
        for (self.commands.items) |*existing| {
            if (std.mem.eql(u8, existing.id, command.id)) {
                existing.* = command;
                return;
            }
        }
        self.commands.append(self.gpa, command) catch {};
    }

    pub fn find(self: *const Registry, id: []const u8) ?*const Command {
        for (self.commands.items) |*command| if (std.mem.eql(u8, command.id, id)) return command;
        return null;
    }

    pub fn isAvailable(self: *const Registry, id: []const u8) bool {
        const command = self.find(id) orelse return false;
        return if (command.available) |f| f(command.context) else true;
    }

    /// Runs `id` if it exists and can run now; true when it ran.
    pub fn run(self: *Registry, id: []const u8) bool {
        const command = self.find(id) orelse return false;
        if (command.available) |f| if (!f(command.context)) return false;
        self.remember(command.id);
        command.run(command.context);
        return true;
    }

    fn remember(self: *Registry, id: []const u8) void {
        if (std.mem.startsWith(u8, id, "palette.")) return;
        for (self.recent.items, 0..) |r, i| {
            if (std.mem.eql(u8, r, id)) {
                _ = self.recent.orderedRemove(i);
                break;
            }
        }
        self.recent.insert(self.gpa, 0, id) catch return;
        if (self.recent.items.len > max_recent) self.recent.shrinkRetainingCapacity(max_recent);
    }
};

/// The palette's sections with an empty field, by id prefix, in the order
/// of docs/spec/command-palette.md.
pub const Section = struct {
    title: []const u8,
    prefixes: []const []const u8,
};

pub const sections = [_]Section{
    .{ .title = "Abas", .prefixes = &.{"tab"} },
    .{ .title = "Painéis", .prefixes = &.{"pane"} },
    .{ .title = "Arquivos", .prefixes = &.{ "explorer", "workspace" } },
    .{ .title = "Busca", .prefixes = &.{"search"} },
    .{ .title = "Editor", .prefixes = &.{ "editor", "markdown" } },
    .{ .title = "Terminal", .prefixes = &.{"terminal"} },
    .{ .title = "Git", .prefixes = &.{ "git", "history", "diff" } },
    .{ .title = "Web e mídia", .prefixes = &.{ "preview", "media" } },
    .{ .title = "Spaces", .prefixes = &.{"space"} },
    .{ .title = "Editar", .prefixes = &.{"edit"} },
};

/// Anything else: the app, settings, the palette, the window.
pub const app_section = sections.len;

pub fn sectionOf(id: []const u8) usize {
    const prefix = id[0 .. std.mem.indexOfScalar(u8, id, '.') orelse id.len];
    for (sections, 0..) |s, i| {
        for (s.prefixes) |p| if (std.mem.eql(u8, p, prefix)) return i;
    }
    return app_section;
}

pub fn sectionTitle(index: usize) []const u8 {
    return if (index < sections.len) sections[index].title else "Cadex";
}

const testing = std.testing;

test "commands run by id, unavailable ones do not, and recents keep order" {
    const Counter = struct {
        var runs: u32 = 0;
        fn run(_: ?*anyopaque) void {
            runs += 1;
        }
        fn never(_: ?*anyopaque) bool {
            return false;
        }
    };
    var registry: Registry = .{ .gpa = testing.allocator };
    defer registry.deinit();
    registry.add(.{ .id = "tab.new", .title = "Nova aba", .run = Counter.run });
    registry.add(.{ .id = "pane.close", .title = "Fechar painel", .run = Counter.run, .available = Counter.never });
    try testing.expect(registry.run("tab.new"));
    try testing.expect(!registry.run("pane.close"));
    try testing.expect(!registry.run("nothing"));
    try testing.expectEqual(@as(u32, 1), Counter.runs);
    try testing.expectEqualStrings("tab.new", registry.recent.items[0]);
}

test "sections follow the id prefix" {
    try testing.expectEqualStrings("Painéis", sectionTitle(sectionOf("pane.split-right")));
    try testing.expectEqualStrings("Git", sectionTitle(sectionOf("history.refresh")));
    try testing.expectEqualStrings("Cadex", sectionTitle(sectionOf("settings.open")));
}
