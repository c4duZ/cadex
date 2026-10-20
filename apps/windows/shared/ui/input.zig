//! What the window received since the last frame: the mouse, the wheel,
//! keys and typed text. The window procedure fills it; the frame consumes
//! it (context.zig).

const std = @import("std");
const gfx = @import("gfx");

pub const Mods = packed struct(u8) {
    shift: bool = false,
    ctrl: bool = false,
    alt: bool = false,
    /// The Windows key; never a shortcut of the app (the system owns it).
    super: bool = false,
    _: u4 = 0,

    pub fn none(m: Mods) bool {
        return !m.shift and !m.ctrl and !m.alt and !m.super;
    }
    pub fn eql(a: Mods, b: Mods) bool {
        return @as(u8, @bitCast(a)) == @as(u8, @bitCast(b));
    }
};

/// A key press, by Windows virtual-key code (VK_*), with the modifiers held.
pub const Key = struct {
    vk: u16,
    mods: Mods,
    repeat: bool = false,
    /// Set once something handled it, so nothing else does.
    used: bool = false,
};

pub const Button = enum(u2) { left = 0, right = 1, middle = 2 };

pub const Input = struct {
    mouse: gfx.Point = .{},
    mouse_inside: bool = false,
    /// This frame only: buttons that went down or up.
    pressed: [3]bool = .{ false, false, false },
    released: [3]bool = .{ false, false, false },
    down: [3]bool = .{ false, false, false },
    /// 1, 2 or 3 for the last press (double and triple click).
    clicks: u8 = 1,
    /// Wheel steps this frame (120 per notch, as Windows reports), up positive.
    wheel: i32 = 0,
    wheel_horizontal: i32 = 0,
    mods: Mods = .{},
    keys: std.ArrayList(Key) = .empty,
    /// Text typed this frame (WM_CHAR, after the keyboard layout and dead keys).
    text: std.ArrayList(u8) = .empty,
    /// The IME's text being composed, shown at the caret until committed.
    composition: std.ArrayList(u8) = .empty,
    /// Files dropped on the window this frame (full paths).
    dropped: std.ArrayList([]u8) = .empty,
    drop_point: gfx.Point = .{},

    last_press_ms: i64 = 0,
    last_press_at: gfx.Point = .{},

    pub fn deinit(self: *Input, gpa: std.mem.Allocator) void {
        self.keys.deinit(gpa);
        self.text.deinit(gpa);
        self.composition.deinit(gpa);
        self.clearDropped(gpa);
        self.dropped.deinit(gpa);
    }

    fn clearDropped(self: *Input, gpa: std.mem.Allocator) void {
        for (self.dropped.items) |p| gpa.free(p);
        self.dropped.clearRetainingCapacity();
    }

    /// After a frame: what happened once is gone; what is held stays.
    pub fn endFrame(self: *Input, gpa: std.mem.Allocator) void {
        self.pressed = .{ false, false, false };
        self.released = .{ false, false, false };
        self.wheel = 0;
        self.wheel_horizontal = 0;
        self.keys.clearRetainingCapacity();
        self.text.clearRetainingCapacity();
        self.clearDropped(gpa);
    }

    /// A press, counting double and triple clicks the way Windows does:
    /// within `double_ms` and a few pixels of the last one.
    pub fn press(self: *Input, button: Button, at: gfx.Point, now_ms: i64, double_ms: i64, slop: f32) void {
        const i = @intFromEnum(button);
        const near = @abs(at.x - self.last_press_at.x) <= slop and @abs(at.y - self.last_press_at.y) <= slop;
        self.clicks = if (button == .left and near and now_ms - self.last_press_ms <= double_ms) (self.clicks % 3) + 1 else 1;
        self.last_press_ms = now_ms;
        self.last_press_at = at;
        self.pressed[i] = true;
        self.down[i] = true;
        self.mouse = at;
    }

    pub fn release(self: *Input, button: Button, at: gfx.Point) void {
        const i = @intFromEnum(button);
        self.released[i] = true;
        self.down[i] = false;
        self.mouse = at;
    }
};

test "double and triple clicks count within time and distance" {
    var input: Input = .{};
    input.press(.left, .{ .x = 10, .y = 10 }, 1000, 500, 4);
    try std.testing.expectEqual(@as(u8, 1), input.clicks);
    input.press(.left, .{ .x = 11, .y = 10 }, 1200, 500, 4);
    try std.testing.expectEqual(@as(u8, 2), input.clicks);
    input.press(.left, .{ .x = 11, .y = 10 }, 1300, 500, 4);
    try std.testing.expectEqual(@as(u8, 3), input.clicks);
    input.press(.left, .{ .x = 50, .y = 10 }, 1350, 500, 4);
    try std.testing.expectEqual(@as(u8, 1), input.clicks);
}

test {
    @import("win32").refAllDeep(@This());
}
