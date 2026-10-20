//! The themes feature (docs/spec/themes.md): the built-in catalog, the
//! theme in use (the family the user picked, in the mode they picked,
//! following Windows' light or dark by default), and the colors it gives
//! the interface and the terminals.

const std = @import("std");
const gfx = @import("gfx");
const ui = @import("ui");
const w = @import("win32");
const cadex = @import("cadex");

pub const theme = @import("theme.zig");
pub const catalog = @import("catalog.zig");
pub const Theme = theme.Theme;
pub const Family = theme.Family;

pub const Mode = enum { system, dark, light };

pub const Store = struct {
    gpa: std.mem.Allocator,
    family_id: []const u8 = catalog.default_id,
    mode: Mode = .system,
    current: Theme,

    pub fn init(gpa: std.mem.Allocator) Store {
        var self: Store = .{ .gpa = gpa, .current = undefined };
        self.current = self.resolve();
        return self;
    }

    pub fn families(self: *const Store) []const Family {
        return catalog.families(self.gpa);
    }

    pub fn family(self: *const Store) Family {
        return catalog.find(self.gpa, self.family_id) orelse catalog.families(self.gpa)[0];
    }

    /// Picks a family and a mode (from the settings). True if the theme changed.
    pub fn select(self: *Store, id: []const u8, mode: Mode) bool {
        self.family_id = if (catalog.find(self.gpa, id)) |f| f.id else catalog.default_id;
        self.mode = mode;
        return self.refresh();
    }

    /// Windows switched light and dark (WM_SETTINGCHANGE "ImmersiveColorSet").
    pub fn refresh(self: *Store) bool {
        const next = self.resolve();
        const changed = !std.mem.eql(u8, next.name, self.current.name) or next.dark != self.current.dark;
        self.current = next;
        return changed;
    }

    fn resolve(self: *const Store) Theme {
        const dark = switch (self.mode) {
            .system => systemIsDark(),
            .dark => true,
            .light => false,
        };
        return self.family().theme(dark);
    }
};

/// Whether Windows' apps are in dark mode (Settings > Personalization > Colors).
pub fn systemIsDark() bool {
    var value: w.c.DWORD = 1;
    var size: w.c.DWORD = @sizeOf(w.c.DWORD);
    const status = w.c.RegGetValueW(
        w.c.HKEY_CURRENT_USER,
        w.L("Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize"),
        w.L("AppsUseLightTheme"),
        w.c.RRF_RT_REG_DWORD,
        null,
        &value,
        &size,
    );
    return status == 0 and value == 0;
}

/// The interface colors as the widgets draw them; `scale` is the window's.
pub fn style(t: Theme, scale: f32) ui.Style {
    const i = t.interface;
    return .{
        .chrome = gfx.Color.rgb(i.chrome),
        .panel = gfx.Color.rgb(i.panel),
        .panel_border = gfx.Color.rgb(i.panel_border),
        .tab_active = gfx.Color.rgb(i.tab_active),
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
}
