//! Pages the app serves itself (WebResourceRequested): the rendered note
//! and its images, at https://<host>/<path of the file>, answered by the
//! feature (Serve), which checks the file is inside the workspace. A page
//! of ours this way has a real address: relative images resolve against
//! the note's folder and #heading stays in the page, as cadex-file: does
//! on the Mac.

const std = @import("std");
const w = @import("win32");
const c = w.c;
const strings = @import("strings.zig");
const View = @import("view.zig").View;

pub const Body = union(enum) {
    /// Owned by the view's allocator; freed after the answer.
    bytes: []u8,
    /// A file to stream (owned UTF-8 path).
    file: []u8,
};

pub const Served = struct {
    body: Body,
    /// "text/html; charset=utf-8", "image/png" (static).
    mime: []const u8,
};

pub const Serve = struct {
    /// "https://note.cadex.example/": only requests under it are asked.
    prefix: []const u8,
    context: *anyopaque,
    /// Null: 404.
    answer: *const fn (context: *anyopaque, gpa: std.mem.Allocator, url: []const u8) ?Served,
};

extern "shlwapi" fn SHCreateMemStream(init: ?[*]const u8, size: c.UINT) callconv(.winapi) ?*c.IStream;
extern "shlwapi" fn SHCreateStreamOnFileEx(file: [*:0]const u16, mode: c.DWORD, attributes: c.DWORD, create: c.BOOL, template: ?*c.IStream, out: *?*c.IStream) callconv(.winapi) c.HRESULT;

pub fn register(v: *View, serve: Serve, handler: *c.ICoreWebView2WebResourceRequestedEventHandler, token: *c.EventRegistrationToken) void {
    const web = v.web.?;
    var filter_buf: [512]u8 = undefined;
    const filter = std.fmt.bufPrint(&filter_buf, "{s}*", .{serve.prefix}) catch return;
    const wide = strings.wide(v.gpa, filter) catch return;
    defer v.gpa.free(wide);
    _ = w.call(web, "add_WebResourceRequested", .{ handler, token });
    _ = w.call(web, "AddWebResourceRequestedFilter", .{ wide.ptr, c.COREWEBVIEW2_WEB_RESOURCE_CONTEXT_ALL });
}

pub fn answer(v: *View, args: [*c]c.ICoreWebView2WebResourceRequestedEventArgs) void {
    const serve = v.options.serve orelse return;
    const env = v.env.ready() orelse return;
    var request: [*c]c.ICoreWebView2WebResourceRequest = null;
    if (w.call(args, "get_Request", .{&request}) < 0 or request == null) return;
    defer w.release(request);
    var raw: c.LPWSTR = null;
    _ = w.call(request, "get_Uri", .{&raw});
    const url = strings.take(v.gpa, raw) orelse return;
    defer v.gpa.free(url);
    if (!std.mem.startsWith(u8, url, serve.prefix)) return;

    var stream: ?*c.IStream = null;
    var mime: []const u8 = "text/plain";
    if (serve.answer(serve.context, v.gpa, url)) |served| {
        mime = served.mime;
        stream = open(v.gpa, served.body);
    }
    defer if (stream) |s| w.release(s);
    var headers_buf: [256]u8 = undefined;
    // no-store: a note edited and shown again must not come from the cache.
    const headers = std.fmt.bufPrint(&headers_buf, "Content-Type: {s}\r\nCache-Control: no-store", .{mime}) catch return;
    const wide_headers = strings.wide(v.gpa, headers) catch return;
    defer v.gpa.free(wide_headers);
    var response: [*c]c.ICoreWebView2WebResourceResponse = null;
    const status: c_int = if (stream != null) 200 else 404;
    const reason = if (stream != null) w.L("OK") else w.L("Not Found");
    if (w.call(env, "CreateWebResourceResponse", .{ stream, status, reason, wide_headers.ptr, &response }) < 0) return;
    defer w.release(response);
    _ = w.call(args, "put_Response", .{response});
}

fn open(gpa: std.mem.Allocator, body: Body) ?*c.IStream {
    switch (body) {
        .bytes => |b| {
            defer gpa.free(b);
            // A copy of the bytes, held by the stream.
            return SHCreateMemStream(b.ptr, @intCast(b.len));
        },
        .file => |path| {
            defer gpa.free(path);
            const wide = strings.wide(gpa, path) catch return null;
            defer gpa.free(wide);
            var out: ?*c.IStream = null;
            const STGM_READ = 0;
            const STGM_SHARE_DENY_NONE = 0x40;
            if (SHCreateStreamOnFileEx(wide.ptr, STGM_READ | STGM_SHARE_DENY_NONE, 0, 0, null, &out) < 0) return null;
            return out;
        },
    }
}

/// The MIME type of a file a page asks for, by extension (images of a note,
/// and anything else as bytes).
pub fn mimeOf(path: []const u8) []const u8 {
    const dot = std.mem.lastIndexOfScalar(u8, path, '.') orelse return "application/octet-stream";
    const ext = path[dot + 1 ..];
    const table = [_]struct { []const u8, []const u8 }{
        .{ "png", "image/png" },       .{ "jpg", "image/jpeg" },     .{ "jpeg", "image/jpeg" },
        .{ "gif", "image/gif" },       .{ "webp", "image/webp" },    .{ "svg", "image/svg+xml" },
        .{ "bmp", "image/bmp" },       .{ "ico", "image/x-icon" },   .{ "avif", "image/avif" },
        .{ "md", "text/html; charset=utf-8" }, .{ "markdown", "text/html; charset=utf-8" },
        .{ "css", "text/css" },        .{ "txt", "text/plain; charset=utf-8" },
    };
    for (table) |entry| if (std.ascii.eqlIgnoreCase(entry[0], ext)) return entry[1];
    return "application/octet-stream";
}

test "mime types by extension" {
    try std.testing.expectEqualStrings("image/png", mimeOf("C:\\a\\b.PNG"));
    try std.testing.expectEqualStrings("image/svg+xml", mimeOf("x.svg"));
    try std.testing.expectEqualStrings("application/octet-stream", mimeOf("noext"));
}

test {
    @import("win32").refAllDeep(@This());
}
