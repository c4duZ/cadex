//! Reading rules of plan 15 (phases B and C), as the Mac's HighContrast.swift:
//! the accent of the user's over the theme's, the text that goes on top of
//! the active tab, and the high contrast mode (every text at 7:1, WCAG AAA;
//! borders and the accent at 3:1). Pure color math, tested on the Mac too.

const std = @import("std");
const theme = @import("theme.zig");

const Theme = theme.Theme;
const Interface = theme.Interface;

pub const high_contrast_text = 7.0;
pub const high_contrast_border = 3.0;
/// How much of the accent tints the active tab: 0.22 normally (the
/// importers' rule), 0.45 in high contrast so the tab stands out.
pub const accent_tint = 0.22;
pub const high_contrast_tint = 0.45;

const white: u32 = 0xffffff;
const black: u32 = 0x000000;

/// WCAG contrast ratio between two colors, 1 to 21.
pub fn contrast(a: u32, b: u32) f64 {
    const la = theme.luminance(a);
    const lb = theme.luminance(b);
    return (@max(la, lb) + 0.05) / (@min(la, lb) + 0.05);
}

/// `color` moved toward white or black, whichever reads better on
/// `background`, just until the contrast reaches `ratio` (or as far as it
/// goes): ten halvings, as the Mac's RGB.readable.
pub fn readable(color: u32, background: u32, ratio: f64) u32 {
    if (contrast(color, background) >= ratio) return color;
    const target = if (contrast(white, background) >= contrast(black, background)) white else black;
    var low: f64 = 0;
    var high: f64 = 1;
    for (0..10) |_| {
        const middle = (low + high) / 2;
        if (contrast(theme.mix(color, target, middle), background) >= ratio) high = middle else low = middle;
    }
    return theme.mix(color, target, high);
}

/// Black or white, whichever reads better on `fill`.
pub fn textOnTop(fill: u32) u32 {
    return if (contrast(white, fill) >= contrast(black, fill)) white else black;
}

/// The text on the active tab and the selected rows: the theme's text, or
/// black or white when an accent made the fill too close to it.
pub fn textOnTabActive(ui: Interface) u32 {
    return if (contrast(ui.text, ui.tab_active) >= 4.5) ui.text else textOnTop(ui.tab_active);
}

/// The user's accent (appearance.accent, or a space's or tab's color) in
/// place of the theme's; the active tab takes a tint of it.
pub fn withAccent(t: Theme, accent: u32) Theme {
    var out = t;
    out.interface.accent = accent;
    out.interface.tab_active = theme.mix(t.interface.chrome, accent, accent_tint);
    return out;
}

/// The high contrast version of a theme (appearance.highContrast, or
/// Windows' contrast themes).
pub fn withHighContrast(t: Theme) Theme {
    var out = t;
    var ui = out.interface;
    for ([_]u32{ ui.panel, ui.chrome, ui.field }) |background| {
        ui.text = readable(ui.text, background, high_contrast_text);
        ui.secondary_text = readable(ui.secondary_text, background, high_contrast_text);
    }
    ui.panel_border = readable(ui.panel_border, ui.panel, high_contrast_border);
    ui.accent = readable(ui.accent, ui.chrome, high_contrast_border);
    ui.tab_active = theme.mix(ui.chrome, ui.accent, high_contrast_tint);
    out.interface = ui;
    out.terminal.foreground = readable(t.terminal.foreground, t.terminal.background, high_contrast_text);
    return out;
}

/// "#RRGGBB" (appearance.accent's only form), else null.
pub fn parseHex(text: []const u8) ?u32 {
    if (text.len != 7 or text[0] != '#') return null;
    return std.fmt.parseInt(u32, text[1..], 16) catch null;
}

/// The settings' form of a color: "#RRGGBB", upper case as the Mac writes it.
pub fn formatHex(buf: *[7]u8, rgb: u32) []const u8 {
    return std.fmt.bufPrint(buf, "#{X:0>6}", .{rgb & 0xffffff}) catch unreachable;
}

const testing = std.testing;

const sample: Theme = .{
    .name = "sample",
    .dark = true,
    .interface = .{ .chrome = 0x222222, .panel = 0x111111, .panel_border = 0x201e18, .tab_active = 0x534c45, .field = 0x2e2e2e, .text = 0x9a9a9a, .secondary_text = 0x6a6a6a, .accent = 0x404040 },
    .terminal = .{ .background = 0x111111, .foreground = 0x555555, .cursor = 0xffffff, .selection = 0x333333, .ansi = [_]u32{0} ** 16 },
};

test "contrast is 21 between black and white and 1 with itself" {
    try testing.expectApproxEqAbs(@as(f64, 21), contrast(white, black), 1e-9);
    try testing.expectApproxEqAbs(@as(f64, 1), contrast(0x336699, 0x336699), 1e-9);
}

test "readable reaches the ratio, toward the side that contrasts more" {
    const on_dark = readable(0x444444, 0x111111, 7);
    try testing.expect(contrast(on_dark, 0x111111) >= 7);
    try testing.expect(theme.luminance(on_dark) > theme.luminance(0x444444));
    const on_light = readable(0xbbbbbb, 0xffffff, 4.5);
    try testing.expect(contrast(on_light, 0xffffff) >= 4.5);
    try testing.expect(theme.luminance(on_light) < theme.luminance(0xbbbbbb));
    // Already readable: untouched.
    try testing.expectEqual(@as(u32, 0xeeeeee), readable(0xeeeeee, 0x111111, 7));
}

test "readable moves just enough: one step less would not reach" {
    const got = readable(0x444444, 0x111111, 7);
    try testing.expect(contrast(got, 0x111111) < 7.6);
}

test "an accent tints the active tab, and the text on it stays readable" {
    const light_accent = withAccent(sample, 0xffffff);
    try testing.expectEqual(theme.mix(0x222222, 0xffffff, 0.22), light_accent.interface.tab_active);
    const dark_accent = withAccent(sample, 0x000000);
    try testing.expectEqual(@as(u32, 0x9a9a9a), textOnTabActive(dark_accent.interface));
    var pale = sample.interface;
    pale.tab_active = 0xeeeeee;
    try testing.expectEqual(black, textOnTabActive(pale));
    pale.tab_active = 0x101010;
    pale.text = 0x202020;
    try testing.expectEqual(white, textOnTabActive(pale));
}

test "high contrast: every text at 7:1, borders and accent at 3:1" {
    const hc = withHighContrast(sample);
    const ui = hc.interface;
    for ([_]u32{ ui.panel, ui.chrome, ui.field }) |bg| {
        try testing.expect(contrast(ui.text, bg) >= 7);
        try testing.expect(contrast(ui.secondary_text, bg) >= 7);
    }
    try testing.expect(contrast(ui.panel_border, ui.panel) >= 3);
    try testing.expect(contrast(ui.accent, ui.chrome) >= 3);
    try testing.expectEqual(theme.mix(ui.chrome, ui.accent, 0.45), ui.tab_active);
    try testing.expect(contrast(hc.terminal.foreground, hc.terminal.background) >= 7);
}

test "accent hex in and out" {
    try testing.expectEqual(@as(?u32, 0x12abef), parseHex("#12ABef"));
    try testing.expectEqual(@as(?u32, null), parseHex("#12AB"));
    try testing.expectEqual(@as(?u32, null), parseHex("12ABEF0"));
    var buf: [7]u8 = undefined;
    try testing.expectEqualStrings("#0A0B0C", formatHex(&buf, 0x0a0b0c));
}
