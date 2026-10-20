//! The zoom and pan of an image in its pane, the Mac's rules
//! (apps/macos/features/media-preview/ImageViewer.swift): fitted to the
//! pane when bigger, never enlarged by fitting; zoom in and out by 1.25,
//! from 5 % to 1600 %; real size; centered when smaller than the pane,
//! dragged around when larger. Pure, in window pixels.

const std = @import("std");
const gfx = @import("gfx");

pub const Size = struct { w: f32, h: f32 };

pub const min_scale: f32 = 0.05;
pub const max_scale: f32 = 16;
pub const step: f32 = 1.25;

pub const Zoom = struct {
    /// Follows the pane's size (Ctrl+0); off after any zoom.
    fitted: bool = true,
    scale: f32 = 1,
    /// How far the image's center is from the pane's, in pixels.
    pan: gfx.Point = .{},

    pub fn fitScale(image: Size, area: Size) f32 {
        if (image.w <= 0 or image.h <= 0 or area.w <= 0 or area.h <= 0) return 1;
        return @min(@min(area.w / image.w, area.h / image.h), 1);
    }

    /// The scale on screen now.
    pub fn effective(self: Zoom, image: Size, area: Size) f32 {
        return if (self.fitted) fitScale(image, area) else self.scale;
    }

    pub fn fit(self: *Zoom) void {
        self.fitted = true;
        self.pan = .{};
    }

    pub fn actualSize(self: *Zoom) void {
        self.fitted = false;
        self.scale = 1;
        self.pan = .{};
    }

    /// Zooms around the pane's center: what is in the middle stays there.
    pub fn zoomBy(self: *Zoom, factor: f32, image: Size, area: Size) void {
        const before = self.effective(image, area);
        const after = std.math.clamp(before * factor, min_scale, max_scale);
        self.fitted = false;
        self.scale = after;
        const ratio = after / before;
        self.pan = .{ .x = self.pan.x * ratio, .y = self.pan.y * ratio };
        self.clampPan(image, area);
    }

    pub fn panBy(self: *Zoom, dx: f32, dy: f32, image: Size, area: Size) void {
        self.pan.x += dx;
        self.pan.y += dy;
        self.clampPan(image, area);
    }

    /// An image smaller than the pane stays centered on that axis; a larger
    /// one never leaves an edge inside the pane.
    fn clampPan(self: *Zoom, image: Size, area: Size) void {
        const s = self.effective(image, area);
        const max_x = @max(0, (image.w * s - area.w) / 2);
        const max_y = @max(0, (image.h * s - area.h) / 2);
        self.pan.x = std.math.clamp(self.pan.x, -max_x, max_x);
        self.pan.y = std.math.clamp(self.pan.y, -max_y, max_y);
    }

    /// Where the image is drawn in `area`.
    pub fn dest(self: Zoom, image: Size, area: gfx.Rect) gfx.Rect {
        const s = self.effective(image, .{ .w = area.w, .h = area.h });
        const w = image.w * s;
        const h = image.h * s;
        const c = area.center();
        return .{ .x = @round(c.x - w / 2 + self.pan.x), .y = @round(c.y - h / 2 + self.pan.y), .w = w, .h = h };
    }

    /// Bigger than the pane: the hand cursor and dragging apply.
    pub fn pannable(self: Zoom, image: Size, area: Size) bool {
        const s = self.effective(image, area);
        return image.w * s > area.w + 0.5 or image.h * s > area.h + 0.5;
    }
};

const testing = std.testing;
const big: Size = .{ .w = 2000, .h = 1000 };
const pane: Size = .{ .w = 1000, .h = 800 };

test "fitting shrinks a big image and never enlarges a small one" {
    try testing.expectEqual(@as(f32, 0.5), Zoom.fitScale(big, pane));
    try testing.expectEqual(@as(f32, 1), Zoom.fitScale(.{ .w = 10, .h = 10 }, pane));
}

test "zoom steps from the fitted scale and stays in range" {
    var z: Zoom = .{};
    z.zoomBy(step, big, pane);
    try testing.expect(!z.fitted);
    try testing.expectApproxEqAbs(@as(f32, 0.625), z.scale, 0.0001);
    for (0..100) |_| z.zoomBy(step, big, pane);
    try testing.expectEqual(max_scale, z.scale);
    z.fit();
    try testing.expect(z.fitted);
    z.actualSize();
    try testing.expectEqual(@as(f32, 1), z.effective(big, pane));
}

test "panning stops at the edges, and a small image stays centered" {
    var z: Zoom = .{};
    z.actualSize();
    z.panBy(5000, 5000, big, pane);
    // 2000 wide in a 1000 pane: 500 to each side; 1000 high in 800: 100.
    try testing.expectEqual(@as(f32, 500), z.pan.x);
    try testing.expectEqual(@as(f32, 100), z.pan.y);
    const r = z.dest(big, .{ .w = 1000, .h = 800 });
    try testing.expectEqual(@as(f32, 0), r.x);
    var small: Zoom = .{};
    small.panBy(50, 50, .{ .w = 10, .h = 10 }, pane);
    try testing.expectEqual(@as(f32, 0), small.pan.x);
    try testing.expect(!small.pannable(.{ .w = 10, .h = 10 }, pane));
}

test {
    @import("win32").refAllDeep(@This());
}
