//! The Material Icon Theme's drawings for files and folders
//! (docs/adr/0011-material-file-icons.md), the same lookup as the Mac's
//! FileIcons.image and folderImage: the whole name, then the extensions
//! from the longest ("x.d.ts" tries "d.ts", then "ts"); a folder by its
//! name, ".github" and "_tests" as "github" and "tests". Not known: null,
//! and the caller draws the Phosphor icon.

const std = @import("std");
const gfx = @import("gfx");
const table = @import("file_icons.zig");

pub const Icon = u8;

fn find(entries: []const table.Entry, key: []const u8) ?Icon {
    const i = std.sort.binarySearch(table.Entry, entries, key, struct {
        fn order(k: []const u8, e: table.Entry) std.math.Order {
            return std.mem.order(u8, k, e[0]);
        }
    }.order) orelse return null;
    return entries[i][1];
}

pub fn forFile(name: []const u8) ?Icon {
    var buf: [256]u8 = undefined;
    if (name.len > buf.len) return null;
    const lower = std.ascii.lowerString(&buf, name);
    if (find(&table.file_names, lower) orelse find(&table.extensions, lower)) |icon| return icon;
    var rest = lower;
    while (std.mem.indexOfScalar(u8, rest, '.')) |dot| {
        rest = rest[dot + 1 ..];
        if (find(&table.extensions, rest)) |icon| return icon;
    }
    return null;
}

pub fn forFolder(name: []const u8) ?Icon {
    var buf: [256]u8 = undefined;
    if (name.len > buf.len) return null;
    const lower = std.ascii.lowerString(&buf, name);
    if (find(&table.folders, lower)) |icon| return icon;
    const bare = std.mem.trimStart(u8, lower, "._");
    return find(&table.folders, bare);
}

/// Draws `icon` `size` pixels square in `r`, from the PNG closest above.
pub fn draw(painter: *gfx.Painter, icon: Icon, size: f32, r: gfx.Rect) bool {
    const bytes = if (size <= 32) table.png32[icon] else table.png64[icon];
    return painter.png(bytes, size, r);
}

/// A file (or folder) by its name: its drawing when the pack has one.
pub fn drawNamed(painter: *gfx.Painter, name: []const u8, folder: bool, size: f32, r: gfx.Rect) bool {
    const icon = (if (folder) forFolder(name) else forFile(name)) orelse return false;
    return draw(painter, icon, size, r);
}

fn nameOf(icon: ?Icon) []const u8 {
    return table.names[icon orelse return ""];
}

test "names, extensions and folders find the pack's drawings" {
    try std.testing.expectEqualStrings("docker", nameOf(forFile("Dockerfile")));
    try std.testing.expectEqualStrings("zig", nameOf(forFile("build.ZIG")));
    try std.testing.expectEqualStrings("folder-src", nameOf(forFolder("src")));
    try std.testing.expectEqualStrings("folder-github", nameOf(forFolder(".github")));
    try std.testing.expect(forFile("no-such-thing.qqq") == null);
    for (table.png32, table.png64) |a, b| try std.testing.expect(a.len > 8 and b.len > 8);
}
