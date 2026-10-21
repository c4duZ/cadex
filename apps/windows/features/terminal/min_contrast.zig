//! The terminal's minimum contrast (terminal.minimumContrast, plan 15
//! phase C): text a program colors too close to its cell's background moves
//! toward white or black, whichever reads better there, just far enough
//! (8 halvings). The Mac does it in its vertex shader
//! (TerminalShaders.swift); the Windows terminal draws with Direct2D glyph
//! runs, so the same math runs here once per glyph, with the last answer
//! kept (a run of text is mostly one pair of colors).

const std = @import("std");

pub const Rgb = [3]f32;

fn linear(ch: f32) f32 {
    return if (ch <= 0.04045) ch / 12.92 else std.math.pow(f32, (ch + 0.055) / 1.055, 2.4);
}

pub fn luminance(c: Rgb) f32 {
    return 0.2126 * linear(c[0]) + 0.7152 * linear(c[1]) + 0.0722 * linear(c[2]);
}

fn ratio(a: f32, b: f32) f32 {
    return (@max(a, b) + 0.05) / (@min(a, b) + 0.05);
}

pub fn fromHex(rgb: u32) Rgb {
    return .{
        @as(f32, @floatFromInt((rgb >> 16) & 0xff)) / 255,
        @as(f32, @floatFromInt((rgb >> 8) & 0xff)) / 255,
        @as(f32, @floatFromInt(rgb & 0xff)) / 255,
    };
}

fn mix(a: Rgb, b: Rgb, t: f32) Rgb {
    return .{ a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t };
}

/// `fg` as it reads on `bg` with at least `minimum` (a WCAG ratio).
pub fn contrasted(fg: Rgb, bg: Rgb, minimum: f32) Rgb {
    const lb = luminance(bg);
    if (ratio(luminance(fg), lb) >= minimum) return fg;
    const target: Rgb = if (ratio(1, lb) >= ratio(0, lb)) .{ 1, 1, 1 } else .{ 0, 0, 0 };
    var lo: f32 = 0;
    var hi: f32 = 1;
    for (0..8) |_| {
        const mid = (lo + hi) * 0.5;
        if (ratio(luminance(mix(fg, target, mid)), lb) >= minimum) hi = mid else lo = mid;
    }
    return mix(fg, target, hi);
}

/// The last pair of colors and its answer.
pub const Cache = struct {
    minimum: f32,
    fg: u32 = 0,
    bg: u32 = 0,
    out: Rgb = .{ 0, 0, 0 },
    valid: bool = false,

    pub fn get(self: *Cache, fg: u32, bg: u32) Rgb {
        if (self.valid and self.fg == fg and self.bg == bg) return self.out;
        self.* = .{ .minimum = self.minimum, .fg = fg, .bg = bg, .valid = true, .out = contrasted(fromHex(fg), fromHex(bg), self.minimum) };
        return self.out;
    }
};

const testing = std.testing;

test "text too close to its background moves until it reads" {
    const bg = fromHex(0x202020);
    const out = contrasted(fromHex(0x303030), bg, 4.5);
    try testing.expect(ratio(luminance(out), luminance(bg)) >= 4.5);
    try testing.expect(luminance(out) > luminance(fromHex(0x303030)));
    const on_light = contrasted(fromHex(0xdddddd), fromHex(0xffffff), 7);
    try testing.expect(ratio(luminance(on_light), 1) >= 7);
}

test "readable text and a minimum of 1 leave the color alone" {
    const fg = fromHex(0xeeeeee);
    try testing.expectEqual(fg, contrasted(fg, fromHex(0x111111), 4.5));
    try testing.expectEqual(fromHex(0x222222), contrasted(fromHex(0x222222), fromHex(0x202020), 1));
}

test "the cache answers the same pair without computing again" {
    var cache: Cache = .{ .minimum = 7 };
    const a = cache.get(0x404040, 0x101010);
    try testing.expectEqual(a, cache.get(0x404040, 0x101010));
    try testing.expect(cache.get(0xffffff, 0x101010)[0] == 1);
}
