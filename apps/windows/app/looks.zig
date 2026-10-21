//! The looks of plan 15 as the window applies them: the settings' theme
//! choice (a theme per mode, accent, high contrast) to the themes store,
//! the work color of the active tab or space over the accent, the
//! interface's zoom, density and font (read once when Cadex opens, like the
//! language: settings offers "Reopen now"), the terminal's typesetting and
//! minimum contrast, and the shade over panes without focus.

const std = @import("std");
const ui = @import("ui");
const themes = @import("themes");
const terminal = @import("terminal");
const settings = @import("settings");
const App = @import("app.zig").App;
const work_colors = @import("work_colors.zig");

/// The interface's looks as Cadex opened with them.
const Launch = struct {
    zoom: f32 = 1,
    compact: bool = false,
    font: [128]u8 = undefined,
    font_len: usize = 0,
    font_size: f32 = 13,

    fn fontName(self: *const Launch) []const u8 {
        return self.font[0..self.font_len];
    }
};

var launch: Launch = .{};

/// Once, from App.init, before the first frame.
pub fn captureLaunch(s: settings.Settings) void {
    const a = s.appearance;
    launch = .{ .zoom = @floatCast(a.ui_zoom), .compact = std.mem.eql(u8, a.density, "compact"), .font_size = @floatCast(a.ui_font_size) };
    launch.font_len = @min(a.ui_font.len, launch.font.len);
    @memcpy(launch.font[0..launch.font_len], a.ui_font[0..launch.font_len]);
}

/// The saved zoom, density or font differ from the ones on screen: the
/// General page offers to reopen.
pub fn needsRelaunch(s: settings.Settings) bool {
    const a = s.appearance;
    return @as(f32, @floatCast(a.ui_zoom)) != launch.zoom or std.mem.eql(u8, a.density, "compact") != launch.compact or
        @as(f32, @floatCast(a.ui_font_size)) != launch.font_size or !std.mem.eql(u8, a.ui_font, launch.fontName());
}

/// The style the frame draws with: the theme, the work color over its
/// accent, and the interface's zoom, density and font.
pub fn frameStyle(app: *App) ui.Style {
    var t = app.themes.current;
    if (work_colors.current(app)) |rgb| t = themes.contrast.withAccent(t, rgb);
    const window_scale = app.window.scale();
    var style = themes.style(t, window_scale * launch.zoom);
    style.window_scale = window_scale;
    style.density = if (launch.compact) 0.85 else 1;
    style.font_size = launch.font_size;
    if (launch.font_len > 0) style.font_family = launch.fontName();
    return style;
}

/// What the settings ask of the themes store.
pub fn choice(s: settings.Settings) themes.Choice {
    const a = s.appearance;
    const mode: themes.Mode = if (std.mem.eql(u8, a.mode, "dark")) .dark else if (std.mem.eql(u8, a.mode, "light")) .light else .system;
    return .{
        .dark = inUseDark(a),
        .light = inUseLight(a),
        .mode = mode,
        .accent = themes.contrast.parseHex(a.accent),
        .high_contrast = a.high_contrast,
    };
}

pub fn inUseDark(a: anytype) []const u8 {
    return if (a.dark_theme.len == 0) a.theme else a.dark_theme;
}

pub fn inUseLight(a: anytype) []const u8 {
    return if (a.light_theme.len == 0) a.theme else a.light_theme;
}

/// The setting, raised to 7 in high contrast (the Mac's SettingsBridge).
pub fn minContrast(app: *App) f32 {
    const set: f32 = @floatCast(app.settings.current.terminal.minimum_contrast);
    return if (app.themes.isHighContrast()) @max(set, @as(f32, themes.contrast.high_contrast_text)) else set;
}

/// No Mica in high contrast: no transparency (plan 15, phase C).
pub fn vibrancy(app: *App) bool {
    return app.settings.current.appearance.vibrancy and !app.themes.isHighContrast();
}

/// The terminal's font with the settings' typesetting; every caller gets
/// the same one, so it is made only when something changes.
pub fn terminalFont(app: *App) ?*terminal.Font {
    const t = app.settings.current.terminal;
    const typesetting = terminal.Typesetting.init(@floatCast(t.line_height), @floatCast(t.letter_spacing), t.font_features);
    return app.term_font.get(t.font_family, @floatCast(t.font_size), app.window.scale(), typesetting);
}

/// The rest of the settings' looks that live outside the theme.
pub fn applyPanes(app: *App) void {
    app.layout.unfocused_dim = @floatCast(app.settings.current.tabs.unfocused_dim);
}

test {
    @import("win32").refAllDeep(@This());
}
