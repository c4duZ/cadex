//! The terminal feature (docs/spec/terminal.md): a shell per pane through
//! the core, drawn with Direct2D, keys and text from the window, the mouse,
//! links, find and paste. `Fonts` keeps one font per size and scale for
//! every pane.

const std = @import("std");
const w = @import("win32");

pub const Session = @import("session.zig").Session;
pub const Event = @import("session.zig").Event;
pub const Events = @import("session.zig").Events;
pub const Preferences = @import("session.zig").Preferences;
pub const Owned = @import("session.zig").Owned;
pub const View = @import("view.zig").View;
pub const Hooks = @import("view.zig").Hooks;
pub const Font = @import("font.zig").Font;
pub const paste = @import("paste.zig");
pub const keys = @import("keys.zig");

/// The font every pane draws with; made again when the family, the size
/// or the window's scale changes.
pub const SharedFont = struct {
    gpa: std.mem.Allocator,
    factory: *w.c.IDWriteFactory5,
    font: ?Font = null,
    family: []const u8 = "",
    points: f32 = 0,
    scale: f32 = 0,

    pub fn get(self: *SharedFont, family: []const u8, points: f32, scale: f32) ?*Font {
        if (self.font != null and std.mem.eql(u8, family, self.family) and points == self.points and scale == self.scale) return &self.font.?;
        if (self.font) |*f| f.deinit();
        self.font = Font.init(self.gpa, self.factory, family, points, scale) catch null;
        self.family = family;
        self.points = points;
        self.scale = scale;
        return if (self.font) |*f| f else null;
    }

    pub fn deinit(self: *SharedFont) void {
        if (self.font) |*f| f.deinit();
    }
};

test {
    _ = @import("session.zig");
    _ = @import("view.zig");
    _ = @import("font.zig");
    _ = @import("renderer.zig");
    _ = @import("keys.zig");
    _ = @import("find.zig");
    _ = @import("paste.zig");
}
