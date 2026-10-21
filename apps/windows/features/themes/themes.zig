//! The themes feature (docs/spec/themes.md): the built-in catalog and the
//! user's themes folder, importing other apps' theme files, the theme in
//! use (the family the user picked, in the mode they picked, following
//! Windows' light or dark by default), and the colors it gives the
//! interface and the terminals. Only the family in use is kept; the list
//! of every theme is read by whoever shows it (`library.all`).

const std = @import("std");
const gfx = @import("gfx");
const ui = @import("ui");
const w = @import("win32");
const cadex = @import("cadex");

pub const theme = @import("theme.zig");
pub const catalog = @import("catalog.zig");
pub const library = @import("library.zig");
pub const import = @import("import.zig");
pub const Theme = theme.Theme;
pub const Family = theme.Family;

pub const Mode = enum { system, dark, light };

pub const Store = struct {
    gpa: std.mem.Allocator,
    /// Holds the strings of `family` (and so of `current`); replaced with it.
    arena: std.heap.ArenaAllocator,
    family: Family,
    mode: Mode = .system,
    current: Theme,
    /// The user's themes folder (library.folder); empty if Windows has none.
    folder: []const u8,

    pub fn init(gpa: std.mem.Allocator) Store {
        var self: Store = .{ .gpa = gpa, .arena = .init(gpa), .family = undefined, .current = undefined, .folder = library.folder(gpa) catch "" };
        // Embedded at build time and checked by the tests: it is there.
        self.family = catalog.find(gpa, self.arena.allocator(), catalog.default_id) orelse @panic("catalog.json sem o tema padrão");
        self.current = self.resolve();
        return self;
    }

    pub fn deinit(self: *Store) void {
        self.arena.deinit();
        if (self.folder.len > 0) self.gpa.free(self.folder);
    }

    /// Picks a family and a mode (from the settings). True if the theme
    /// changed. The same id again reads nothing: the settings call this on
    /// every change.
    pub fn select(self: *Store, id: []const u8, mode: Mode) bool {
        self.mode = mode;
        if (std.mem.eql(u8, id, self.family.id)) return self.refresh();
        return self.load(id);
    }

    /// The user's themes folder changed (an import): the theme in use may
    /// be one of them.
    pub fn reload(self: *Store) bool {
        return self.load(self.family.id);
    }

    /// Reads one family into a fresh arena; an unknown id falls back to the
    /// default, as on the Mac. The old arena goes after the comparison.
    fn load(self: *Store, id: []const u8) bool {
        var next: std.heap.ArenaAllocator = .init(self.gpa);
        const a = next.allocator();
        const found = library.family(self.gpa, a, self.folder, id) orelse catalog.find(self.gpa, a, catalog.default_id) orelse {
            next.deinit();
            return self.refresh();
        };
        var old = self.arena;
        self.arena = next;
        self.family = found;
        const changed = self.refresh();
        old.deinit();
        return changed;
    }

    /// Windows switched light and dark (WM_SETTINGCHANGE "ImmersiveColorSet").
    pub fn refresh(self: *Store) bool {
        const next = self.resolve();
        const same = std.mem.eql(u8, next.name, self.current.name) and next.dark == self.current.dark and
            std.meta.eql(next.interface, self.current.interface) and std.meta.eql(next.terminal, self.current.terminal);
        self.current = next;
        return !same;
    }

    fn resolve(self: *const Store) Theme {
        const dark = switch (self.mode) {
            .system => systemIsDark(),
            .dark => true,
            .light => false,
        };
        return self.family.theme(dark);
    }
};

/// HKEY_CURRENT_USER is 0x80000001, an odd "pointer" Zig will not form,
/// so the key goes in as a number.
const hkey_current_user: usize = 0x80000001;
extern "advapi32" fn RegGetValueW(key: usize, sub_key: [*:0]const u16, value: [*:0]const u16, flags: w.c.DWORD, kind: ?*w.c.DWORD, data: ?*anyopaque, size: ?*w.c.DWORD) callconv(.winapi) c_long;

/// Whether Windows' apps are in dark mode (Settings > Personalization > Colors).
pub fn systemIsDark() bool {
    var value: w.c.DWORD = 1;
    var size: w.c.DWORD = @sizeOf(w.c.DWORD);
    const status = RegGetValueW(
        hkey_current_user,
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
    _ = @import("file.zig");
    _ = @import("import.zig");
    _ = @import("library.zig");
}
