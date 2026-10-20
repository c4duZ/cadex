//! Which keys reach the core as keys and which as text. Named keys
//! (arrows, F1–F12, Enter, Tab, Backspace, Esc, Home, End...) and Ctrl or
//! Alt combinations go to cadex_terminal_key, which encodes them in the
//! format the program asked for (application cursor keys, kitty). Plain
//! text comes from WM_CHAR, after the keyboard layout and dead keys (ABNT2
//! accents, AltGr), and is written as typed.

const std = @import("std");
const w = @import("win32");
const cadex = @import("cadex");
const ui = @import("ui");

const c = w.c;

pub fn named(vk: u16) ?u16 {
    return switch (vk) {
        c.VK_RETURN => cadex.CADEX_KEY_ENTER,
        c.VK_TAB => cadex.CADEX_KEY_TAB,
        c.VK_BACK => cadex.CADEX_KEY_BACKSPACE,
        c.VK_ESCAPE => cadex.CADEX_KEY_ESCAPE,
        c.VK_DELETE => cadex.CADEX_KEY_DELETE,
        c.VK_INSERT => cadex.CADEX_KEY_INSERT,
        c.VK_HOME => cadex.CADEX_KEY_HOME,
        c.VK_END => cadex.CADEX_KEY_END,
        c.VK_PRIOR => cadex.CADEX_KEY_PAGE_UP,
        c.VK_NEXT => cadex.CADEX_KEY_PAGE_DOWN,
        c.VK_UP => cadex.CADEX_KEY_UP,
        c.VK_DOWN => cadex.CADEX_KEY_DOWN,
        c.VK_LEFT => cadex.CADEX_KEY_LEFT,
        c.VK_RIGHT => cadex.CADEX_KEY_RIGHT,
        c.VK_F1...c.VK_F12 => @intCast(cadex.CADEX_KEY_F1 + (vk - @as(u16, c.VK_F1))),
        else => null,
    };
}

pub fn modsOf(m: ui.Mods) u8 {
    var bits: u8 = 0;
    if (m.shift) bits |= cadex.CADEX_MOD_SHIFT;
    if (m.ctrl) bits |= cadex.CADEX_MOD_CTRL;
    if (m.alt) bits |= cadex.CADEX_MOD_ALT;
    return bits;
}

/// What a key types with Shift as held but without Ctrl and Alt, and the
/// key without Shift: the core needs both for Ctrl+Shift+A or Alt+B. Asks
/// the layout without touching its dead-key state (flag 4, Windows 10+),
/// so an accent typed next still composes.
pub const Typed = struct { text: [8]u8 = undefined, len: usize = 0, unshifted: u32 = 0 };

pub fn typed(vk: u16, scan: u16, shift: bool) Typed {
    var out: Typed = .{};
    var state = std.mem.zeroes([256]u8);
    if (shift) state[c.VK_SHIFT] = 0x80;
    var wide: [4]u16 = undefined;
    const layout = c.GetKeyboardLayout(0);
    const n = c.ToUnicodeEx(vk, scan, &state, &wide, wide.len, 4, layout);
    if (n > 0) {
        out.len = std.unicode.wtf16LeToWtf8(&out.text, wide[0..@intCast(n)]);
    }
    var plain = std.mem.zeroes([256]u8);
    var plain_wide: [4]u16 = undefined;
    const m = c.ToUnicodeEx(vk, scan, &plain, &plain_wide, plain_wide.len, 4, layout);
    if (m == 1) out.unshifted = plain_wide[0];
    return out;
}

/// AltGr reaches Windows apps as Ctrl+Alt: with it held, the key types a
/// character (@ on ABNT2 is AltGr+2) and must come as text, not a combo.
pub fn isAltGr(m: ui.Mods) bool {
    return m.ctrl and m.alt and (c.GetKeyState(c.VK_RMENU) & @as(c_short, @bitCast(@as(u16, 0x8000)))) != 0;
}

test {
    std.testing.refAllDecls(@This());
}
