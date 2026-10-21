//! The settings file's tests: forgiving reads, the Mac's layout, the keys
//! of plan 15 and their ranges.

const std = @import("std");
const model = @import("model.zig");

const read = model.read;
const write = model.write;
const Settings = model.Settings;
const testing = std.testing;

test "a wrong field keeps its default and the rest still counts" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const got = read(arena.allocator(),
        \\{"terminal": {"fontSize": 99, "cursor": "triangle", "copyOnSelect": true},
        \\ "general": {"openFiles": "tab"}, "shortcuts": {"cmd+shift+t": "tab.new", "cmd+w": null}}
    );
    try testing.expectEqual(@as(f64, 32), got.settings.terminal.font_size);
    try testing.expectEqualStrings("bar", got.settings.terminal.cursor);
    try testing.expect(got.settings.terminal.copy_on_select);
    try testing.expectEqualStrings("tab", got.settings.general.open_files);
    try testing.expectEqual(@as(usize, 2), got.settings.shortcuts.len);
    try testing.expectEqual(@as(usize, 1), got.problems.len);
}

test "written settings read back the same" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var s: Settings = .{};
    s.terminal.font_size = 15;
    s.appearance.mode = "dark";
    const text = try write(arena.allocator(), s);
    const back = read(arena.allocator(), text);
    try testing.expectEqual(@as(f64, 15), back.settings.terminal.font_size);
    try testing.expectEqualStrings("dark", back.settings.appearance.mode);
    try testing.expectEqual(@as(usize, 0), back.problems.len);
}

test "a broken file gives the defaults" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const got = read(arena.allocator(), "{oops");
    try testing.expectEqualStrings("caffeine", got.settings.appearance.theme);
    try testing.expectEqual(@as(usize, 1), got.problems.len);
}

test "plan 15 keys read back, out of range values clamped" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const got = read(arena.allocator(),
        \\{"terminal": {"minimumContrast": 40, "lineHeight": 0.1, "letterSpacing": 9, "fontFeatures": ["calt", "-liga", "toolong"]},
        \\ "appearance": {"accent": "#12AB34", "darkTheme": "nord", "highContrast": true, "uiZoom": 3, "density": "compact", "uiFontSize": 2},
        \\ "tabs": {"unfocusedDim": 0.9}}
    );
    const s = got.settings;
    try testing.expectEqual(@as(f64, 21), s.terminal.minimum_contrast);
    try testing.expectEqual(@as(f64, 0.8), s.terminal.line_height);
    try testing.expectEqual(@as(f64, 4), s.terminal.letter_spacing);
    try testing.expectEqual(@as(usize, 2), s.terminal.font_features.len);
    try testing.expectEqualStrings("-liga", s.terminal.font_features[1]);
    try testing.expectEqualStrings("#12AB34", s.appearance.accent);
    try testing.expectEqualStrings("nord", s.appearance.dark_theme);
    try testing.expect(s.appearance.high_contrast);
    try testing.expectEqual(@as(f64, 1.5), s.appearance.ui_zoom);
    try testing.expectEqualStrings("compact", s.appearance.density);
    try testing.expectEqual(@as(f64, 9), s.appearance.ui_font_size);
    try testing.expectEqual(@as(f64, 0.6), s.tabs.unfocused_dim);
    // The bad feature is the only problem.
    try testing.expectEqual(@as(usize, 1), got.problems.len);
}

test "a bad accent keeps the theme's and says why" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const got = read(arena.allocator(), "{\"appearance\": {\"accent\": \"red\"}}");
    try testing.expectEqualStrings("", got.settings.appearance.accent);
    try testing.expectEqual(@as(usize, 1), got.problems.len);
}

test "plan 15 keys written read back the same" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var s: Settings = .{};
    s.terminal.font_features = &.{ "calt", "liga", "ss01" };
    s.terminal.line_height = 1.25;
    s.appearance.light_theme = "github-light";
    s.appearance.accent = "#FF8800";
    s.appearance.ui_font = "Inter";
    s.tabs.unfocused_dim = 0.1;
    const back = read(arena.allocator(), try write(arena.allocator(), s)).settings;
    try testing.expectEqual(@as(usize, 3), back.terminal.font_features.len);
    try testing.expectEqual(@as(f64, 1.25), back.terminal.line_height);
    try testing.expectEqualStrings("github-light", back.appearance.light_theme);
    try testing.expectEqualStrings("#FF8800", back.appearance.accent);
    try testing.expectEqualStrings("Inter", back.appearance.ui_font);
    try testing.expectEqual(@as(f64, 0.1), back.tabs.unfocused_dim);
}
