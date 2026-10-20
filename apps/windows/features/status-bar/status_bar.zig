//! The status bar (docs/spec/status-bar.md): on the left the focused
//! terminal's folder as a trail; a piece opens a menu of the subfolders
//! of that level, and choosing one takes the terminal there (`cd`), only
//! while the shell waits at its prompt. On the right, the environment:
//! "Local", or the WSL distribution.

const std = @import("std");
const gfx = @import("gfx");
const ui = @import("ui");
const w = @import("win32");
const icons = @import("icons");
const breadcrumb = @import("breadcrumb.zig");

pub const Piece = breadcrumb.Piece;
pub const pieces = breadcrumb.pieces;

pub const StatusBar = struct {
    menu: ui.menu.Menu = .{},
    /// The level whose menu is open, and its subfolders (owned).
    menu_path: std.ArrayList(u8) = .empty,
    entries: std.ArrayList([]u8) = .empty,

    pub fn deinit(self: *StatusBar, gpa: std.mem.Allocator) void {
        self.clearEntries(gpa);
        self.entries.deinit(gpa);
        self.menu_path.deinit(gpa);
    }

    fn clearEntries(self: *StatusBar, gpa: std.mem.Allocator) void {
        for (self.entries.items) |e| gpa.free(e);
        self.entries.clearRetainingCapacity();
    }

    pub const Result = struct {
        /// A subfolder was chosen: the terminal goes there.
        go_to: ?[]const u8 = null,
    };

    /// `folder`: the focused terminal's, or null while it is unknown.
    /// `busy`: a program runs, so the menu's folders are dimmed.
    pub fn draw(self: *StatusBar, u: *ui.Ui, area: gfx.Rect, folder: ?[]const u8, home: ?[]const u8, environment: []const u8, busy: bool) Result {
        var result: Result = .{};
        var row = area.inset(u.px(10), 0);
        const env_w = u.painter.measure(environment, u.style.small()) + u.px(12);
        u.painter.text(environment, u.style.small(), row.takeRight(env_w), u.style.secondary_text, .{ .@"align" = .trailing });
        const dir = folder orelse return result;
        var arena: std.heap.ArenaAllocator = .init(u.gpa);
        defer arena.deinit();
        const list = pieces(arena.allocator(), dir, home) catch return result;
        // The middle pieces become "…" when the trail does not fit; the
        // current folder never goes.
        var total: f32 = 0;
        const sep_w = u.painter.measure(" › ", u.style.small());
        for (list) |p| total += u.painter.measure(p.name, u.style.small()) + sep_w + u.px(8);
        const skip_from: usize = if (total > row.w and list.len > 2) 1 else list.len;
        var i: usize = 0;
        while (i < list.len) : (i += 1) {
            if (i == skip_from) {
                const dots = row.takeLeft(u.painter.measure("… › ", u.style.small()));
                u.painter.text("… › ", u.style.small(), dots, u.style.secondary_text, .{ .ellipsis = false });
                while (i < list.len - 1 and remaining(u, list[i + 1 ..], sep_w) > row.w) i += 1;
                continue;
            }
            const p = list[i];
            const name_w = u.painter.measure(p.name, u.style.small()) + u.px(8);
            const r = row.takeLeft(name_w);
            const id = ui.child(ui.id("status.piece", 0), i);
            if (ui.widgets.button(u, id, r.inset(0, u.px(3)), p.name, .{ .radius = 4, .@"align" = .{ .@"align" = .center }, .color = if (i == list.len - 1) u.style.text else u.style.secondary_text })) {
                self.openMenu(u.gpa, p.path);
                self.menu.open(ui.id("status.menu", 0), .{ .x = r.x, .y = area.y });
            }
            if (i + 1 < list.len) u.painter.text(" › ", u.style.small(), row.takeLeft(sep_w), u.style.secondary_text, .{ .ellipsis = false });
        }
        result.go_to = self.drawMenu(u, busy);
        return result;
    }

    fn remaining(u: *ui.Ui, list: []const Piece, sep_w: f32) f32 {
        var t: f32 = 0;
        for (list) |p| t += u.painter.measure(p.name, u.style.small()) + sep_w + u.px(8);
        return t;
    }

    fn openMenu(self: *StatusBar, gpa: std.mem.Allocator, path: []const u8) void {
        self.clearEntries(gpa);
        self.menu_path.clearRetainingCapacity();
        self.menu_path.appendSlice(gpa, path) catch return;
        listFolders(gpa, path, &self.entries);
    }

    fn drawMenu(self: *StatusBar, u: *ui.Ui, busy: bool) ?[]const u8 {
        const owner = ui.id("status.menu", 0);
        if (!self.menu.isOpen(owner)) return null;
        var items: std.ArrayList(ui.menu.Item) = .empty;
        defer items.deinit(u.gpa);
        if (self.entries.items.len == 0) items.append(u.gpa, .{ .label = "Sem acesso", .enabled = false }) catch {};
        for (self.entries.items) |e| {
            const name = std.fs.path.basenameWindows(e);
            items.append(u.gpa, .{ .label = name, .icon = icons.phosphor.folder, .enabled = !busy }) catch {};
        }
        // Opened at the bar's top, it does not fit below and opens above.
        const chosen = ui.menu.show(u, &self.menu, owner, items.items);
        if (chosen) |i| if (i < self.entries.items.len) return self.entries.items[i];
        return null;
    }
};

/// The subfolders of `path`, sorted, hidden ones left out.
fn listFolders(gpa: std.mem.Allocator, path: []const u8, out: *std.ArrayList([]u8)) void {
    const c = w.c;
    const pattern = std.fmt.allocPrint(gpa, "{s}\\*", .{std.mem.trimEnd(u8, path, "\\/")}) catch return;
    defer gpa.free(pattern);
    const wide = std.unicode.wtf8ToWtf16LeAllocZ(gpa, pattern) catch return;
    defer gpa.free(wide);
    var data: c.WIN32_FIND_DATAW = undefined;
    const find = c.FindFirstFileW(wide.ptr, &data);
    if (find == c.INVALID_HANDLE_VALUE) return;
    defer _ = c.FindClose(find);
    while (true) {
        const is_dir = data.dwFileAttributes & c.FILE_ATTRIBUTE_DIRECTORY != 0;
        const hidden = data.dwFileAttributes & (c.FILE_ATTRIBUTE_HIDDEN | c.FILE_ATTRIBUTE_SYSTEM) != 0;
        const name = std.unicode.wtf16LeToWtf8Alloc(gpa, std.mem.sliceTo(&data.cFileName, 0)) catch null;
        if (name) |n| {
            defer gpa.free(n);
            if (is_dir and !hidden and n[0] != '.') {
                const full = std.fmt.allocPrint(gpa, "{s}\\{s}", .{ std.mem.trimEnd(u8, path, "\\/"), n }) catch null;
                if (full) |f| out.append(gpa, f) catch gpa.free(f);
            }
        }
        if (c.FindNextFileW(find, &data) == 0) break;
    }
    std.mem.sort([]u8, out.items, {}, struct {
        fn lessThan(_: void, a: []u8, b: []u8) bool {
            return std.ascii.lessThanIgnoreCase(a, b);
        }
    }.lessThan);
}

test {
    _ = @import("breadcrumb.zig");
    std.testing.refAllDecls(@This());
}
