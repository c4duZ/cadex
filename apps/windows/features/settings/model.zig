//! The user's choices, the same fields and defaults as the Mac
//! (apps/macos/features/settings/Settings.swift), so one settings.json
//! serves both. Read forgivingly: a wrong field keeps its default and
//! becomes a problem for the log; the rest of the file still counts.

const std = @import("std");

pub const Settings = struct {
    general: struct {
        shell: []const u8 = "",
        confirm_close: bool = true,
        confirm_multiline_paste: bool = true,
        /// "beside" or "tab".
        open_files: []const u8 = "beside",
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
    } = .{},
    appearance: struct {
        theme: []const u8 = "caffeine",
        /// "system", "dark" or "light".
        mode: []const u8 = "system",
        vibrancy: bool = false,
        background_image: ?[]const u8 = null,
        background_opacity: f64 = 0.5,
        background_blur: f64 = 0,
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
        /// How Cadex opens: "off", "always" or "running".
        keep_awake: []const u8 = "off",
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
const keep_awake_modes = [_][]const u8{ "off", "always", "running" };

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
    }
    if (r.section(root, "terminal")) |t| {
        if (r.string(t, "terminal", "fontFamily")) |v| s.terminal.font_family = v;
        if (r.number(t, "terminal", "fontSize")) |v| s.terminal.font_size = std.math.clamp(v, font_sizes[0], font_sizes[1]);
        if (r.choice(t, "terminal", "cursor", &cursors)) |v| s.terminal.cursor = v;
        if (r.boolean(t, "terminal", "cursorBlink")) |v| s.terminal.cursor_blink = v;
        if (r.number(t, "terminal", "historyLines")) |v| s.terminal.history_lines = @intFromFloat(std.math.clamp(v, history_range[0], history_range[1]));
        if (r.boolean(t, "terminal", "optionAsMeta")) |v| s.terminal.option_as_meta = v;
        if (r.boolean(t, "terminal", "copyOnSelect")) |v| s.terminal.copy_on_select = v;
    }
    if (r.section(root, "appearance")) |a| {
        if (r.string(a, "appearance", "theme")) |v| s.appearance.theme = v;
        if (r.choice(a, "appearance", "mode", &modes)) |v| s.appearance.mode = v;
        if (r.boolean(a, "appearance", "vibrancy")) |v| s.appearance.vibrancy = v;
        if (a.get("backgroundImage")) |v| s.appearance.background_image = if (v == .string) v.string else null;
        if (r.number(a, "appearance", "backgroundOpacity")) |v| s.appearance.background_opacity = std.math.clamp(v, 0, 1);
        if (r.number(a, "appearance", "backgroundBlur")) |v| s.appearance.background_blur = std.math.clamp(v, 0, 50);
    }
    if (r.section(root, "explorer")) |e| {
        if (r.boolean(e, "explorer", "showHidden")) |v| s.explorer.show_hidden = v;
        if (r.boolean(e, "explorer", "followTerminal")) |v| s.explorer.follow_terminal = v;
    }
    if (r.section(root, "markdown")) |m| {
        if (r.choice(m, "markdown", "openAs", &markdown_openings)) |v| s.markdown.open_as = v;
    }
    if (r.section(root, "power")) |p| {
        if (r.choice(p, "power", "keepAwake", &keep_awake_modes)) |v| s.power.keep_awake = v;
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

const Reader = struct {
    arena: std.mem.Allocator,
    problems: std.ArrayList([]const u8) = .empty,

    fn note(self: *Reader, comptime fmt: []const u8, args: anytype) void {
        const text = std.fmt.allocPrint(self.arena, fmt, args) catch return;
        self.problems.append(self.arena, text) catch {};
    }

    fn section(self: *Reader, root: std.json.ObjectMap, key: []const u8) ?std.json.ObjectMap {
        const value = root.get(key) orelse return null;
        if (value != .object) {
            self.note("{s}: esperava uma seção", .{key});
            return null;
        }
        return value.object;
    }

    fn string(self: *Reader, object: std.json.ObjectMap, group: []const u8, key: []const u8) ?[]const u8 {
        const value = object.get(key) orelse return null;
        if (value != .string) {
            self.note("{s}.{s}: esperava um texto", .{ group, key });
            return null;
        }
        return value.string;
    }

    fn boolean(self: *Reader, object: std.json.ObjectMap, group: []const u8, key: []const u8) ?bool {
        const value = object.get(key) orelse return null;
        if (value != .bool) {
            self.note("{s}.{s}: esperava true ou false", .{ group, key });
            return null;
        }
        return value.bool;
    }

    fn number(self: *Reader, object: std.json.ObjectMap, group: []const u8, key: []const u8) ?f64 {
        const value = object.get(key) orelse return null;
        return switch (value) {
            .integer => |i| @floatFromInt(i),
            .float => |f| f,
            else => {
                self.note("{s}.{s}: esperava um número", .{ group, key });
                return null;
            },
        };
    }

    fn choice(self: *Reader, object: std.json.ObjectMap, group: []const u8, key: []const u8, options: []const []const u8) ?[]const u8 {
        const text = self.string(object, group, key) orelse return null;
        for (options) |o| if (std.mem.eql(u8, o, text)) return o;
        self.note("{s}.{s}: \"{s}\" não é uma das opções", .{ group, key, text });
        return null;
    }
};

/// The file's text, in the Mac's layout (sorted keys, two spaces).
pub fn write(gpa: std.mem.Allocator, s: Settings) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    var j: std.json.Stringify = .{ .writer = &out.writer, .options = .{ .whitespace = .indent_2 } };
    try j.beginObject();
    try j.objectField("appearance");
    try j.beginObject();
    try field(&j, "backgroundBlur", s.appearance.background_blur);
    try field(&j, "backgroundImage", s.appearance.background_image);
    try field(&j, "backgroundOpacity", s.appearance.background_opacity);
    try field(&j, "mode", s.appearance.mode);
    try field(&j, "theme", s.appearance.theme);
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
    try field(&j, "openFiles", s.general.open_files);
    try field(&j, "shell", s.general.shell);
    try j.endObject();
    try j.objectField("markdown");
    try j.beginObject();
    try field(&j, "openAs", s.markdown.open_as);
    try j.endObject();
    try j.objectField("power");
    try j.beginObject();
    try field(&j, "keepAwake", s.power.keep_awake);
    try field(&j, "keepDisplayOn", s.power.keep_display_on);
    try j.endObject();
    try j.objectField("shortcuts");
    try j.beginObject();
    for (s.shortcuts) |sc| try field(&j, sc.keys, sc.id);
    try j.endObject();
    try j.objectField("terminal");
    try j.beginObject();
    try field(&j, "copyOnSelect", s.terminal.copy_on_select);
    try field(&j, "cursor", s.terminal.cursor);
    try field(&j, "cursorBlink", s.terminal.cursor_blink);
    try field(&j, "fontFamily", s.terminal.font_family);
    try field(&j, "fontSize", s.terminal.font_size);
    try field(&j, "historyLines", s.terminal.history_lines);
    try field(&j, "optionAsMeta", s.terminal.option_as_meta);
    try j.endObject();
    try j.endObject();
    return out.toOwnedSlice();
}

fn field(j: *std.json.Stringify, name: []const u8, value: anytype) !void {
    try j.objectField(name);
    try j.write(value);
}

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
