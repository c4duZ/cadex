//! The user's choices, the same fields and defaults as the Mac
//! (apps/macos/features/settings/Settings.swift), so one settings.json
//! serves both. Read forgivingly: a wrong field keeps its default and
//! becomes a problem for the log; the rest of the file still counts.

const std = @import("std");
const Reader = @import("reader.zig").Reader;

pub const Settings = struct {
    general: struct {
        shell: []const u8 = "",
        confirm_close: bool = true,
        confirm_multiline_paste: bool = true,
        /// "beside" or "tab".
        open_files: []const u8 = "beside",
        /// The interface's language, "en" or "pt"; counts when Cadex opens
        /// (docs/adr/0015-english-default-two-languages.md).
        language: []const u8 = "en",
    } = .{},
    terminal: struct {
        /// The Mac's default; a font Windows lacks falls back to Cascadia Mono.
        font_family: []const u8 = "SF Mono",
        font_size: f64 = 13,
        /// "bar", "block" or "underline".
        cursor: []const u8 = "bar",
        cursor_blink: bool = false,
        history_lines: u32 = 10_000,
        option_as_meta: bool = false,
        copy_on_select: bool = false,
        /// The WCAG ratio text keeps against its background; 1 is off (plan 15).
        minimum_contrast: f64 = 1,
        /// Line height as a multiple of the font's.
        line_height: f64 = 1,
        /// Extra space between letters, in points.
        letter_spacing: f64 = 0,
        /// OpenType tags: "calt" and "liga" join ligatures, "-" turns one off.
        font_features: []const []const u8 = &.{},
    } = .{},
    appearance: struct {
        theme: []const u8 = "caffeine",
        /// Another theme for the light or dark mode; empty uses `theme`
        /// (plan 15, phase B).
        light_theme: []const u8 = "",
        dark_theme: []const u8 = "",
        /// "#RRGGBB" in place of the theme's accent; empty keeps the theme's.
        accent: []const u8 = "",
        /// "system", "dark" or "light".
        mode: []const u8 = "system",
        vibrancy: bool = false,
        background_image: ?[]const u8 = null,
        background_opacity: f64 = 0.5,
        background_blur: f64 = 0,
        /// Text at 7:1, stronger borders, no transparency; also on with a
        /// contrast theme of Windows (plan 15, phase C).
        high_contrast: bool = false,
        /// The interface's zoom, density and font, apart from the
        /// terminal's; they count when Cadex opens (plan 15, phase D).
        ui_zoom: f64 = 1,
        /// "normal" or "compact".
        density: []const u8 = "normal",
        /// Empty: the system's (Segoe UI Variable).
        ui_font: []const u8 = "",
        ui_font_size: f64 = 13,
    } = .{},
    tabs: struct {
        /// The shade over the panes without focus, 0 to 0.6 (0.26 measured
        /// against dark themes on 2026-10-19, on the Mac).
        unfocused_dim: f64 = 0.26,
    } = .{},
    explorer: struct {
        show_hidden: bool = true,
        follow_terminal: bool = true,
    } = .{},
    markdown: struct {
        /// "source" or "rendered".
        open_as: []const u8 = "source",
    } = .{},
    /// Keep-awake (docs/spec/power.md).
    power: struct {
        /// What the coffee turns on: "always" or "running".
        mode: []const u8 = "always",
        /// Turned on when Cadex opens.
        on_at_launch: bool = false,
        /// The screen stays on too while the computer is held.
        keep_display_on: bool = false,
    } = .{},
    /// Key combination → command id, or null to turn a default off.
    shortcuts: []const Shortcut = &.{},
};

pub const Shortcut = struct { keys: []const u8, id: ?[]const u8 };

pub const font_sizes = [2]f64{ 8, 32 };
pub const history_range = [2]u32{ 100, 100_000 };
const cursors = [_][]const u8{ "bar", "block", "underline" };
const modes = [_][]const u8{ "system", "dark", "light" };
const markdown_openings = [_][]const u8{ "source", "rendered" };
const file_openings = [_][]const u8{ "beside", "tab" };
const languages = [_][]const u8{ "en", "pt" };
const keep_awake_modes = [_][]const u8{ "always", "running" };
const densities = [_][]const u8{ "normal", "compact" };
pub const contrast_range = [2]f64{ 1, 21 };
pub const line_heights = [2]f64{ 0.8, 2.0 };
pub const letter_spacings = [2]f64{ -1, 4 };
pub const dim_range = [2]f64{ 0, 0.6 };
pub const zoom_range = [2]f64{ 0.8, 1.5 };
pub const ui_font_sizes = [2]f64{ 9, 24 };

fn clamp(v: f64, range: [2]f64) f64 {
    return std.math.clamp(v, range[0], range[1]);
}

/// "calt", "ss01", "-liga": a 4-letter OpenType tag, "-" to turn it off.
pub fn isFontFeature(text: []const u8) bool {
    const tag = if (text.len > 0 and text[0] == '-') text[1..] else text;
    if (tag.len != 4) return false;
    for (tag) |ch| if (!std.ascii.isAlphanumeric(ch)) return false;
    return true;
}

/// "#RRGGBB", the accent's only form.
pub fn isHexColor(text: []const u8) bool {
    if (text.len != 7 or text[0] != '#') return false;
    for (text[1..]) |ch| if (!std.ascii.isHex(ch)) return false;
    return true;
}

/// Reading the file: the settings live in `arena` (strings point into it).
pub const Read = struct {
    settings: Settings,
    problems: []const []const u8,
};

pub fn read(arena: std.mem.Allocator, data: []const u8) Read {
    var r: Reader = .{ .arena = arena };
    var s: Settings = .{};
    const parsed = std.json.parseFromSliceLeaky(std.json.Value, arena, data, .{}) catch {
        r.note("settings.json não é um objeto JSON; valem os padrões", .{});
        return .{ .settings = s, .problems = r.problems.items };
    };
    if (parsed != .object) {
        r.note("settings.json não é um objeto JSON; valem os padrões", .{});
        return .{ .settings = s, .problems = r.problems.items };
    }
    const root = parsed.object;
    if (r.section(root, "general")) |g| {
        if (r.string(g, "general", "shell")) |v| s.general.shell = v;
        if (r.boolean(g, "general", "confirmClose")) |v| s.general.confirm_close = v;
        if (r.boolean(g, "general", "confirmMultilinePaste")) |v| s.general.confirm_multiline_paste = v;
        if (r.choice(g, "general", "openFiles", &file_openings)) |v| s.general.open_files = v;
        if (r.choice(g, "general", "language", &languages)) |v| s.general.language = v;
    }
    if (r.section(root, "terminal")) |t| {
        if (r.string(t, "terminal", "fontFamily")) |v| s.terminal.font_family = v;
        if (r.number(t, "terminal", "fontSize")) |v| s.terminal.font_size = std.math.clamp(v, font_sizes[0], font_sizes[1]);
        if (r.choice(t, "terminal", "cursor", &cursors)) |v| s.terminal.cursor = v;
        if (r.boolean(t, "terminal", "cursorBlink")) |v| s.terminal.cursor_blink = v;
        if (r.number(t, "terminal", "historyLines")) |v| s.terminal.history_lines = @intFromFloat(std.math.clamp(v, history_range[0], history_range[1]));
        if (r.boolean(t, "terminal", "optionAsMeta")) |v| s.terminal.option_as_meta = v;
        if (r.boolean(t, "terminal", "copyOnSelect")) |v| s.terminal.copy_on_select = v;
        readTerminalText(&r, t, &s);
    }
    if (r.section(root, "appearance")) |a| {
        if (r.string(a, "appearance", "theme")) |v| s.appearance.theme = v;
        if (r.choice(a, "appearance", "mode", &modes)) |v| s.appearance.mode = v;
        if (r.boolean(a, "appearance", "vibrancy")) |v| s.appearance.vibrancy = v;
        if (a.get("backgroundImage")) |v| s.appearance.background_image = if (v == .string) v.string else null;
        if (r.number(a, "appearance", "backgroundOpacity")) |v| s.appearance.background_opacity = std.math.clamp(v, 0, 1);
        if (r.number(a, "appearance", "backgroundBlur")) |v| s.appearance.background_blur = std.math.clamp(v, 0, 50);
        readLooks(&r, a, &s);
    }
    if (r.section(root, "tabs")) |t| {
        if (r.number(t, "tabs", "unfocusedDim")) |v| s.tabs.unfocused_dim = clamp(v, dim_range);
    }
    if (r.section(root, "explorer")) |e| {
        if (r.boolean(e, "explorer", "showHidden")) |v| s.explorer.show_hidden = v;
        if (r.boolean(e, "explorer", "followTerminal")) |v| s.explorer.follow_terminal = v;
    }
    if (r.section(root, "markdown")) |m| {
        if (r.choice(m, "markdown", "openAs", &markdown_openings)) |v| s.markdown.open_as = v;
    }
    if (r.section(root, "power")) |p| {
        if (r.choice(p, "power", "mode", &keep_awake_modes)) |v| s.power.mode = v;
        if (r.boolean(p, "power", "onAtLaunch")) |v| s.power.on_at_launch = v;
        if (r.boolean(p, "power", "keepDisplayOn")) |v| s.power.keep_display_on = v;
    }
    if (r.section(root, "shortcuts")) |map| {
        var list: std.ArrayList(Shortcut) = .empty;
        var it = map.iterator();
        while (it.next()) |entry| {
            const value = entry.value_ptr.*;
            switch (value) {
                .null => list.append(arena, .{ .keys = entry.key_ptr.*, .id = null }) catch {},
                .string => |id| list.append(arena, .{ .keys = entry.key_ptr.*, .id = id }) catch {},
                else => r.note("shortcuts.{s}: esperava o id de um comando ou null", .{entry.key_ptr.*}),
            }
        }
        s.shortcuts = list.items;
    }
    return .{ .settings = s, .problems = r.problems.items };
}

/// terminal.minimumContrast, lineHeight, letterSpacing and fontFeatures (plan 15).
fn readTerminalText(r: *Reader, t: std.json.ObjectMap, s: *Settings) void {
    if (r.number(t, "terminal", "minimumContrast")) |v| s.terminal.minimum_contrast = clamp(v, contrast_range);
    if (r.number(t, "terminal", "lineHeight")) |v| s.terminal.line_height = clamp(v, line_heights);
    if (r.number(t, "terminal", "letterSpacing")) |v| s.terminal.letter_spacing = clamp(v, letter_spacings);
    if (r.strings(t, "terminal", "fontFeatures")) |list| {
        var kept: std.ArrayList([]const u8) = .empty;
        for (list) |f| if (isFontFeature(f)) kept.append(r.arena, f) catch {};
        if (kept.items.len != list.len) r.note("terminal.fontFeatures: cada item é uma etiqueta OpenType de 4 letras, como \"calt\" ou \"-liga\"", .{});
        s.terminal.font_features = kept.items;
    }
}

/// The appearance keys of plan 15: themes per mode, accent, high contrast,
/// the interface's zoom, density and font.
fn readLooks(r: *Reader, a: std.json.ObjectMap, s: *Settings) void {
    if (r.string(a, "appearance", "lightTheme")) |v| s.appearance.light_theme = v;
    if (r.string(a, "appearance", "darkTheme")) |v| s.appearance.dark_theme = v;
    if (r.string(a, "appearance", "accent")) |v| {
        if (v.len == 0 or isHexColor(v)) s.appearance.accent = v else r.note("appearance.accent: \"{s}\" não é uma cor #RRGGBB", .{v});
    }
    if (r.boolean(a, "appearance", "highContrast")) |v| s.appearance.high_contrast = v;
    if (r.number(a, "appearance", "uiZoom")) |v| s.appearance.ui_zoom = clamp(v, zoom_range);
    if (r.choice(a, "appearance", "density", &densities)) |v| s.appearance.density = v;
    if (r.string(a, "appearance", "uiFont")) |v| s.appearance.ui_font = v;
    if (r.number(a, "appearance", "uiFontSize")) |v| s.appearance.ui_font_size = clamp(v, ui_font_sizes);
}

/// The file's text, in the Mac's layout (sorted keys, two spaces).
pub fn write(gpa: std.mem.Allocator, s: Settings) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    var j: std.json.Stringify = .{ .writer = &out.writer, .options = .{ .whitespace = .indent_2 } };
    try j.beginObject();
    try j.objectField("appearance");
    try j.beginObject();
    try field(&j, "accent", s.appearance.accent);
    try field(&j, "backgroundBlur", s.appearance.background_blur);
    try field(&j, "backgroundImage", s.appearance.background_image);
    try field(&j, "backgroundOpacity", s.appearance.background_opacity);
    try field(&j, "darkTheme", s.appearance.dark_theme);
    try field(&j, "density", s.appearance.density);
    try field(&j, "highContrast", s.appearance.high_contrast);
    try field(&j, "lightTheme", s.appearance.light_theme);
    try field(&j, "mode", s.appearance.mode);
    try field(&j, "theme", s.appearance.theme);
    try field(&j, "uiFont", s.appearance.ui_font);
    try field(&j, "uiFontSize", s.appearance.ui_font_size);
    try field(&j, "uiZoom", s.appearance.ui_zoom);
    try field(&j, "vibrancy", s.appearance.vibrancy);
    try j.endObject();
    try j.objectField("explorer");
    try j.beginObject();
    try field(&j, "followTerminal", s.explorer.follow_terminal);
    try field(&j, "showHidden", s.explorer.show_hidden);
    try j.endObject();
    try j.objectField("general");
    try j.beginObject();
    try field(&j, "confirmClose", s.general.confirm_close);
    try field(&j, "confirmMultilinePaste", s.general.confirm_multiline_paste);
    try field(&j, "language", s.general.language);
    try field(&j, "openFiles", s.general.open_files);
    try field(&j, "shell", s.general.shell);
    try j.endObject();
    try j.objectField("markdown");
    try j.beginObject();
    try field(&j, "openAs", s.markdown.open_as);
    try j.endObject();
    try j.objectField("power");
    try j.beginObject();
    try field(&j, "keepDisplayOn", s.power.keep_display_on);
    try field(&j, "mode", s.power.mode);
    try field(&j, "onAtLaunch", s.power.on_at_launch);
    try j.endObject();
    try j.objectField("shortcuts");
    try j.beginObject();
    for (s.shortcuts) |sc| try field(&j, sc.keys, sc.id);
    try j.endObject();
    try j.objectField("tabs");
    try j.beginObject();
    try field(&j, "unfocusedDim", s.tabs.unfocused_dim);
    try j.endObject();
    try j.objectField("terminal");
    try j.beginObject();
    try field(&j, "copyOnSelect", s.terminal.copy_on_select);
    try field(&j, "cursor", s.terminal.cursor);
    try field(&j, "cursorBlink", s.terminal.cursor_blink);
    try field(&j, "fontFamily", s.terminal.font_family);
    try field(&j, "fontFeatures", s.terminal.font_features);
    try field(&j, "fontSize", s.terminal.font_size);
    try field(&j, "historyLines", s.terminal.history_lines);
    try field(&j, "letterSpacing", s.terminal.letter_spacing);
    try field(&j, "lineHeight", s.terminal.line_height);
    try field(&j, "minimumContrast", s.terminal.minimum_contrast);
    try field(&j, "optionAsMeta", s.terminal.option_as_meta);
    try j.endObject();
    try j.endObject();
    return out.toOwnedSlice();
}

fn field(j: *std.json.Stringify, name: []const u8, value: anytype) !void {
    try j.objectField(name);
    try j.write(value);
}

test {
    _ = @import("model_test.zig");
}
