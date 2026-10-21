//! The importers of import.zig, each with a small sample of its format.

const std = @import("std");
const theme = @import("theme.zig");
const import = @import("import.zig");
const file = @import("file.zig");

const testing = std.testing;

fn readSample(arena: *std.heap.ArenaAllocator, path: []const u8, data: []const u8) !theme.Theme {
    var problem: theme.Problem = .{};
    return import.read(arena.allocator(), testing.allocator, path, data, &problem);
}

/// The colors every sample shares: ANSI n is 0x0n0n0n... except the blue.
fn ansiOf(th: theme.Theme, i: usize) u32 {
    return th.terminal.ansi[i];
}

fn itermEntry(out: *std.ArrayList(u8), key: []const u8, r: f64, g: f64, b: f64) !void {
    try out.print(testing.allocator,
        \\  <key>{s}</key>
        \\  <dict>
        \\    <key>Alpha Component</key>
        \\    <real>1</real>
        \\    <key>Blue Component</key>
        \\    <real>{d}</real>
        \\    <key>Color Space</key>
        \\    <string>sRGB</string>
        \\    <key>Green Component</key>
        \\    <real>{d}</real>
        \\    <key>Red Component</key>
        \\    <real>{d}</real>
        \\  </dict>
        \\
    , .{ key, b, g, r });
}

test "iTerm2 .itermcolors: the 16 colors, background, text, cursor; the frame derived" {
    var data: std.ArrayList(u8) = .empty;
    defer data.deinit(testing.allocator);
    try data.appendSlice(testing.allocator, "<?xml version=\"1.0\"?>\n<plist version=\"1.0\">\n<dict>\n");
    for (0..16) |i| {
        var key: [16]u8 = undefined;
        const v = @as(f64, @floatFromInt(i)) / 255;
        try itermEntry(&data, try std.fmt.bufPrint(&key, "Ansi {d} Color", .{i}), v, v, if (i == 4) 1 else v);
    }
    try itermEntry(&data, "Background Color", 0, 0, 0);
    try itermEntry(&data, "Foreground Color", 1, 1, 1);
    try itermEntry(&data, "Cursor Color", 1, 0, 0);
    try data.appendSlice(testing.allocator, "</dict>\n</plist>\n");

    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const th = try readSample(&arena, "C:\\Downloads\\Night Sky.itermcolors", data.items);
    try testing.expectEqualStrings("Night Sky", th.name);
    try testing.expect(th.dark);
    try testing.expectEqual(@as(u32, 0x000000), th.terminal.background);
    try testing.expectEqual(@as(u32, 0xffffff), th.terminal.foreground);
    try testing.expectEqual(@as(u32, 0xff0000), th.terminal.cursor);
    // No Selection Color: a quarter of the way to the text.
    try testing.expectEqual(theme.mix(0x000000, 0xffffff, 0.25), th.terminal.selection);
    try testing.expectEqual(@as(u32, 0x0a0a0a), ansiOf(th, 10));
    try testing.expectEqual(@as(u32, 0x0404ff), th.interface.accent);
    try testing.expectEqual(theme.mix(0x000000, 0xffffff, 0.07), th.interface.chrome);
}

test "Ghostty theme: palette lines, cursor and selection" {
    var data: std.ArrayList(u8) = .empty;
    defer data.deinit(testing.allocator);
    for (0..16) |i| try data.print(testing.allocator, "palette = {d}=#{x:0>2}{x:0>2}{x:0>2}\n", .{ i, i, i, i });
    try data.appendSlice(testing.allocator, "background = fafafa\r\nforeground = #202020\ncursor-color = #ff00ff\nselection-background = #c0c0c0\n# a comment\n");
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const th = try readSample(&arena, "Paper", data.items);
    try testing.expectEqualStrings("Paper", th.name);
    try testing.expect(!th.dark);
    try testing.expectEqual(@as(u32, 0xfafafa), th.terminal.background);
    try testing.expectEqual(@as(u32, 0x202020), th.terminal.foreground);
    try testing.expectEqual(@as(u32, 0xff00ff), th.terminal.cursor);
    try testing.expectEqual(@as(u32, 0xc0c0c0), th.terminal.selection);
    try testing.expectEqual(@as(u32, 0x0f0f0f), ansiOf(th, 15));
}

test "base16 and base24 .yaml: tinted-theming's terminal mapping" {
    const yaml =
        \\system: "base24"
        \\name: "Example Dark"
        \\palette:
        \\  base00: "101010"
        \\  base01: "111111"
        \\  base02: "222222" # selection
        \\  base03: "333333"
        \\  base04: "444444"
        \\  base05: "d0d0d0"
        \\  base06: "e0e0e0"
        \\  base07: "f0f0f0"
        \\  base08: "ff0000"
        \\  base09: "ff8800"
        \\  base0A: "ffff00"
        \\  base0B: "00ff00"
        \\  base0C: "00ffff"
        \\  base0D: "0000ff"
        \\  base0E: "ff00ff"
        \\  base0F: "880000"
        \\  base12: "ff5555"
        \\  base16: "5555ff"
    ;
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const th = try readSample(&arena, "example.yaml", yaml);
    try testing.expectEqualStrings("Example Dark", th.name);
    const want = [16]u32{ 0x101010, 0xff0000, 0x00ff00, 0xffff00, 0x0000ff, 0xff00ff, 0x00ffff, 0xd0d0d0, 0x333333, 0xff5555, 0x00ff00, 0xffff00, 0x5555ff, 0xff00ff, 0x00ffff, 0xf0f0f0 };
    try testing.expectEqual(want, th.terminal.ansi);
    try testing.expectEqual(@as(u32, 0x222222), th.terminal.selection);
    try testing.expectEqual(@as(u32, 0xd0d0d0), th.terminal.cursor);
}

test "a Cadex .json is read as it is; a file of another kind says why not" {
    const text = try file.write(testing.allocator, file.sample);
    defer testing.allocator.free(text);
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const th = try readSample(&arena, "mine.JSON", text);
    try testing.expectEqualStrings(file.sample.name, th.name);
    var problem: theme.Problem = .{};
    try testing.expectError(error.InvalidTheme, import.read(arena.allocator(), testing.allocator, "x.itermcolors", "hello", &problem));
    try testing.expectError(error.InvalidTheme, import.read(arena.allocator(), testing.allocator, "x.conf", "background = 000000", &problem));
    try testing.expectEqualStrings("palette", problem.field);
}
