//! Find in the file (edit.find, docs/spec/editor.md "Editar"): a bar at the
//! top right of the view, every match in amber and the current one in
//! orange, as the terminal's find; Enter and Shift+Enter go through them,
//! Esc closes and gives the keys back to the text. Ignores case.

const std = @import("std");
const strings = @import("strings");
const gfx = @import("gfx");
const w = @import("win32");
const ui_mod = @import("ui");
const icons = @import("icons");
const View = @import("view.zig").View;

const Ui = ui_mod.Ui;

/// More than this many matches is not worth counting on screen.
const max_matches = 10_000;

pub const Find = struct {
    open: bool = false,
    field: ui_mod.TextBuffer = .{},
    field_scroll: ui_mod.text_field.Scroll = .{},
    /// Start bytes of the matches, in order.
    matches: std.ArrayList(usize) = .empty,
    current: ?usize = null,
    /// The text and query the matches are for.
    built_version: u64 = std.math.maxInt(u64),
    built_query: u64 = 0,

    pub fn deinit(self: *Find, gpa: std.mem.Allocator) void {
        self.field.deinit(gpa);
        self.matches.deinit(gpa);
    }

    pub fn query(self: *const Find) []const u8 {
        return self.field.text();
    }

    fn fieldId(view: *const View) ui_mod.Id {
        return ui_mod.child(view.id, 0xf1d);
    }

    /// Opens the bar with the field focused; a selection on one line
    /// becomes the query.
    pub fn show(self: *Find, u: *Ui, view: *View) void {
        const picked = view.buffer.selected();
        if (picked.len > 0 and picked.len < 200 and std.mem.indexOfScalar(u8, picked, '\n') == null) {
            self.field.set(view.gpa, picked) catch {};
        }
        self.field.selectAll();
        self.open = true;
        self.built_version = std.math.maxInt(u64);
        u.focus = fieldId(view);
    }

    pub fn hide(self: *Find, u: *Ui, view: *View) void {
        self.open = false;
        if (u.focus == fieldId(view)) u.focus = view.id;
    }

    /// The matches that overlap [start, end).
    pub fn matchesIn(self: *const Find, start: usize, end: usize) []const usize {
        const len = self.query().len;
        const items = self.matches.items;
        const lo = std.sort.lowerBound(usize, items, (start + 1) -| len, order);
        const hi = std.sort.lowerBound(usize, items, end, order);
        return items[lo..@max(lo, hi)];
    }

    fn order(key: usize, item: usize) std.math.Order {
        return std.math.order(key, item);
    }

    fn search(self: *Find, view: *View) void {
        const q = self.query();
        const key = std.hash.Wyhash.hash(0, q);
        if (self.built_version == view.buffer.version and self.built_query == key) return;
        self.built_version = view.buffer.version;
        self.built_query = key;
        self.matches.clearRetainingCapacity();
        self.current = null;
        if (q.len == 0) return;
        const hay = view.text();
        var at: usize = 0;
        while (self.matches.items.len < max_matches) {
            const found = std.ascii.indexOfIgnoreCasePos(hay, at, q) orelse break;
            self.matches.append(view.gpa, found) catch break;
            at = found + q.len;
        }
        // The first match at or after the caret is current.
        const caret = view.buffer.selection().start;
        for (self.matches.items, 0..) |m, i| if (m >= caret) {
            self.current = i;
            break;
        };
        if (self.current == null and self.matches.items.len > 0) self.current = 0;
    }

    /// Selects the next (or previous) match and scrolls to it.
    fn go(self: *Find, view: *View, forward: bool) void {
        const n = self.matches.items.len;
        if (n == 0) return;
        self.current = if (self.current) |c| (if (forward) (c + 1) % n else (c + n - 1) % n) else 0;
        self.select(view);
    }

    fn select(self: *Find, view: *View) void {
        const c = self.current orelse return;
        const m = self.matches.items[c];
        view.buffer.selectRange(m, m + self.query().len);
        view.reveal_caret = true;
    }

    pub fn draw(self: *Find, u: *Ui, view: *View, area: gfx.Rect) void {
        const id = fieldId(view);
        const bar_w = @min(u.px(360), area.w - u.px(16));
        const bar: gfx.Rect = .{ .x = area.right() - bar_w - u.px(18), .y = area.y + u.px(8), .w = bar_w, .h = u.px(34) };
        // Over the text: a click on the bar is not a click on the text.
        u.beginOverlay(bar);
        defer u.endOverlay();
        u.painter.fillRounded(bar.inset(-1, -1), u.px(8), u.style.panel_border);
        u.painter.fillRounded(bar, u.px(8), u.style.panel);
        var inner = bar.inset(u.px(5), u.px(4));
        const close_r = inner.takeRight(u.px(26));
        const next_r = inner.takeRight(u.px(26));
        const prev_r = inner.takeRight(u.px(26));
        var count_buf: [32]u8 = undefined;
        const count_r = inner.takeRight(u.px(78));
        const focused = u.focus == id;
        const back = focused and u.key(w.c.VK_RETURN, .{ .shift = true });
        const result = ui_mod.text_field.textField(u, id, inner, &self.field, &self.field_scroll, .{ .placeholder = strings.t("Find in file", "Buscar no arquivo") });
        self.search(view);
        if (result.changed) self.select(view);
        if (result.submitted) self.go(view, true);
        if (back) self.go(view, false);
        const label = if (self.query().len == 0)
            ""
        else if (self.matches.items.len == 0)
            strings.t("None", "Nenhum")
        else
            std.fmt.bufPrint(&count_buf, "{d} {s} {d}", .{ (self.current orelse 0) + 1, strings.t("of", "de"), self.matches.items.len }) catch "";
        u.painter.text(label, u.style.small(), count_r, u.style.secondary_text, .{ .@"align" = .trailing });
        if (ui_mod.widgets.iconButton(u, ui_mod.child(id, 1), prev_r, icons.phosphor.caret_up, .{ .icon_size = 13 })) self.go(view, false);
        if (ui_mod.widgets.iconButton(u, ui_mod.child(id, 2), next_r, icons.phosphor.caret_down, .{ .icon_size = 13 })) self.go(view, true);
        const closed = ui_mod.widgets.iconButton(u, ui_mod.child(id, 3), close_r, icons.phosphor.x, .{ .icon_size = 13 });
        if (closed or result.cancelled) self.hide(u, view);
    }
};

test {
    @import("win32").refAllDeep(@This());
}
