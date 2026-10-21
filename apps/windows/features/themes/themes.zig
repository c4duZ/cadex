//! The themes feature (docs/spec/themes.md): the built-in catalog and the
//! user's themes folder, importing other apps' theme files, the theme in
//! use (`store.zig`: a family for dark and one for light, the mode, the
//! accent and high contrast), and the colors it gives the interface and
//! the terminals. The list of every theme is read by whoever shows it
//! (`library.all`).

const std = @import("std");
const gfx = @import("gfx");
const ui = @import("ui");
const cadex = @import("cadex");

pub const theme = @import("theme.zig");
pub const catalog = @import("catalog.zig");
pub const library = @import("library.zig");
pub const import = @import("import.zig");
pub const contrast = @import("contrast.zig");
pub const Theme = theme.Theme;
pub const Family = theme.Family;

pub const store = @import("store.zig");
pub const Store = store.Store;
pub const Choice = store.Choice;
pub const Mode = store.Mode;
pub const systemIsDark = store.systemIsDark;

/// The interface colors as the widgets draw them; `scale` is the window's.
pub fn style(t: Theme, scale: f32) ui.Style {
    const i = t.interface;
    return .{
        .chrome = gfx.Color.rgb(i.chrome),
        .panel = gfx.Color.rgb(i.panel),
        .panel_border = gfx.Color.rgb(i.panel_border),
        .tab_active = gfx.Color.rgb(i.tab_active),
        .tab_active_text = gfx.Color.rgb(contrast.textOnTabActive(i)),
        .field = gfx.Color.rgb(i.field),
        .text = gfx.Color.rgb(i.text),
        .secondary_text = gfx.Color.rgb(i.secondary_text),
        .accent = gfx.Color.rgb(i.accent),
        .dark = t.dark,
        .scale = scale,
    };
}

/// The colors the core gives programs and paints by default.
pub fn terminalColors(t: Theme) cadex.cadex_terminal_colors {
    return .{
        .background = t.terminal.background,
        .foreground = t.terminal.foreground,
        .cursor = t.terminal.cursor,
        .ansi = t.terminal.ansi,
    };
}

test {
    _ = @import("theme.zig");
    _ = @import("catalog.zig");
    _ = @import("file.zig");
    _ = @import("import.zig");
    _ = @import("library.zig");
    _ = @import("contrast.zig");
    _ = @import("store.zig");
}
