//! A fenced code block as HTML, colored by the editor feature's tree-sitter
//! (through its entry point): each span is `<span class="tN">`, N being the
//! token kind; the app's stylesheet gives the colors.

const std = @import("std");
const editor = @import("../editor/editor.zig");
const html = @import("html.zig");

/// Fence names that are not file extensions.
const names = std.StaticStringMap([]const u8).initComptime(.{
    .{ "javascript", "js" }, .{ "typescript", "ts" }, .{ "python", "py" }, .{ "rust", "rs" },
    .{ "shell", "sh" },      .{ "console", "sh" },    .{ "c++", "cpp" },   .{ "markdown", "md" },
    .{ "golang", "go" },     .{ "yml", "yaml" },
});

pub fn write(gpa: std.mem.Allocator, out: *std.ArrayList(u8), lang: []const u8, text: []const u8) !void {
    try out.appendSlice(gpa, "<pre><code");
    if (lang.len > 0) {
        try out.appendSlice(gpa, " class=\"language-");
        try html.escape(gpa, out, lang);
        try out.append(gpa, '"');
    }
    try out.append(gpa, '>');
    try colored(gpa, out, lang, text);
    try out.appendSlice(gpa, "</code></pre>\n");
}

fn colored(gpa: std.mem.Allocator, out: *std.ArrayList(u8), lang: []const u8, text: []const u8) !void {
    var lower: [32]u8 = undefined;
    const key = if (lang.len <= lower.len) std.ascii.lowerString(&lower, lang) else "";
    var name_buf: [48]u8 = undefined;
    const name = std.fmt.bufPrint(&name_buf, "code.{s}", .{names.get(key) orelse key}) catch "code";
    const doc = editor.Document.open(gpa, name, text, .utf8) catch return html.escape(gpa, out, text);
    defer doc.close();
    const spans = doc.highlights(gpa, 0, @intCast(text.len)) catch return html.escape(gpa, out, text);
    defer gpa.free(spans);
    var at: usize = 0;
    for (spans) |s| {
        try html.escape(gpa, out, text[at..s.start]);
        var open: [24]u8 = undefined;
        try out.appendSlice(gpa, try std.fmt.bufPrint(&open, "<span class=\"t{d}\">", .{@intFromEnum(s.kind)}));
        try html.escape(gpa, out, text[s.start..s.end]);
        try out.appendSlice(gpa, "</span>");
        at = s.end;
    }
    try html.escape(gpa, out, text[at..]);
}
