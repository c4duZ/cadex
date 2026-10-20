//! Drawing for the Windows app (docs/adr/0012-windows-zig-win32-d3d11.md):
//! one Device per process, a Surface per window, a Painter per frame.

const geometry = @import("geometry.zig");

pub const Device = @import("device.zig").Device;
pub const Surface = @import("surface.zig").Surface;
pub const Fonts = @import("fonts.zig").Fonts;
pub const FontSpec = @import("fonts.zig").Spec;
pub const Weight = @import("fonts.zig").Weight;
pub const Painter = @import("painter.zig").Painter;
pub const TextOptions = @import("painter.zig").TextOptions;
pub const utf16 = @import("painter.zig").utf16;
pub const wic = @import("wic.zig");
pub const Rect = geometry.Rect;
pub const Point = geometry.Point;
pub const Color = geometry.Color;

test {
    _ = @import("geometry.zig");
    _ = @import("painter.zig");
    _ = @import("device.zig");
    _ = @import("surface.zig");
    _ = @import("fonts.zig");
    _ = @import("wic.zig");
}

test {
    @import("std").testing.refAllDecls(@This());
}
