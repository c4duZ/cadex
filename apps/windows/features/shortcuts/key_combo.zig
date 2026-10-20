//! A key combination on Windows: a virtual key and Ctrl, Shift, Alt. It is
//! written in the Mac's notation ("cmd+shift+d"), so one settings.json
//! serves both systems (docs/spec/shortcuts.md):
//! - "cmd" is Ctrl+Shift: Ctrl alone with a letter belongs to the programs
//!   in the terminal, and Windows Terminal uses Ctrl+Shift the same way;
//! - "cmd" with "shift", "opt" or "ctrl" is Ctrl+Shift+Alt;
//! - "ctrl", "shift", "opt"/"alt" without "cmd" are those keys as written.
//! A symbol key follows the keyboard layout ("cmd+[" is wherever [ is, on
//! ABNT2 too), as the Mac's menus do.

const std = @import("std");
const w = @import("win32");
const strings = @import("strings");
const c = w.c;

pub const KeyCombo = struct {
    vk: u16,
    ctrl: bool = false,
    shift: bool = false,
    alt: bool = false,

    pub fn eql(a: KeyCombo, b: KeyCombo) bool {
        return a.vk == b.vk and a.ctrl == b.ctrl and a.shift == b.shift and a.alt == b.alt;
    }

    /// Parses "cmd+shift+t", "ctrl+tab", "cmd+opt+left", "cmd++". Null when
    /// malformed or the key has no place on this keyboard.
    pub fn parse(text: []const u8) ?KeyCombo {
        var buf: [64]u8 = undefined;
        if (text.len == 0 or text.len > buf.len) return null;
        const lower = std.ascii.lowerString(&buf, text);
        var key: []const u8 = undefined;
        var mods: []const u8 = undefined;
        if (std.mem.endsWith(u8, lower, "++")) {
            key = "+";
            mods = lower[0 .. lower.len - 1];
        } else {
            const plus = std.mem.lastIndexOfScalar(u8, lower, '+');
            key = if (plus) |p| lower[p + 1 ..] else lower;
            mods = if (plus) |p| lower[0 .. p + 1] else "";
        }
        if (key.len == 0) return null;
        var cmd = false;
        var shift = false;
        var alt = false;
        var ctrl = false;
        var it = std.mem.tokenizeScalar(u8, mods, '+');
        while (it.next()) |m| {
            if (eqlAny(m, &.{ "cmd", "command" })) cmd = true else if (std.mem.eql(u8, m, "shift")) shift = true else if (eqlAny(m, &.{ "opt", "option", "alt" })) alt = true else if (eqlAny(m, &.{ "ctrl", "control" })) ctrl = true else return null;
        }
        var combo = keyOf(key) orelse return null;
        if (cmd) {
            combo.ctrl = true;
            combo.shift = true;
            if (shift or alt or ctrl) combo.alt = true;
        }
        combo.ctrl = combo.ctrl or ctrl;
        combo.shift = combo.shift or shift;
        combo.alt = combo.alt or alt;
        return combo;
    }

    fn eqlAny(a: []const u8, options: []const []const u8) bool {
        for (options) |o| if (std.mem.eql(u8, a, o)) return true;
        return false;
    }

    /// The virtual key of a key name or character; a character that needs
    /// Shift on this layout carries it ("+" on US is Shift+=).
    fn keyOf(key: []const u8) ?KeyCombo {
        for (named) |n| if (std.mem.eql(u8, n.name, key)) return .{ .vk = n.vk };
        if (key.len >= 2 and key[0] == 'f') {
            const n = std.fmt.parseInt(u8, key[1..], 10) catch return null;
            if (n >= 1 and n <= 12) return .{ .vk = @intCast(c.VK_F1 + n - 1) };
            return null;
        }
        const cp = std.unicode.utf8Decode(key) catch return null;
        if (cp >= 'a' and cp <= 'z') return .{ .vk = @intCast(cp - 'a' + 'A') };
        if (cp >= '0' and cp <= '9') return .{ .vk = @intCast(cp) };
        if (cp > 0xFFFF) return null;
        const scan = c.VkKeyScanW(@intCast(cp));
        if (scan == -1) return null;
        const bits: u16 = @bitCast(scan);
        return .{ .vk = bits & 0xFF, .shift = bits & 0x100 != 0, .ctrl = bits & 0x200 != 0, .alt = bits & 0x400 != 0 };
    }

    /// "Ctrl+Shift+D", as Windows menus write it.
    pub fn label(self: KeyCombo, out: []u8) []const u8 {
        var stream: std.Io.Writer = .fixed(out);
        if (self.ctrl) stream.writeAll("Ctrl+") catch {};
        if (self.shift) stream.writeAll("Shift+") catch {};
        if (self.alt) stream.writeAll("Alt+") catch {};
        stream.writeAll(keyName(self.vk)) catch {};
        return stream.buffered();
    }

    /// Ctrl with a letter or symbol and nothing else but Shift: what the
    /// programs in the terminal use. Only "cmd" (Ctrl+Shift) may take these
    /// letters; a "ctrl+b" in the settings is refused.
    pub fn isTerminalControlKey(self: KeyCombo, from_cmd: bool) bool {
        if (from_cmd or !self.ctrl or self.alt) return false;
        return (self.vk >= 'A' and self.vk <= 'Z') or self.vk >= c.VK_OEM_1;
    }
};

const Named = struct { name: []const u8, vk: u16 };

/// The Mac's named keys; "delete" is the Mac's (Backspace here).
const named = [_]Named{
    .{ .name = "left", .vk = c.VK_LEFT },        .{ .name = "right", .vk = c.VK_RIGHT },
    .{ .name = "up", .vk = c.VK_UP },            .{ .name = "down", .vk = c.VK_DOWN },
    .{ .name = "tab", .vk = c.VK_TAB },          .{ .name = "return", .vk = c.VK_RETURN },
    .{ .name = "enter", .vk = c.VK_RETURN },     .{ .name = "escape", .vk = c.VK_ESCAPE },
    .{ .name = "esc", .vk = c.VK_ESCAPE },       .{ .name = "delete", .vk = c.VK_BACK },
    .{ .name = "backspace", .vk = c.VK_BACK },   .{ .name = "forwarddelete", .vk = c.VK_DELETE },
    .{ .name = "space", .vk = c.VK_SPACE },      .{ .name = "home", .vk = c.VK_HOME },
    .{ .name = "end", .vk = c.VK_END },          .{ .name = "pageup", .vk = c.VK_PRIOR },
    .{ .name = "pagedown", .vk = c.VK_NEXT },
};

fn keyName(vk: u16) []const u8 {
    return switch (vk) {
        c.VK_LEFT => "←",
        c.VK_RIGHT => "→",
        c.VK_UP => "↑",
        c.VK_DOWN => "↓",
        c.VK_TAB => "Tab",
        c.VK_RETURN => "Enter",
        c.VK_ESCAPE => "Esc",
        c.VK_BACK => "Backspace",
        c.VK_DELETE => "Del",
        c.VK_SPACE => strings.t("Space", "Espaço"),
        c.VK_HOME => "Home",
        c.VK_END => "End",
        c.VK_PRIOR => "PgUp",
        c.VK_NEXT => "PgDn",
        'A'...'Z', '0'...'9' => &[_]u8{@intCast(vk)},
        c.VK_F1...c.VK_F12 => fkeys[vk - @as(u16, c.VK_F1)],
        else => oemName(vk),
    };
}

const fkeys = [_][]const u8{ "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12" };

/// The character a symbol key types on this layout, for its label.
fn oemName(vk: u16) []const u8 {
    const State = struct {
        var buf: [8]u8 = undefined;
    };
    const ch = c.MapVirtualKeyW(vk, c.MAPVK_VK_TO_CHAR) & 0x7FFF;
    if (ch == 0) return "?";
    const n = std.unicode.utf8Encode(@intCast(ch), &State.buf) catch return "?";
    return State.buf[0..n];
}

const testing = std.testing;

test "cmd becomes Ctrl+Shift, and with Shift or Option also Alt" {
    const t = KeyCombo.parse("cmd+t").?;
    try testing.expect(t.ctrl and t.shift and !t.alt and t.vk == 'T');
    const d = KeyCombo.parse("cmd+shift+d").?;
    try testing.expect(d.ctrl and d.shift and d.alt and d.vk == 'D');
    const tab = KeyCombo.parse("ctrl+tab").?;
    try testing.expect(tab.ctrl and !tab.shift and tab.vk == c.VK_TAB);
    const left = KeyCombo.parse("cmd+opt+left").?;
    try testing.expect(left.alt and left.vk == c.VK_LEFT);
    try testing.expect(KeyCombo.parse("cmd+") == null);
    try testing.expect(KeyCombo.parse("hyper+t") == null);
    var buf: [32]u8 = undefined;
    try testing.expectEqualStrings("Ctrl+Shift+Alt+D", d.label(&buf));
}

test "Ctrl with a letter is the terminal's unless it came from cmd" {
    try testing.expect(KeyCombo.parse("ctrl+b").?.isTerminalControlKey(false));
    try testing.expect(!KeyCombo.parse("ctrl+tab").?.isTerminalControlKey(false));
    try testing.expect(!KeyCombo.parse("cmd+b").?.isTerminalControlKey(true));
}
