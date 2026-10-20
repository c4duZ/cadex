//! The interface layer of the Windows app (docs/adr/0012-windows-zig-win32-d3d11.md):
//! immediate mode, drawn by gfx, styled by the theme.

pub const context = @import("context.zig");
pub const Ui = context.Ui;
pub const Id = context.Id;
pub const id = context.id;
pub const child = context.child;
pub const Cursor = context.Cursor;
pub const Input = @import("input.zig").Input;
pub const Key = @import("input.zig").Key;
pub const Mods = @import("input.zig").Mods;
pub const Button = @import("input.zig").Button;
pub const Style = @import("style.zig").Style;
pub const widgets = @import("widgets.zig");
pub const TextBuffer = @import("text_buffer.zig").TextBuffer;
pub const text_field = @import("text_field.zig");
pub const list = @import("list.zig");
pub const menu = @import("menu.zig");
pub const clipboard = @import("clipboard.zig");

test {
    _ = @import("context.zig");
    _ = @import("input.zig");
    _ = @import("style.zig");
    _ = @import("widgets.zig");
    _ = @import("text_buffer.zig");
    _ = @import("text_field.zig");
    _ = @import("list.zig");
    _ = @import("menu.zig");
    _ = @import("clipboard.zig");
}

test {
    @import("win32").refAllDeep(@This());
}
