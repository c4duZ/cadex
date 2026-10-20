//! The shortcuts feature (docs/spec/shortcuts.md): a shortcut is only keys
//! pointing at a command id. The window hands every key press here first,
//! before the terminal or a field; a combination bound to a command that
//! can run now runs it and the key goes no further.

const std = @import("std");
const ui = @import("ui");
const palette = @import("command-palette");

pub const KeyCombo = @import("key_combo.zig").KeyCombo;
pub const Keymap = @import("keymap.zig").Keymap;
pub const Preference = @import("keymap.zig").Preference;

pub const Shortcuts = struct {
    registry: *palette.Registry,
    keymap: Keymap,

    pub fn init(gpa: std.mem.Allocator, registry: *palette.Registry) Shortcuts {
        return .{ .registry = registry, .keymap = .init(gpa, registry) };
    }

    pub fn deinit(self: *Shortcuts) void {
        self.keymap.deinit();
    }

    /// The settings changed: the defaults again, then the user's section.
    pub fn reload(self: *Shortcuts, gpa: std.mem.Allocator, preferences: []const Preference) void {
        self.keymap.deinit();
        self.keymap = .init(gpa, self.registry);
        self.keymap.applyPreferences(preferences, self.registry);
        for (self.keymap.problems.items) |p| std.log.warn("atalhos: {s}", .{p});
    }

    /// Runs the command of `key` if there is one and it can run now.
    pub fn handle(self: *Shortcuts, key: ui.Key) bool {
        const combo: KeyCombo = .{ .vk = key.vk, .ctrl = key.mods.ctrl, .shift = key.mods.shift, .alt = key.mods.alt };
        const id = self.keymap.commandFor(combo) orelse return false;
        // An unavailable command lets the key through (to the terminal).
        return self.registry.run(id);
    }

    /// "Ctrl+Shift+D" for the command, or "" (the palette's rows, menus).
    pub fn label(context: ?*anyopaque, id: []const u8, arena: std.mem.Allocator) []const u8 {
        const self: *Shortcuts = @ptrCast(@alignCast(context.?));
        const combo = self.keymap.comboFor(id) orelse return "";
        var buf: [48]u8 = undefined;
        return arena.dupe(u8, combo.label(&buf)) catch "";
    }
};

test {
    _ = @import("key_combo.zig");
    _ = @import("keymap.zig");
}
