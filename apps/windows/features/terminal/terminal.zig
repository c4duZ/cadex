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
pub const Typesetting = @import("typesetting.zig").Typesetting;
pub const paste = @import("paste.zig");
pub const keys = @import("keys.zig");

/// The font every pane draws with; made again when the family, the size,
/// the window's scale or the typesetting (line height, letter spacing,
/// features) changes.
pub const SharedFont = struct {
    gpa: std.mem.Allocator,
    factory: *w.c.IDWriteFactory5,
    font: ?Font = null,
    /// A hash of the family, not the settings' slice, which a reload frees.
    family: u64 = 0,
    points: f32 = 0,
    scale: f32 = 0,
    typesetting: u64 = 0,

    pub fn get(self: *SharedFont, family: []const u8, points: f32, scale: f32, t: Typesetting) ?*Font {
        const family_key = std.hash.Wyhash.hash(0, family);
        const t_key = t.key();
        if (self.font != null and family_key == self.family and points == self.points and scale == self.scale and t_key == self.typesetting) return &self.font.?;
        if (self.font) |*f| f.deinit();
        self.font = Font.init(self.gpa, self.factory, family, points, scale, t) catch null;
        self.family = family_key;
        self.points = points;
        self.scale = scale;
        self.typesetting = t_key;
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
    _ = @import("typesetting.zig");
    _ = @import("min_contrast.zig");
    _ = @import("shaping.zig");
}
