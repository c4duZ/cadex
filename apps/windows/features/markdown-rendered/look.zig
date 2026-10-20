//! The rendered note's colors and its page around the core's HTML, the
//! Mac's (apps/macos/features/markdown/MarkdownPreview.swift, and
//! EditorLooks in apps/macos/app/FileOpener.swift): the terminal's palette
//! of the theme, so a note reads like the code next to it; code background
//! the foreground at 6 %, borders the secondary text at 70 %, token colors
//! from the ANSI colors.

const std = @import("std");
const gfx = @import("gfx");

/// CADEX_TOKEN_* run from 1 to 17 (core/include/cadex.h).
pub const token_count = 18;

pub const Look = struct {
    background: gfx.Color,
    foreground: gfx.Color,
    /// Code spans and blocks.
    current_line: gfx.Color,
    /// Rules under headings, table borders, quote bars.
    line_number: gfx.Color,
    font_family: []const u8 = "Cascadia Mono",
    /// By CADEX_TOKEN_*; null uses the foreground.
    tokens: [token_count]?gfx.Color = @splat(null),

    /// From the theme (themes feature, given by the app): the terminal's
    /// background, foreground and 16 ANSI colors, the interface's secondary text.
    pub fn fromTheme(background: u32, foreground: u32, secondary_text: u32, ansi: [16]u32, font_family: []const u8) Look {
        const fg = gfx.Color.rgb(foreground);
        var look: Look = .{
            .background = gfx.Color.rgb(background),
            .foreground = fg,
            .current_line = fg.alpha(0.06),
            .line_number = gfx.Color.rgb(secondary_text).alpha(0.7),
            .font_family = font_family,
        };
        const a = struct {
            fn at(colors: [16]u32, i: usize) gfx.Color {
                return gfx.Color.rgb(colors[i]);
            }
        }.at;
        // The Mac's EditorAppearance.tokens(ansi:foreground:), slot by slot.
        look.tokens[1] = a(ansi, 5); // keyword
        look.tokens[2] = a(ansi, 2); // string
        look.tokens[3] = a(ansi, 3); // number
        look.tokens[4] = a(ansi, 8); // comment
        look.tokens[5] = a(ansi, 4); // function
        look.tokens[6] = a(ansi, 6); // type
        look.tokens[7] = a(ansi, 11); // constant
        look.tokens[8] = a(ansi, 14); // property
        look.tokens[9] = fg; // operator
        look.tokens[10] = fg.alpha(0.7); // punctuation
        look.tokens[11] = a(ansi, 1); // variable
        look.tokens[12] = a(ansi, 1); // tag
        look.tokens[13] = a(ansi, 3); // attribute
        look.tokens[14] = a(ansi, 6); // escape
        look.tokens[15] = a(ansi, 4); // heading
        look.tokens[16] = a(ansi, 12); // link
        look.tokens[17] = a(ansi, 13); // emphasis
        return look;
    }
};

/// "rgba(r,g,b,a)": with the alpha, since the code background is the
/// foreground at 6 % and dropping it painted it almost white (2026-10-19).
fn css(w: *std.Io.Writer, color: ?gfx.Color) !void {
    const col = color orelse return w.writeAll("inherit");
    const r: u32 = @intFromFloat(@round(std.math.clamp(col.r, 0, 1) * 255));
    const g: u32 = @intFromFloat(@round(std.math.clamp(col.g, 0, 1) * 255));
    const b: u32 = @intFromFloat(@round(std.math.clamp(col.b, 0, 1) * 255));
    try w.print("rgba({d},{d},{d},{d:.3})", .{ r, g, b, std.math.clamp(col.a, 0, 1) });
}

/// The whole page for a note's HTML body (cadex_markdown_render). No
/// script runs (JavaScript is off in the view, and the policy says so
/// again); images come only from `origin`, the app's own server of the
/// note's folder, and data: URLs.
pub fn page(gpa: std.mem.Allocator, body: []const u8, look: Look, origin: []const u8) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    const w = &out.writer;
    try w.print(
        \\<!doctype html><html><head><meta charset="utf-8">
        \\<meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src {s} data:; style-src 'unsafe-inline'">
        \\<style>
        \\body {{ font: 14px "Segoe UI Variable Text", "Segoe UI", system-ui, sans-serif; line-height: 1.6; color:
    , .{origin});
    try css(w, look.foreground);
    try w.writeAll(";\n       background: ");
    try css(w, look.background);
    try w.writeAll("; max-width: 860px; margin: 0 auto; padding: 24px 32px; }\na { color: ");
    try css(w, look.tokens[16]);
    try w.writeAll("; } a.wiki { text-decoration-style: dotted; }\nh1, h2 { border-bottom: 1px solid ");
    try css(w, look.line_number);
    try w.print("; padding-bottom: .3em; }}\ncode, pre {{ font-family: \"{s}\", \"Cascadia Mono\", Consolas, monospace; font-size: 13px; }}\ncode {{ background: ", .{look.font_family});
    try css(w, look.current_line);
    try w.writeAll("; padding: .1em .35em; border-radius: 4px; }\npre { background: ");
    try css(w, look.current_line);
    try w.writeAll("; padding: 12px 14px; border-radius: 6px; overflow-x: auto; }\npre code { background: none; padding: 0; }\ntable { border-collapse: collapse; } th, td { border: 1px solid ");
    try css(w, look.line_number);
    try w.writeAll("; padding: 4px 10px; }\nblockquote { margin: 0; padding-left: 1em; border-left: 3px solid ");
    try css(w, look.line_number);
    try w.writeAll("; opacity: .85; }\nimg { max-width: 100%; } li.task { list-style: none; margin-left: -1.3em; }\n");
    for (look.tokens, 0..) |token, i| {
        if (token == null) continue;
        try w.print(".t{d} {{ color: ", .{i});
        try css(w, token);
        try w.writeAll("; }\n");
    }
    try w.writeAll("</style></head><body>");
    try w.writeAll(body);
    try w.writeAll("</body></html>");
    return out.toOwnedSlice();
}

const testing = std.testing;

fn sample() Look {
    var ansi: [16]u32 = undefined;
    for (&ansi, 0..) |*a, i| a.* = @intCast(i * 0x101010);
    return Look.fromTheme(0x111111, 0xeeeeee, 0xb4b4b4, ansi, "Cascadia Code");
}

test "the page has no script and keeps the alpha of the code background" {
    const html = try page(testing.allocator, "<p>oi</p>", sample(), "https://note.cadex.example/");
    defer testing.allocator.free(html);
    try testing.expect(std.mem.indexOf(u8, html, "<script") == null);
    try testing.expect(std.mem.indexOf(u8, html, "default-src 'none'; img-src https://note.cadex.example/ data:") != null);
    try testing.expect(std.mem.indexOf(u8, html, "rgba(238,238,238,0.060)") != null);
    try testing.expect(std.mem.indexOf(u8, html, ".t16 { color: rgba(192,192,192,1.000); }") != null);
    try testing.expect(std.mem.indexOf(u8, html, "<body><p>oi</p></body>") != null);
}

test {
    @import("win32").refAllDeep(@This());
}
