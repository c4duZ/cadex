//! The pages WebView2 shows for media (docs/adr/0014-webview2-on-windows.md):
//! the file's folder is mapped to https://media.cadex.example/ (seeking
//! works, which a served stream lacks), and a small page of ours plays it
//! with the system's controls, stopped (docs/spec/media-preview.md). A file
//! the runtime cannot decode posts "error" and the pane says so instead
//! of a black box. A PDF opens straight in Edge's viewer: pages, zoom,
//! Ctrl+F and the password prompt are its own.

const std = @import("std");
const gfx = @import("gfx");
const webview = @import("webview");
const Kind = @import("kind.zig").Kind;

pub const host_name = "media.cadex.example";
pub const prefix = "https://" ++ host_name ++ "/";

/// The address of `path` once its folder is mapped.
pub fn fileUrl(gpa: std.mem.Allocator, path: []const u8) ![]u8 {
    return webview.urls.fileUrl(gpa, prefix, webview.urls.fileName(path));
}

/// "rgb(17,17,17)" for CSS.
pub fn css(buf: []u8, color: gfx.Color) []const u8 {
    const r: u32 = @intFromFloat(@round(std.math.clamp(color.r, 0, 1) * 255));
    const g: u32 = @intFromFloat(@round(std.math.clamp(color.g, 0, 1) * 255));
    const b: u32 = @intFromFloat(@round(std.math.clamp(color.b, 0, 1) * 255));
    return std.fmt.bufPrint(buf, "rgb({d},{d},{d})", .{ r, g, b }) catch "black";
}

/// The page for video, audio or an animated or vector image; null for PDF
/// (navigated to directly).
pub fn html(gpa: std.mem.Allocator, kind: Kind, url: []const u8, background: gfx.Color) !?[]u8 {
    var bg_buf: [32]u8 = undefined;
    const bg = css(&bg_buf, background);
    const element = switch (kind) {
        // preload=metadata: shows the length and first frame, plays nothing.
        .video => try std.fmt.allocPrint(gpa, "<video id=m controls preload=metadata src=\"{s}\"></video>", .{url}),
        .audio => try std.fmt.allocPrint(gpa, "<audio id=m controls preload=metadata src=\"{s}\"></audio>", .{url}),
        .web_image => try std.fmt.allocPrint(gpa, "<img id=m class=checker src=\"{s}\">", .{url}),
        .pdf, .image => return null,
    };
    defer gpa.free(element);
    return try std.fmt.allocPrint(gpa,
        \\<!doctype html><html><head><meta charset="utf-8">
        \\<meta http-equiv="Content-Security-Policy" content="default-src 'none'; media-src {s}; img-src {s}; style-src 'unsafe-inline'; script-src 'unsafe-inline'">
        \\<style>html,body{{margin:0;height:100%;background:{s}}}
        \\body{{display:flex;align-items:center;justify-content:center}}
        \\video,img{{max-width:100%;max-height:100%}} audio{{width:min(640px,90%)}}
        \\.checker{{background:repeating-conic-gradient(rgba(128,128,128,.22) 0 25%,rgba(128,128,128,.1) 0 50%) 0 0/16px 16px}}</style>
        \\</head><body>{s}
        \\<script>document.getElementById('m').addEventListener('error',function(){{chrome.webview.postMessage('error')}});</script>
        \\</body></html>
    , .{ prefix, prefix, bg, element });
}

const testing = std.testing;

test "a video page plays nothing by itself and reports a bad file" {
    const page = (try html(testing.allocator, .video, "https://media.cadex.example/a%20b.mp4", gfx.Color.black)).?;
    defer testing.allocator.free(page);
    try testing.expect(std.mem.indexOf(u8, page, "autoplay") == null);
    try testing.expect(std.mem.indexOf(u8, page, "preload=metadata") != null);
    try testing.expect(std.mem.indexOf(u8, page, "postMessage('error')") != null);
    try testing.expect(std.mem.indexOf(u8, page, "background:rgb(0,0,0)") != null);
}

test "a PDF has no page of ours, and names are encoded" {
    try testing.expect((try html(testing.allocator, .pdf, "x", gfx.Color.black)) == null);
    const url = try fileUrl(testing.allocator, "C:\\docs\\manual 1.pdf");
    defer testing.allocator.free(url);
    try testing.expectEqualStrings("https://media.cadex.example/manual%201.pdf", url);
}

test {
    @import("win32").refAllDeep(@This());
}
