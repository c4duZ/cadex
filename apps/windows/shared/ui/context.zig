//! The immediate-mode interface: each frame the app draws everything again
//! and the widgets answer the input of that frame (clicked, typed). A
//! frame runs only when something changed (input, output of a terminal,
//! a timer), so an idle window costs nothing.
//!
//! Widgets are known by an Id, stable across frames: `hot` is under the
//! mouse, `active` holds the mouse button, `focus` gets the keys. Popups
//! (menus, the palette, dialogs) are an overlay: while one is open, the
//! layer below sees no mouse.

const std = @import("std");
const gfx = @import("gfx");
const input_mod = @import("input.zig");
const Style = @import("style.zig").Style;

pub const Id = u64;
pub const none: Id = 0;

pub fn id(comptime name: []const u8, index: usize) Id {
    return std.hash.Wyhash.hash(index, name) | 1;
}

/// An id under another one (a row of a list, a button of a tab).
pub fn child(parent: Id, index: usize) Id {
    return std.hash.Wyhash.hash(parent, std.mem.asBytes(&index)) | 1;
}

pub const Cursor = enum { arrow, ibeam, hand, resize_we, resize_ns };

pub const Layer = enum { base, overlay };

pub const Ui = struct {
    gpa: std.mem.Allocator,
    painter: *gfx.Painter,
    style: Style,
    input: *input_mod.Input,
    /// Window size in pixels.
    size: gfx.Point = .{},
    now_ms: i64 = 0,

    hot: Id = none,
    active: Id = none,
    focus: Id = none,
    /// The hot widget found while drawing this frame; becomes `hot` next.
    next_hot: Id = none,
    cursor: Cursor = .arrow,
    layer: Layer = .base,
    /// The overlay's area last frame: the base layer is blind under it.
    overlay_rects: std.ArrayList(gfx.Rect) = .empty,
    next_overlay_rects: std.ArrayList(gfx.Rect) = .empty,
    /// Asks for another frame soon (a blinking caret, an animation).
    wants_frame_in_ms: ?u32 = null,
    /// Where the IME should show its candidates (the focused caret).
    ime_caret: ?gfx.Rect = null,
    /// The window, for the clipboard.
    hwnd: @import("win32").c.HWND = null,
    /// While a scrolled page draws: the part on screen. Widgets scrolled
    /// out of it get no mouse (a row under the page's title is not clicked).
    mouse_clip: ?gfx.Rect = null,

    pub fn deinit(self: *Ui) void {
        self.overlay_rects.deinit(self.gpa);
        self.next_overlay_rects.deinit(self.gpa);
    }

    pub fn beginFrame(self: *Ui, now_ms: i64) void {
        self.now_ms = now_ms;
        self.cursor = .arrow;
        self.next_hot = none;
        self.wants_frame_in_ms = null;
        self.ime_caret = null;
        self.layer = .base;
        self.next_overlay_rects.clearRetainingCapacity();
        if (!self.input.down[0] and !self.input.down[1] and !self.input.down[2]) self.active = none;
    }

    pub fn endFrame(self: *Ui) void {
        self.hot = self.next_hot;
        std.mem.swap(std.ArrayList(gfx.Rect), &self.overlay_rects, &self.next_overlay_rects);
        // A click on nothing drops the focus of a field (not of a terminal,
        // which takes it back itself when clicked).
        self.input.endFrame(self.gpa);
    }

    /// Draws in the overlay from here on; the rectangle blocks the layer below.
    pub fn beginOverlay(self: *Ui, area: gfx.Rect) void {
        self.layer = .overlay;
        self.next_overlay_rects.append(self.gpa, area) catch {};
    }

    pub fn endOverlay(self: *Ui) void {
        self.layer = .base;
    }

    /// Whether the mouse can reach `r` in the current layer.
    pub fn mouseOver(self: *Ui, r: gfx.Rect) bool {
        if (!self.input.mouse_inside or !r.contains(self.input.mouse)) return false;
        if (self.mouse_clip) |clip| if (!clip.contains(self.input.mouse)) return false;
        if (self.layer == .base) {
            for (self.overlay_rects.items) |o| if (o.contains(self.input.mouse)) return false;
        }
        return true;
    }

    /// Hover and press bookkeeping for a clickable area. True on the
    /// release over it (a click), as Windows buttons behave.
    pub fn clickable(self: *Ui, widget: Id, r: gfx.Rect) bool {
        const over = self.mouseOver(r);
        if (over) self.next_hot = widget;
        if (over and self.input.pressed[0]) self.active = widget;
        const clicked = self.active == widget and self.input.released[0] and over;
        if (clicked) self.active = none;
        return clicked;
    }

    /// The press itself (for drags, double clicks and right clicks).
    pub fn pressedOn(self: *Ui, r: gfx.Rect, button: input_mod.Button) bool {
        return self.input.pressed[@intFromEnum(button)] and self.mouseOver(r);
    }

    pub fn isHot(self: *Ui, widget: Id) bool {
        return self.hot == widget;
    }

    pub fn isActive(self: *Ui, widget: Id) bool {
        return self.active == widget;
    }

    /// The first unused press of `vk` with exactly `mods`, marked used.
    pub fn key(self: *Ui, vk: u16, mods: input_mod.Mods) bool {
        for (self.input.keys.items) |*k| {
            if (!k.used and k.vk == vk and k.mods.eql(mods)) {
                k.used = true;
                return true;
            }
        }
        return false;
    }

    pub fn requestFrame(self: *Ui, in_ms: u32) void {
        self.wants_frame_in_ms = if (self.wants_frame_in_ms) |t| @min(t, in_ms) else in_ms;
    }

    pub fn px(self: *const Ui, dips: f32) f32 {
        return self.style.px(dips);
    }

    /// A row's height: zoomed and tighter in compact density.
    pub fn rowPx(self: *const Ui, dips: f32) f32 {
        return self.style.rowPx(dips);
    }
};

test "ids are stable and differ by name and index" {
    try std.testing.expectEqual(id("tab", 1), id("tab", 1));
    try std.testing.expect(id("tab", 1) != id("tab", 2));
    try std.testing.expect(id("tab", 1) != id("pane", 1));
    try std.testing.expect(child(id("list", 0), 3) != none);
}

test {
    @import("win32").refAllDeep(@This());
}
