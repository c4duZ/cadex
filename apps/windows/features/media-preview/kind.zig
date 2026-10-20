//! Which viewer a file opens in (docs/spec/media-preview.md), by its
//! extension, the formats of the spec. Windows has no Quick Look: any
//! other file belongs to the editor, which says when it is binary.
//!
//! How each is shown (docs/adr/0014-webview2-on-windows.md): still images
//! natively (WIC into a Direct2D bitmap); GIF (it animates) and SVG (WIC
//! decodes neither) as a page; video, audio and PDF in WebView2, with
//! Edge's player and PDF viewer.

const std = @import("std");

pub const Kind = enum {
    /// PNG, JPEG, WebP, HEIC, TIFF, BMP, ICO: WIC.
    image,
    /// GIF and SVG, in a page.
    web_image,
    video,
    audio,
    pdf,

    pub fn zoomable(self: Kind) bool {
        return self == .image;
    }

    pub fn web(self: Kind) bool {
        return self != .image;
    }
};

const table = [_]struct { Kind, []const []const u8 }{
    .{ .image, &.{ "png", "jpg", "jpeg", "jpe", "webp", "heic", "heif", "tif", "tiff", "bmp", "ico", "jxr" } },
    .{ .web_image, &.{ "gif", "svg" } },
    .{ .video, &.{ "mp4", "mov", "m4v", "webm" } },
    .{ .audio, &.{ "mp3", "wav", "aac", "m4a", "flac", "aiff", "aif", "ogg", "oga", "opus" } },
    .{ .pdf, &.{"pdf"} },
};

/// Null when the file belongs to the editor.
pub fn of(path: []const u8) ?Kind {
    const name_start = if (std.mem.lastIndexOfAny(u8, path, "\\/")) |i| i + 1 else 0;
    const name = path[name_start..];
    const dot = std.mem.lastIndexOfScalar(u8, name, '.') orelse return null;
    if (dot == 0) return null;
    const ext = name[dot + 1 ..];
    for (table) |entry| {
        for (entry[1]) |e| if (std.ascii.eqlIgnoreCase(e, ext)) return entry[0];
    }
    return null;
}

test "the viewer comes from the extension" {
    try std.testing.expectEqual(Kind.image, of("C:\\docs\\cadex-icon.PNG").?);
    try std.testing.expectEqual(Kind.web_image, of("a/b.svg").?);
    try std.testing.expectEqual(Kind.video, of("clip.webm").?);
    try std.testing.expectEqual(Kind.audio, of("x.flac").?);
    try std.testing.expectEqual(Kind.pdf, of("manual.pdf").?);
    try std.testing.expect(of("main.zig") == null);
    try std.testing.expect(of(".png") == null);
    try std.testing.expect(of("C:\\pasta.png\\arquivo") == null);
}

test "only still images zoom here; the rest is a page" {
    try std.testing.expect(Kind.image.zoomable());
    try std.testing.expect(!Kind.pdf.zoomable());
    try std.testing.expect(Kind.video.web());
}

test {
    @import("win32").refAllDeep(@This());
}
