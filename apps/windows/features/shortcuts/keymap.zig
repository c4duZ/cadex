//! Which command each key combination runs: the defaults the commands
//! declare, then the user's `shortcuts` section of settings.json on top
//! (docs/spec/shortcuts.md). Problems go to `problems`, for the log.

const std = @import("std");
const palette = @import("command-palette");
const KeyCombo = @import("key_combo.zig").KeyCombo;

pub const Binding = struct { combo: KeyCombo, id: []const u8 };

/// One entry of the settings' section: a combination, and a command id or
/// null (turns the default of that combination off).
pub const Preference = struct { keys: []const u8, id: ?[]const u8 };

pub const Keymap = struct {
    gpa: std.mem.Allocator,
    bindings: std.ArrayList(Binding) = .empty,
    problems: std.ArrayList([]u8) = .empty,
    /// Owns the ids that came from the settings.
    arena: std.heap.ArenaAllocator,

    pub fn init(gpa: std.mem.Allocator, registry: *const palette.Registry) Keymap {
        var self: Keymap = .{ .gpa = gpa, .arena = .init(gpa) };
        for (registry.commands.items) |command| {
            const text = command.shortcut orelse continue;
            const combo = KeyCombo.parse(text) orelse {
                self.note("atalho padrão inválido em {s}: {s}", .{ command.id, text });
                continue;
            };
            if (self.commandFor(combo)) |other| self.note("atalho padrão {s} repetido em {s} e {s}", .{ text, other, command.id });
            self.set(combo, command.id);
        }
        return self;
    }

    pub fn deinit(self: *Keymap) void {
        self.bindings.deinit(self.gpa);
        for (self.problems.items) |p| self.gpa.free(p);
        self.problems.deinit(self.gpa);
        self.arena.deinit();
    }

    fn note(self: *Keymap, comptime fmt: []const u8, args: anytype) void {
        const text = std.fmt.allocPrint(self.gpa, fmt, args) catch return;
        self.problems.append(self.gpa, text) catch self.gpa.free(text);
    }

    fn set(self: *Keymap, combo: KeyCombo, id: ?[]const u8) void {
        for (self.bindings.items, 0..) |b, i| {
            if (b.combo.eql(combo)) {
                if (id) |new| self.bindings.items[i].id = new else _ = self.bindings.orderedRemove(i);
                return;
            }
        }
        if (id) |new| self.bindings.append(self.gpa, .{ .combo = combo, .id = new }) catch {};
    }

    pub fn applyPreferences(self: *Keymap, preferences: []const Preference, registry: *const palette.Registry) void {
        for (preferences) |p| {
            const combo = KeyCombo.parse(p.keys) orelse {
                self.note("atalho inválido: {s}", .{p.keys});
                continue;
            };
            const id = p.id orelse {
                self.set(combo, null);
                continue;
            };
            const command = registry.find(id) orelse {
                self.note("{s} aponta para um comando que não existe: {s}", .{ p.keys, id });
                continue;
            };
            if (combo.isTerminalControlKey(std.mem.indexOf(u8, p.keys, "cmd") != null)) {
                self.note("{s} recusado: Ctrl+tecla é dos programas no terminal", .{p.keys});
                continue;
            }
            if (self.commandFor(combo)) |replaced| {
                if (!std.mem.eql(u8, replaced, id)) self.note("{s} agora roda {s} no lugar de {s}", .{ p.keys, id, replaced });
            }
            self.set(combo, command.id);
        }
    }

    pub fn commandFor(self: *const Keymap, combo: KeyCombo) ?[]const u8 {
        for (self.bindings.items) |b| if (b.combo.eql(combo)) return b.id;
        return null;
    }

    /// The first combination that runs `id` (what menus and the palette show).
    pub fn comboFor(self: *const Keymap, id: []const u8) ?KeyCombo {
        for (self.bindings.items) |b| if (std.mem.eql(u8, b.id, id)) return b.combo;
        return null;
    }
};

const testing = std.testing;

test "defaults, then preferences that replace, remove and are refused" {
    const Nop = struct {
        fn run(_: ?*anyopaque) void {}
    };
    var registry: palette.Registry = .{ .gpa = testing.allocator };
    defer registry.deinit();
    registry.add(.{ .id = "tab.new", .title = "Nova aba", .shortcut = "cmd+t", .run = Nop.run });
    registry.add(.{ .id = "pane.close", .title = "Fechar painel", .shortcut = "cmd+w", .run = Nop.run });
    var keymap = Keymap.init(testing.allocator, &registry);
    defer keymap.deinit();
    try testing.expectEqualStrings("tab.new", keymap.commandFor(KeyCombo.parse("cmd+t").?).?);
    keymap.applyPreferences(&.{
        .{ .keys = "cmd+shift+t", .id = "tab.new" },
        .{ .keys = "cmd+w", .id = null },
        .{ .keys = "ctrl+b", .id = "tab.new" },
        .{ .keys = "cmd+k", .id = "nothing" },
    }, &registry);
    try testing.expectEqualStrings("tab.new", keymap.commandFor(KeyCombo.parse("cmd+shift+t").?).?);
    try testing.expect(keymap.commandFor(KeyCombo.parse("cmd+w").?) == null);
    try testing.expect(keymap.commandFor(KeyCombo.parse("ctrl+b").?) == null);
    try testing.expectEqual(@as(usize, 2), keymap.problems.items.len);
}
