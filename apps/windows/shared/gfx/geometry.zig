//! Points, rectangles and colors in the units the app draws in: pixels of
//! the window (already scaled for the monitor's DPI).

const std = @import("std");

pub const Point = struct {
    x: f32 = 0,
    y: f32 = 0,
};

pub const Rect = struct {
    x: f32 = 0,
    y: f32 = 0,
    w: f32 = 0,
    h: f32 = 0,

    pub fn right(r: Rect) f32 {
        return r.x + r.w;
    }
    pub fn bottom(r: Rect) f32 {
        return r.y + r.h;
    }
    pub fn contains(r: Rect, p: Point) bool {
        return p.x >= r.x and p.x < r.right() and p.y >= r.y and p.y < r.bottom();
    }
    pub fn inset(r: Rect, dx: f32, dy: f32) Rect {
        return .{ .x = r.x + dx, .y = r.y + dy, .w = @max(r.w - 2 * dx, 0), .h = @max(r.h - 2 * dy, 0) };
    }
    /// The top `h` of the rectangle, and what is left below.
    pub fn takeTop(r: *Rect, h: f32) Rect {
        const t = @min(h, r.h);
        const top: Rect = .{ .x = r.x, .y = r.y, .w = r.w, .h = t };
        r.y += t;
        r.h -= t;
        return top;
    }
    pub fn takeBottom(r: *Rect, h: f32) Rect {
        const t = @min(h, r.h);
        r.h -= t;
        return .{ .x = r.x, .y = r.y + r.h, .w = r.w, .h = t };
    }
    pub fn takeLeft(r: *Rect, wd: f32) Rect {
        const t = @min(wd, r.w);
        const left: Rect = .{ .x = r.x, .y = r.y, .w = t, .h = r.h };
        r.x += t;
        r.w -= t;
        return left;
    }
    pub fn takeRight(r: *Rect, wd: f32) Rect {
        const t = @min(wd, r.w);
        r.w -= t;
        return .{ .x = r.x + r.w, .y = r.y, .w = t, .h = r.h };
    }
    pub fn center(r: Rect) Point {
        return .{ .x = r.x + r.w / 2, .y = r.y + r.h / 2 };
    }
    pub fn intersect(a: Rect, b: Rect) Rect {
        const x = @max(a.x, b.x);
        const y = @max(a.y, b.y);
        return .{ .x = x, .y = y, .w = @max(@min(a.right(), b.right()) - x, 0), .h = @max(@min(a.bottom(), b.bottom()) - y, 0) };
    }
};

pub const Color = struct {
    r: f32,
    g: f32,
    b: f32,
    a: f32 = 1,

    /// 0xRRGGBB, as the core and the themes give colors.
    pub fn rgb(value: u32) Color {
        return .{
            .r = @as(f32, @floatFromInt((value >> 16) & 0xff)) / 255,
            .g = @as(f32, @floatFromInt((value >> 8) & 0xff)) / 255,
            .b = @as(f32, @floatFromInt(value & 0xff)) / 255,
        };
    }
    pub fn alpha(self: Color, a: f32) Color {
        return .{ .r = self.r, .g = self.g, .b = self.b, .a = self.a * a };
    }
    /// The mix of `self` and `other`, `t` of the way to other.
    pub fn mix(self: Color, other: Color, t: f32) Color {
        return .{
            .r = self.r + (other.r - self.r) * t,
            .g = self.g + (other.g - self.g) * t,
            .b = self.b + (other.b - self.b) * t,
            .a = self.a + (other.a - self.a) * t,
        };
    }
    pub fn luminance(self: Color) f32 {
        return 0.2126 * self.r + 0.7152 * self.g + 0.0722 * self.b;
    }
    pub const transparent: Color = .{ .r = 0, .g = 0, .b = 0, .a = 0 };
    pub const white: Color = .{ .r = 1, .g = 1, .b = 1 };
    pub const black: Color = .{ .r = 0, .g = 0, .b = 0 };
};

test "rectangles split and contain" {
    var r: Rect = .{ .w = 100, .h = 50 };
    const top = r.takeTop(10);
    try std.testing.expectEqual(@as(f32, 10), top.h);
    try std.testing.expectEqual(@as(f32, 40), r.h);
    try std.testing.expect(r.contains(.{ .x = 5, .y = 15 }));
    try std.testing.expect(!r.contains(.{ .x = 5, .y = 5 }));
}

test "colors come from 0xRRGGBB" {
    const c = Color.rgb(0xff8000);
    try std.testing.expectEqual(@as(f32, 1), c.r);
    try std.testing.expect(c.g > 0.5 and c.g < 0.51);
}
