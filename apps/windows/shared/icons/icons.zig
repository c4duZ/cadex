//! The app's icons (docs/adr/0008-phosphor-icons.md): Phosphor glyphs by
//! name (phosphor.zig, generated from the Mac's list), the font itself,
//! embedded from the same file the Mac ships, and the icon and color of a
//! file by its name, the same groups as apps/macos/shared/icons/FileIcons.swift.

const std = @import("std");
const gfx = @import("gfx");

pub const phosphor = @import("phosphor.zig");
/// The Material Icon Theme for files and folders that it knows (ADR 0011).
pub const material = @import("material.zig");

/// Phosphor-Regular.ttf, loaded from memory by gfx.Fonts.
pub const font_bytes = @embedFile("phosphor_font");

pub fn forFileNamed(name: []const u8) u21 {
    var lower_buf: [256]u8 = undefined;
    const lower = std.ascii.lowerString(lower_buf[0..@min(name.len, lower_buf.len)], name[0..@min(name.len, lower_buf.len)]);
    for (by_name) |entry| if (std.mem.eql(u8, entry[0], lower)) return entry[1];
    const dot = std.mem.lastIndexOfScalar(u8, lower, '.') orelse return phosphor.file;
    if (dot == 0) return phosphor.file;
    const ext = lower[dot + 1 ..];
    for (groups) |group| {
        for (group.extensions) |e| if (std.mem.eql(u8, e, ext)) return group.icon;
    }
    return phosphor.file;
}

const by_name = [_]struct { []const u8, u21 }{
    .{ "makefile", phosphor.file_code },     .{ "dockerfile", phosphor.file_code },
    .{ "license", phosphor.file_text },      .{ "notice", phosphor.file_text },
    .{ ".gitignore", phosphor.brackets_curly }, .{ ".env", phosphor.brackets_curly },
    .{ ".editorconfig", phosphor.brackets_curly },
};

const Group = struct { icon: u21, extensions: []const []const u8 };

const groups = [_]Group{
    .{ .icon = phosphor.file_code, .extensions = &.{
        "zig", "swift", "c",    "h",    "m",       "mm",     "cpp", "hpp",   "cc",    "rs",  "go",     "py",
        "rb",  "js",    "mjs",  "cjs",  "ts",      "tsx",    "jsx", "java",  "kt",    "cs",  "php",    "lua",
        "sh",  "zsh",   "bash", "fish", "sql",     "html",   "css", "scss",  "vue",   "svelte", "ex",  "exs",
        "dart", "scala", "metal", "zon", "modulemap", "gradle", "pl", "r", "ps1", "psm1", "bat", "cmd",
    } },
    .{ .icon = phosphor.file_md, .extensions = &.{ "md", "markdown", "mdx" } },
    .{ .icon = phosphor.file_text, .extensions = &.{ "txt", "rtf", "log", "csv", "tsv" } },
    .{ .icon = phosphor.brackets_curly, .extensions = &.{
        "json", "jsonc", "yaml", "yml", "toml", "ini", "xml", "plist", "lock", "conf", "cfg", "env", "properties",
    } },
    .{ .icon = phosphor.file_image, .extensions = &.{
        "png", "jpg", "jpeg", "gif", "webp", "heic", "bmp", "tiff", "tif", "svg", "ico", "icns", "ppm",
    } },
    .{ .icon = phosphor.file_video, .extensions = &.{ "mp4", "mov", "m4v", "webm", "mkv", "avi" } },
    .{ .icon = phosphor.file_audio, .extensions = &.{ "mp3", "wav", "aac", "m4a", "flac", "ogg", "aiff" } },
    .{ .icon = phosphor.file_pdf, .extensions = &.{"pdf"} },
    .{ .icon = phosphor.file_archive, .extensions = &.{ "zip", "tar", "gz", "tgz", "bz2", "xz", "7z", "rar", "dmg", "zst" } },
};

/// The color of a file's icon by type (CodeEdit's groups, MIT, see NOTICE),
/// or null for the tree's gray.
pub fn colorForFileNamed(name: []const u8) ?gfx.Color {
    var lower_buf: [256]u8 = undefined;
    const lower = std.ascii.lowerString(lower_buf[0..@min(name.len, lower_buf.len)], name[0..@min(name.len, lower_buf.len)]);
    if (std.mem.eql(u8, lower, "makefile")) return gfx.Color.rgb(0xef5350);
    if (std.mem.eql(u8, lower, "license")) return amber;
    const dot = std.mem.lastIndexOfScalar(u8, lower, '.') orelse return null;
    if (dot == 0) return null;
    const ext = lower[dot + 1 ..];
    for (colors) |group| {
        for (group.extensions) |e| if (std.mem.eql(u8, e, ext)) return group.color;
    }
    return null;
}

const amber = gfx.Color.rgb(0xfab821);
const scarlet = gfx.Color.rgb(0xf0544a);

const ColorGroup = struct { color: gfx.Color, extensions: []const []const u8 };

/// The macOS system colors of the Mac's table, as their sRGB values.
const colors = [_]ColorGroup{
    .{ .color = gfx.Color.rgb(0xff9f0a), .extensions = &.{ "swift", "html", "rs" } },
    .{ .color = gfx.Color.rgb(0x0a84ff), .extensions = &.{ "java", "jpg", "jpeg", "png", "svg", "ts", "md", "markdown", "mdx" } },
    .{ .color = gfx.Color.rgb(0x40c8e0), .extensions = &.{ "css", "scss" } },
    .{ .color = amber, .extensions = &.{ "js", "mjs", "cjs", "py", "entitlements", "zig", "zon" } },
    .{ .color = scarlet, .extensions = &.{ "json", "jsonc", "rb", "strings", "yml", "yaml", "toml" } },
    .{ .color = gfx.Color.rgb(0x64d2ff), .extensions = &.{ "jsx", "tsx" } },
    .{ .color = gfx.Color.rgb(0xbf5af2), .extensions = &.{ "c", "cpp", "cc", "hpp" } },
    .{ .color = gfx.Color.rgb(0x41b883), .extensions = &.{"vue"} },
    .{ .color = gfx.Color.rgb(0xaa0822), .extensions = &.{"h"} },
    .{ .color = gfx.Color.rgb(0x734dbf), .extensions = &.{ "m", "mm" } },
    .{ .color = gfx.Color.rgb(0x05acc1), .extensions = &.{"go"} },
    .{ .color = gfx.Color.rgb(0xec407a), .extensions = &.{ "sum", "mod" } },
};

test "file icons by name and extension" {
    try std.testing.expectEqual(phosphor.file_code, forFileNamed("main.ZIG"));
    try std.testing.expectEqual(phosphor.file_md, forFileNamed("README.md"));
    try std.testing.expectEqual(phosphor.file_code, forFileNamed("Makefile"));
    try std.testing.expectEqual(phosphor.file, forFileNamed(".hidden"));
    try std.testing.expect(colorForFileNamed("a.zig") != null);
    try std.testing.expect(colorForFileNamed("a.unknown") == null);
}

test {
    @import("win32").refAllDeep(@This());
}
