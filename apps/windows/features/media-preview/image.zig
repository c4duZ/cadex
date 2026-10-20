//! A still image in a pane: decoded by WIC (gfx/wic.zig), drawn as a
//! Direct2D bitmap over a discreet checkerboard, fitted or zoomed
//! (zoom.zig), dragged when bigger than the pane, dimensions and file size
//! at the bottom.

const std = @import("std");
const w = @import("win32");
const gfx = @import("gfx");
const ui = @import("ui");
const zoom_mod = @import("zoom.zig");
const c = w.c;

/// Direct2D bitmaps stop at 16384 pixels a side on most GPUs; a 20 000 ×
/// 20 000 image is scaled down by WIC first, so it opens instead of failing
/// (docs/spec/media-preview.md).
const max_side: u32 = 8192;

pub const Image = struct {
    gpa: std.mem.Allocator,
    path: []const u8,
    /// Decoded and scaled, until the first draw makes the bitmap from it.
    source: ?*c.IWICBitmapSource = null,
    bitmap: ?*c.ID2D1Bitmap1 = null,
    /// The file's own size (what the info line says).
    width: u32 = 0,
    height: u32 = 0,
    bytes: u64 = 0,
    zoom: zoom_mod.Zoom = .{},
    dragging: ?gfx.Point = null,

    /// Null when WIC cannot decode the file (no codec for it).
    pub fn load(gpa: std.mem.Allocator, path: []const u8) ?Image {
        var self: Image = .{ .gpa = gpa, .path = path };
        if (!self.decode()) return null;
        return self;
    }

    fn decode(self: *Image) bool {
        const decoded = gfx.wic.decodeFile(self.path, self.gpa) catch return false;
        self.width = decoded.width;
        self.height = decoded.height;
        self.source = scaled(decoded) catch {
            decoded.release();
            return false;
        };
        self.bytes = fileSize(self.gpa, self.path);
        return true;
    }

    /// The file changed on disk: decode it again, keeping the zoom.
    pub fn reload(self: *Image) bool {
        self.dropPixels();
        return self.decode();
    }

    pub fn deinit(self: *Image) void {
        self.dropPixels();
    }

    fn dropPixels(self: *Image) void {
        if (self.bitmap) |b| w.release(b);
        if (self.source) |s| w.release(s);
        self.bitmap = null;
        self.source = null;
    }

    fn size(self: *const Image) zoom_mod.Size {
        return .{ .w = @floatFromInt(self.width), .h = @floatFromInt(self.height) };
    }

    pub fn zoomIn(self: *Image, area: gfx.Rect) void {
        self.zoom.zoomBy(zoom_mod.step, self.size(), .{ .w = area.w, .h = area.h });
    }
    pub fn zoomOut(self: *Image, area: gfx.Rect) void {
        self.zoom.zoomBy(1 / zoom_mod.step, self.size(), .{ .w = area.w, .h = area.h });
    }

    pub fn draw(self: *Image, u: *ui.Ui, area: gfx.Rect) void {
        var rest = area;
        const info_rect = rest.takeBottom(u.px(24));
        const view = rest.inset(u.px(4), u.px(4));
        self.handleMouse(u, view);
        u.painter.pushClip(view);
        const r = self.zoom.dest(self.size(), view);
        checkerboard(u, r.intersect(view));
        if (self.ensureBitmap(u.painter)) |bitmap| {
            const dest: c.D2D1_RECT_F = .{ .left = r.x, .top = r.y, .right = r.x + r.w, .bottom = r.y + r.h };
            // Linear when shrinking or slightly enlarged; nearest-neighbor
            // from 4× on, so pixel art and icons stay sharp when inspected.
            const mode = if (self.zoom.effective(self.size(), .{ .w = view.w, .h = view.h }) >= 4) c.D2D1_INTERPOLATION_MODE_NEAREST_NEIGHBOR else c.D2D1_INTERPOLATION_MODE_HIGH_QUALITY_CUBIC;
            w.call(u.painter.context, "DrawBitmap", .{ @as(*c.ID2D1Bitmap, @ptrCast(bitmap)), &dest, 1.0, mode, null, null });
        }
        u.painter.popClip();
        var size_buf: [32]u8 = undefined;
        var info_buf: [96]u8 = undefined;
        const info = std.fmt.bufPrint(&info_buf, "{d} × {d} · {s}", .{ self.width, self.height, formatBytes(&size_buf, self.bytes) }) catch "";
        u.painter.text(info, u.style.small(), info_rect, u.style.secondary_text, .{ .@"align" = .center });
    }

    fn handleMouse(self: *Image, u: *ui.Ui, view: gfx.Rect) void {
        const sz = self.size();
        const area: zoom_mod.Size = .{ .w = view.w, .h = view.h };
        const pannable = self.zoom.pannable(sz, area);
        if (u.mouseOver(view) and pannable) u.cursor = .hand;
        if (pannable and u.pressedOn(view, .left)) self.dragging = u.input.mouse;
        if (self.dragging) |from| {
            if (!u.input.down[0]) {
                self.dragging = null;
            } else {
                self.zoom.panBy(u.input.mouse.x - from.x, u.input.mouse.y - from.y, sz, area);
                self.dragging = u.input.mouse;
            }
        }
        if (u.mouseOver(view) and (u.input.wheel != 0 or u.input.wheel_horizontal != 0)) {
            if (u.input.mods.ctrl) {
                // Ctrl+wheel zooms, as in every Windows image viewer.
                const f: f32 = if (u.input.wheel > 0) zoom_mod.step else 1 / zoom_mod.step;
                self.zoom.zoomBy(f, sz, area);
            } else {
                const notch = u.px(48);
                const dy = @as(f32, @floatFromInt(u.input.wheel)) / 120 * notch;
                const dx = -@as(f32, @floatFromInt(u.input.wheel_horizontal)) / 120 * notch;
                self.zoom.panBy(dx, dy, sz, area);
            }
            u.input.wheel = 0;
            u.input.wheel_horizontal = 0;
        }
    }

    fn ensureBitmap(self: *Image, painter: *gfx.Painter) ?*c.ID2D1Bitmap1 {
        if (self.bitmap) |b| return b;
        const source = self.source orelse return null;
        var bitmap: [*c]c.ID2D1Bitmap1 = null;
        if (w.call(painter.context, "CreateBitmapFromWicBitmap", .{ source, null, &bitmap }) < 0 or bitmap == null) return null;
        // The pixels now live on the GPU; the decoded copy can go.
        w.release(source);
        self.source = null;
        self.bitmap = bitmap;
        return bitmap;
    }
};

/// The source at most max_side pixels a side.
fn scaled(decoded: gfx.wic.Decoded) !*c.IWICBitmapSource {
    const long = @max(decoded.width, decoded.height);
    if (long <= max_side) return decoded.source;
    const f = try gfx.wic.factory();
    defer w.release(f);
    var scaler: [*c]c.IWICBitmapScaler = null;
    try w.check(w.call(f, "CreateBitmapScaler", .{&scaler}));
    errdefer w.release(scaler);
    const ratio = @as(f64, @floatFromInt(max_side)) / @as(f64, @floatFromInt(long));
    const nw: c.UINT = @max(1, @as(c.UINT, @intFromFloat(@as(f64, @floatFromInt(decoded.width)) * ratio)));
    const nh: c.UINT = @max(1, @as(c.UINT, @intFromFloat(@as(f64, @floatFromInt(decoded.height)) * ratio)));
    try w.check(w.call(scaler, "Initialize", .{ decoded.source, nw, nh, c.WICBitmapInterpolationModeFant }));
    // The scaler holds the source now.
    decoded.release();
    return @ptrCast(scaler);
}

/// A discreet checkerboard, so transparency reads as transparency.
fn checkerboard(u: *ui.Ui, r: gfx.Rect) void {
    if (r.w <= 0 or r.h <= 0) return;
    const gray = gfx.Color{ .r = 0.5, .g = 0.5, .b = 0.5 };
    u.painter.fill(r, gray.alpha(0.10));
    const tile = u.px(8);
    var y = r.y;
    var row: usize = 0;
    while (y < r.bottom()) : ({
        y += tile;
        row += 1;
    }) {
        var x = r.x + if (row % 2 == 1) tile else 0;
        while (x < r.right()) : (x += 2 * tile) {
            u.painter.fill((gfx.Rect{ .x = x, .y = y, .w = tile, .h = tile }).intersect(r), gray.alpha(0.12));
        }
    }
}

fn fileSize(gpa: std.mem.Allocator, path: []const u8) u64 {
    const wide = std.unicode.wtf8ToWtf16LeAllocZ(gpa, path) catch return 0;
    defer gpa.free(wide);
    var data: c.WIN32_FILE_ATTRIBUTE_DATA = undefined;
    if (c.GetFileAttributesExW(wide.ptr, c.GetFileExInfoStandard, &data) == 0) return 0;
    return (@as(u64, data.nFileSizeHigh) << 32) | data.nFileSizeLow;
}

/// The size the way the Mac's file formatter writes it, in Portuguese:
/// "830 bytes", "12 KB", "1,2 MB", "3,45 GB" (powers of 1000).
pub fn formatBytes(buf: []u8, bytes: u64) []const u8 {
    const b: f64 = @floatFromInt(bytes);
    const text = if (bytes < 1000)
        std.fmt.bufPrint(buf, "{d} bytes", .{bytes})
    else if (bytes < 1_000_000)
        std.fmt.bufPrint(buf, "{d} KB", .{@as(u64, @intFromFloat(@round(b / 1000)))})
    else if (bytes < 1_000_000_000)
        std.fmt.bufPrint(buf, "{d:.1} MB", .{b / 1_000_000})
    else
        std.fmt.bufPrint(buf, "{d:.2} GB", .{b / 1_000_000_000});
    const out = text catch return "";
    // The decimal comma of pt-BR.
    for (out) |*ch| if (ch.* == '.') {
        ch.* = ',';
    };
    return out;
}

test "sizes read like the Mac's" {
    var buf: [32]u8 = undefined;
    try std.testing.expectEqualStrings("830 bytes", formatBytes(&buf, 830));
    try std.testing.expectEqualStrings("12 KB", formatBytes(&buf, 12_345));
    try std.testing.expectEqualStrings("1,2 MB", formatBytes(&buf, 1_234_567));
    try std.testing.expectEqualStrings("3,46 GB", formatBytes(&buf, 3_456_789_012));
}

test {
    @import("win32").refAllDeep(@This());
}
