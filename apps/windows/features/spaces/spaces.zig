//! The spaces feature (docs/spec/spaces.md): groups of tabs with a name,
//! one shown at a time, saved by themselves half a second after each change
//! to %APPDATA%\Cadex\spaces.json, in the Mac's format (SpacesFile.swift):
//! { "version": 1, "active": 0, "folder": "...", "spaces": [{ "name": ...,
//! "color": "blue", "tabs": <the tabs' snapshot> }] } (the color only when
//! set, plan 15), and restored at start. An unreadable
//! file is kept aside under another name and the app starts fresh.

const std = @import("std");
const w = @import("win32");
const icons = @import("icons");
const strings = @import("strings");
const palette = @import("command-palette");
const tabs = @import("tabs");

pub const Space = struct {
    name: []u8,
    tabs: *tabs.Tabs,
    /// A work color's name ("blue"): space.set-color, plan 15 phase D.
    color: ?[]u8 = null,
};

/// What the spaces need from the app.
pub const Host = struct {
    context: *anyopaque,
    /// A new, empty set of tabs wired to the app (terminals, documents).
    make_tabs: *const fn (context: *anyopaque) ?*tabs.Tabs,
    /// A document again from its identity, for the restore.
    make_document: tabs.snapshot.MakeDocument,
    /// The workspace folder, saved with the spaces and for new ones.
    folder: *const fn (context: *anyopaque) ?[]const u8,
    /// The space on screen changed: redraw, move the focus.
    shown: *const fn (context: *anyopaque) void,
    /// Arms the save timer (the app calls save() when it fires).
    schedule_save: *const fn (context: *anyopaque) void,
    /// Opens the palette with a list (space.switch).
    show_list: *const fn (context: *anyopaque, source: palette.Source) void,
    /// Asks for a name (space.rename); the app calls rename() with it.
    ask_name: *const fn (context: *anyopaque, current: []const u8) void,
};

pub const Spaces = struct {
    gpa: std.mem.Allocator,
    host: Host,
    list: std.ArrayList(Space) = .empty,
    active: usize = 0,
    /// The folder the last session had, for an app opened with none.
    saved_folder: ?[]u8 = null,

    pub fn deinit(self: *Spaces) void {
        for (self.list.items) |s| {
            s.tabs.deinit();
            self.gpa.destroy(s.tabs);
            self.gpa.free(s.name);
            if (s.color) |c| self.gpa.free(c);
        }
        self.list.deinit(self.gpa);
        if (self.saved_folder) |f| self.gpa.free(f);
    }

    pub fn current(self: *Spaces) *tabs.Tabs {
        return self.list.items[self.active].tabs;
    }

    pub fn name(self: *Spaces) []const u8 {
        return self.list.items[self.active].name;
    }

    /// The shown space's work color, if it has one.
    pub fn activeColor(self: *Spaces) ?[]const u8 {
        return self.list.items[self.active].color;
    }

    /// null takes the color off; saved like any other change.
    pub fn setActiveColor(self: *Spaces, color: ?[]const u8) void {
        const space = &self.list.items[self.active];
        if (space.color) |c| self.gpa.free(c);
        space.color = if (color) |c| self.gpa.dupe(u8, c) catch null else null;
        self.host.schedule_save(self.host.context);
    }

    fn path(self: *Spaces) ?[]u8 {
        // CADEX_SPACES_FILE points tests at a file of their own, as on the Mac.
        var buf: [1024]u16 = undefined;
        const n = w.c.GetEnvironmentVariableW(w.L("CADEX_SPACES_FILE"), &buf, buf.len);
        if (n > 0 and n < buf.len) return std.unicode.wtf16LeToWtf8Alloc(self.gpa, buf[0..n]) catch null;
        return w.files.appData(self.gpa, "spaces.json") catch null;
    }

    /// A space named "Space N" with no tabs yet; it becomes the one shown.
    pub fn add(self: *Spaces, given: ?[]const u8) ?*tabs.Tabs {
        const t = self.host.make_tabs(self.host.context) orelse return null;
        const label = if (given) |g| self.gpa.dupe(u8, g) catch return null else std.fmt.allocPrint(self.gpa, "Space {d}", .{self.list.items.len + 1}) catch return null;
        self.list.append(self.gpa, .{ .name = label, .tabs = t }) catch return null;
        self.active = self.list.items.len - 1;
        return t;
    }

    /// Restores the saved spaces; false when there were none to restore
    /// (the app then opens its first terminal).
    pub fn restore(self: *Spaces) bool {
        const file = self.path() orelse return false;
        defer self.gpa.free(file);
        var arena: std.heap.ArenaAllocator = .init(self.gpa);
        defer arena.deinit();
        const data = w.files.read(arena.allocator(), file, 16 * 1024 * 1024) orelse return false;
        const value = std.json.parseFromSliceLeaky(std.json.Value, arena.allocator(), data, .{}) catch {
            self.keepAside(file);
            return false;
        };
        if (value != .object) {
            self.keepAside(file);
            return false;
        }
        if (value.object.get("folder")) |f| if (f == .string) {
            self.saved_folder = self.gpa.dupe(u8, f.string) catch null;
        };
        const spaces = value.object.get("spaces") orelse return false;
        if (spaces != .array) return false;
        for (spaces.array.items) |s| {
            if (s != .object) continue;
            const n = if (s.object.get("name")) |v| (if (v == .string) v.string else null) else null;
            const t = self.add(n) orelse continue;
            if (s.object.get("color")) |c| if (c == .string) {
                self.list.items[self.list.items.len - 1].color = self.gpa.dupe(u8, c.string) catch null;
            };
            if (s.object.get("tabs")) |saved| tabs.snapshot.restore(t, saved, self.host.make_document);
            // A space saved without tabs comes back with a terminal.
            if (t.list.order.items.len == 0) t.newTab(self.host.folder(self.host.context));
        }
        if (self.list.items.len == 0) return false;
        if (value.object.get("active")) |a| if (a == .integer and a.integer >= 0 and a.integer < self.list.items.len) {
            self.active = @intCast(a.integer);
        };
        return true;
    }

    /// The bad file goes next to the good name, for nothing to be lost.
    fn keepAside(self: *Spaces, file: []const u8) void {
        const aside = std.fmt.allocPrint(self.gpa, "{s}.ilegivel", .{file}) catch return;
        defer self.gpa.free(aside);
        const from = std.unicode.wtf8ToWtf16LeAllocZ(self.gpa, file) catch return;
        defer self.gpa.free(from);
        const to = std.unicode.wtf8ToWtf16LeAllocZ(self.gpa, aside) catch return;
        defer self.gpa.free(to);
        _ = w.c.MoveFileExW(from.ptr, to.ptr, w.c.MOVEFILE_REPLACE_EXISTING);
    }

    pub fn save(self: *Spaces) void {
        const file = self.path() orelse return;
        defer self.gpa.free(file);
        var out: std.Io.Writer.Allocating = .init(self.gpa);
        defer out.deinit();
        var j: std.json.Stringify = .{ .writer = &out.writer, .options = .{ .whitespace = .indent_2 } };
        self.write(&j) catch return;
        w.files.writeAtomic(self.gpa, file, out.written()) catch |err| std.log.warn("spaces.json não foi salvo: {s}", .{@errorName(err)});
    }

    fn write(self: *Spaces, j: *std.json.Stringify) !void {
        try j.beginObject();
        try j.objectField("active");
        try j.write(self.active);
        try j.objectField("folder");
        try j.write(self.host.folder(self.host.context));
        try j.objectField("spaces");
        try j.beginArray();
        for (self.list.items) |s| {
            try j.beginObject();
            if (s.color) |c| {
                try j.objectField("color");
                try j.write(c);
            }
            try j.objectField("name");
            try j.write(s.name);
            try j.objectField("tabs");
            try tabs.snapshot.write(s.tabs, j);
            try j.endObject();
        }
        try j.endArray();
        try j.objectField("version");
        try j.write(1);
        try j.endObject();
    }

    pub fn select(self: *Spaces, index: usize) void {
        if (index >= self.list.items.len) return;
        self.active = index;
        self.host.shown(self.host.context);
        self.host.schedule_save(self.host.context);
    }

    pub fn step(self: *Spaces, by: i32) void {
        const n: i32 = @intCast(self.list.items.len);
        if (n < 2) return;
        self.select(@intCast(@mod(@as(i32, @intCast(self.active)) + by + n, n)));
    }

    pub fn rename(self: *Spaces, given: []const u8) void {
        const trimmed = std.mem.trim(u8, given, " ");
        // Empty keeps the name it had (docs/spec/spaces.md).
        if (trimmed.len == 0) return;
        const copy = self.gpa.dupe(u8, trimmed) catch return;
        self.gpa.free(self.list.items[self.active].name);
        self.list.items[self.active].name = copy;
        self.host.schedule_save(self.host.context);
    }

    /// Closes the shown space (after its tabs closed) and shows the one before.
    pub fn removeActive(self: *Spaces) void {
        if (self.list.items.len < 2) return;
        const gone = self.list.orderedRemove(self.active);
        gone.tabs.deinit();
        self.gpa.destroy(gone.tabs);
        self.gpa.free(gone.name);
        if (gone.color) |c| self.gpa.free(c);
        self.active -|= 1;
        self.host.shown(self.host.context);
        self.host.schedule_save(self.host.context);
    }

    // ---- The palette's list and the commands ----

    pub fn source(self: *Spaces) palette.Source {
        return .{ .context = self, .placeholder = strings.t("Switch space", "Trocar de space"), .empty_text = strings.t("No spaces", "Nenhum space"), .icon = icons.phosphor.stack, .search = search, .choose = choose };
    }

    fn search(context: *anyopaque, arena: std.mem.Allocator, query: []const u8, out: *std.ArrayList(palette.Item)) ?[]const u8 {
        const self: *Spaces = @ptrCast(@alignCast(context));
        for (self.list.items, 0..) |s, i| {
            if (query.len > 0 and std.ascii.indexOfIgnoreCase(s.name, query) == null) continue;
            const tabs_count = s.tabs.list.order.items.len;
            out.append(arena, .{
                .id = std.fmt.allocPrint(arena, "{d}", .{i}) catch continue,
                .title = s.name,
                // Two spaces with one name: the position tells them apart.
                .detail = std.fmt.allocPrint(arena, "{d}{s} · {d} {s}{s}", .{ i + 1, strings.t("", "º"), tabs_count, if (tabs_count == 1) strings.t("tab", "aba") else strings.t("tabs", "abas"), if (i == self.active) strings.t(" · current", " · atual") else "" }) catch "",
                .icon = icons.phosphor.stack,
            }) catch {};
        }
        return null;
    }

    fn choose(context: *anyopaque, id: []const u8, _: palette.How) void {
        const self: *Spaces = @ptrCast(@alignCast(context));
        self.select(std.fmt.parseInt(usize, id, 10) catch return);
    }

    pub fn register(self: *Spaces, registry: *palette.Registry) void {
        target = self;
        registry.add(.{ .id = "space.switch", .title = strings.t("Switch Space", "Trocar de space"), .keywords = &.{ "space", "grupo", "projeto", "switch", "group", "project" }, .shortcut = "cmd+shift+s", .run = switchSpace });
        registry.add(.{ .id = "space.new", .title = strings.t("New Space", "Novo space"), .keywords = &.{ "space", "grupo", "criar", "new" }, .shortcut = "ctrl+cmd+n", .run = newSpace });
        registry.add(.{ .id = "space.rename", .title = strings.t("Rename Space", "Renomear space"), .keywords = &.{ "space", "nome", "rename" }, .run = renameSpace });
        registry.add(.{ .id = "space.close", .title = strings.t("Close Space", "Fechar space"), .keywords = &.{ "space", "fechar", "close" }, .run = closeSpace, .available = hasTwo });
        registry.add(.{ .id = "space.next", .title = strings.t("Next Space", "Próximo space"), .keywords = &.{ "space", "alternar", "next" }, .shortcut = "ctrl+cmd+right", .windows_shortcut = "cmd+shift+pagedown", .run = nextSpace, .available = hasTwo });
        registry.add(.{ .id = "space.previous", .title = strings.t("Previous Space", "Space anterior"), .keywords = &.{ "space", "alternar", "previous" }, .shortcut = "ctrl+cmd+left", .windows_shortcut = "cmd+shift+pageup", .run = previousSpace, .available = hasTwo });
    }
};

var target: *Spaces = undefined;

fn switchSpace(_: ?*anyopaque) void {
    target.host.show_list(target.host.context, target.source());
}
fn newSpace(_: ?*anyopaque) void {
    const t = target.add(null) orelse return;
    t.newTab(target.host.folder(target.host.context));
    target.host.shown(target.host.context);
    target.host.schedule_save(target.host.context);
}
fn renameSpace(_: ?*anyopaque) void {
    target.host.ask_name(target.host.context, target.name());
}
fn closeSpace(_: ?*anyopaque) void {
    // The tabs ask first (programs running, unsaved files); when they all
    // closed, the app's on_empty removes the space.
    target.current().requestClose(.all);
}
fn hasTwo(_: ?*anyopaque) bool {
    return target.list.items.len > 1;
}
fn nextSpace(_: ?*anyopaque) void {
    target.step(1);
}
fn previousSpace(_: ?*anyopaque) void {
    target.step(-1);
}

test {
    w.refAllDeep(@This());
}
