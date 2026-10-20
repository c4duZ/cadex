//! Where a file opens (the Mac's FileOpener): media by its type, Markdown
//! as code or rendered (markdown.openAs), the rest in the code view, and in
//! which pane: beside the focused one or in a new tab (general.openFiles),
//! or as the caller chose. Until a viewer exists for a kind, the system's
//! app opens it.

const std = @import("std");
const w = @import("win32");
const tabs = @import("tabs");
const App = @import("app.zig").App;

pub const How = enum { setting, beside, tab };

pub const Kind = enum { code, markdown, image, video, audio, pdf };

pub fn kindOf(path: []const u8) Kind {
    const dot = std.mem.lastIndexOfScalar(u8, path, '.') orelse return .code;
    var buf: [16]u8 = undefined;
    const ext_raw = path[dot + 1 ..];
    if (ext_raw.len > buf.len) return .code;
    const ext = std.ascii.lowerString(&buf, ext_raw);
    const groups = [_]struct { Kind, []const []const u8 }{
        .{ .markdown, &.{ "md", "markdown", "mdx" } },
        .{ .image, &.{ "png", "jpg", "jpeg", "gif", "webp", "bmp", "tif", "tiff", "ico", "heic", "svg" } },
        .{ .video, &.{ "mp4", "mov", "m4v", "webm", "mkv", "avi" } },
        .{ .audio, &.{ "mp3", "wav", "aac", "m4a", "flac", "ogg" } },
        .{ .pdf, &.{"pdf"} },
    };
    for (groups) |g| for (g[1]) |e| if (std.mem.eql(u8, e, ext)) return g[0];
    return .code;
}

/// A document maker for a kind, set when the feature exists (app wiring).
pub const Maker = *const fn (app: *App, path: []const u8, line: u32) ?tabs.Document;

pub var makers: std.EnumArray(Kind, ?Maker) = .initFill(null);

pub fn open(app: *App, path: []const u8, line: u32, how: How) void {
    const kind = kindOf(path);
    if (makers.get(kind)) |make| if (make(app, path, line)) |doc| {
        const where: tabs.OpenFiles = switch (how) {
            .setting => if (std.mem.eql(u8, app.settings.current.general.open_files, "tab")) .tab else .beside,
            .beside => .beside,
            .tab => .tab,
        };
        app.tabs.open(doc, where, null);
        app.window.redraw();
        return;
    };
    systemOpen(app, path);
}

pub fn systemOpen(app: *App, target: []const u8) void {
    const wide = std.unicode.wtf8ToWtf16LeAllocZ(app.gpa, target) catch return;
    defer app.gpa.free(wide);
    _ = w.c.ShellExecuteW(app.window.hwnd, w.L("open"), wide.ptr, null, null, w.c.SW_SHOWNORMAL);
}

test "files go to their viewer by extension" {
    try std.testing.expectEqual(Kind.markdown, kindOf("C:\\x\\README.MD"));
    try std.testing.expectEqual(Kind.image, kindOf("a.png"));
    try std.testing.expectEqual(Kind.code, kindOf("Makefile"));
}

test {
    w.refAllDeep(@This());
}
