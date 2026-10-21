//! The theme in use (docs/spec/themes.md), as the Mac's ThemeStore: a
//! family for dark mode and one for light (the same unless the user picked
//! two, plan 15 phase B), the mode, the accent and high contrast. Only the
//! two families in use are kept, each in an arena of its own replaced with
//! it; the list of every theme is read by whoever shows it.

const std = @import("std");
const w = @import("win32");
const theme = @import("theme.zig");
const catalog = @import("catalog.zig");
const library = @import("library.zig");
const contrast = @import("contrast.zig");

const Theme = theme.Theme;
const Family = theme.Family;

pub const Mode = enum { system, dark, light };

/// What the settings ask for.
pub const Choice = struct {
    dark: []const u8,
    light: []const u8,
    mode: Mode = .system,
    /// In place of the theme's accent; null keeps it.
    accent: ?u32 = null,
    high_contrast: bool = false,
};

/// One family and the arena holding its strings.
const Slot = struct {
    arena: std.heap.ArenaAllocator,
    family: Family,
};

pub const Store = struct {
    gpa: std.mem.Allocator,
    dark: Slot,
    light: Slot,
    mode: Mode = .system,
    accent: ?u32 = null,
    high_contrast: bool = false,
    current: Theme,
    /// The user's themes folder (library.folder); empty if Windows has none.
    folder: []const u8,

    pub fn init(gpa: std.mem.Allocator) Store {
        const folder = library.folder(gpa) catch "";
        // Embedded at build time and checked by the tests: it is there.
        const dark = loadSlot(gpa, folder, catalog.default_id) orelse @panic("catalog.json sem o tema padrão");
        const light = cloneSlot(gpa, dark.family) orelse @panic("sem memória para o tema");
        var self: Store = .{ .gpa = gpa, .dark = dark, .light = light, .current = undefined, .folder = folder };
        self.current = self.resolve();
        return self;
    }

    pub fn deinit(self: *Store) void {
        self.dark.arena.deinit();
        self.light.arena.deinit();
        if (self.folder.len > 0) self.gpa.free(self.folder);
    }

    /// The settings' choice; true if the theme changed. Families are read
    /// only when their id changes: the settings call this on every change.
    pub fn apply(self: *Store, next: Choice) bool {
        self.mode = next.mode;
        self.accent = next.accent;
        self.high_contrast = next.high_contrast;
        var old: [2]?Slot = .{ null, null };
        if (!std.mem.eql(u8, next.dark, self.dark.family.id)) {
            if (loadSlot(self.gpa, self.folder, next.dark)) |s| {
                old[0] = self.dark;
                self.dark = s;
            }
        }
        if (!std.mem.eql(u8, next.light, self.light.family.id)) {
            const same = std.mem.eql(u8, next.light, self.dark.family.id);
            if (if (same) cloneSlot(self.gpa, self.dark.family) else loadSlot(self.gpa, self.folder, next.light)) |s| {
                old[1] = self.light;
                self.light = s;
            }
        }
        // The old families go after the comparison, which reads their names.
        const changed = self.refresh();
        for (&old) |*o| if (o.*) |*s| s.arena.deinit();
        return changed;
    }

    /// The user's themes folder changed (an import): a theme in use may be
    /// one of them, so both are read again.
    pub fn reload(self: *Store) bool {
        var old = [2]Slot{ self.dark, self.light };
        self.dark = loadSlot(self.gpa, self.folder, old[0].family.id) orelse return false;
        self.light = loadSlot(self.gpa, self.folder, old[1].family.id) orelse {
            self.dark.arena.deinit();
            self.dark = old[0];
            return false;
        };
        const changed = self.refresh();
        for (&old) |*s| s.arena.deinit();
        return changed;
    }

    /// Windows switched light and dark or its contrast theme (WM_SETTINGCHANGE).
    pub fn refresh(self: *Store) bool {
        const next = self.resolve();
        const same = std.mem.eql(u8, next.name, self.current.name) and next.dark == self.current.dark and
            std.meta.eql(next.interface, self.current.interface) and std.meta.eql(next.terminal, self.current.terminal);
        self.current = next;
        return !same;
    }

    /// The setting, or a contrast theme of Windows (Accessibility > Contrast themes).
    pub fn isHighContrast(self: *const Store) bool {
        return self.high_contrast or systemHighContrast();
    }

    fn resolve(self: *const Store) Theme {
        const dark = switch (self.mode) {
            .system => systemIsDark(),
            .dark => true,
            .light => false,
        };
        var t = (if (dark) self.dark else self.light).family.theme(dark);
        if (self.accent) |a| t = contrast.withAccent(t, a);
        if (self.isHighContrast()) t = contrast.withHighContrast(t);
        return t;
    }
};

/// A family read into a fresh arena; an unknown id falls back to the
/// default, as on the Mac.
fn loadSlot(gpa: std.mem.Allocator, folder: []const u8, id: []const u8) ?Slot {
    var arena: std.heap.ArenaAllocator = .init(gpa);
    const a = arena.allocator();
    const found = library.family(gpa, a, folder, id) orelse catalog.find(gpa, a, catalog.default_id) orelse {
        arena.deinit();
        return null;
    };
    return .{ .arena = arena, .family = found };
}

/// The same family in an arena of its own, without reading it again.
fn cloneSlot(gpa: std.mem.Allocator, f: Family) ?Slot {
    var arena: std.heap.ArenaAllocator = .init(gpa);
    const copy = cloneFamily(arena.allocator(), f) catch {
        arena.deinit();
        return null;
    };
    return .{ .arena = arena, .family = copy };
}

fn cloneFamily(a: std.mem.Allocator, f: Family) !Family {
    var out = f;
    out.id = try a.dupe(u8, f.id);
    out.name = try a.dupe(u8, f.name);
    out.description = try a.dupe(u8, f.description);
    out.source = try a.dupe(u8, f.source);
    if (f.dark) |d| out.dark.?.name = try a.dupe(u8, d.name);
    if (f.light) |l| out.light.?.name = try a.dupe(u8, l.name);
    return out;
}

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

/// A contrast theme of Windows is on: the app's high contrast follows it,
/// as the Mac's follows "Increase contrast".
pub fn systemHighContrast() bool {
    var hc: w.c.HIGHCONTRASTW = std.mem.zeroes(w.c.HIGHCONTRASTW);
    hc.cbSize = @sizeOf(w.c.HIGHCONTRASTW);
    if (w.c.SystemParametersInfoW(w.c.SPI_GETHIGHCONTRAST, hc.cbSize, &hc, 0) == 0) return false;
    return hc.dwFlags & w.c.HCF_HIGHCONTRASTON != 0;
}

test "two families, a clone for the same id, an accent over both" {
    var s = Store.init(std.testing.allocator);
    defer s.deinit();
    _ = s.apply(.{ .dark = catalog.default_id, .light = catalog.default_id, .mode = .dark, .accent = 0xff0000 });
    try std.testing.expectEqual(@as(u32, 0xff0000), s.current.interface.accent);
    _ = s.apply(.{ .dark = "no-such-theme", .light = catalog.default_id, .mode = .light });
    try std.testing.expectEqualStrings(catalog.default_id, s.light.family.id);
}

test {
    w.refAllDeep(@This());
}
