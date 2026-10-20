//! The palette (Ctrl+Shift+K, the Mac's ⌘K): a field on top of the window
//! and the rows of the current list below. Opening the list that is open
//! closes it; another list's shortcut switches to it with the field empty.
//! Prefixes at the start of the field switch the list without leaving it:
//! `>` commands, `/` files, `#` text, `@` tabs and spaces.
//!
//! The chosen row runs after the frame (takePending), with the palette
//! already closed, so a command sees the window as the user left it.

const std = @import("std");
const gfx = @import("gfx");
const ui_mod = @import("ui");
const w = @import("win32");
const icons = @import("icons");
const source_mod = @import("source.zig");

const Ui = ui_mod.Ui;
const Source = source_mod.Source;
const Item = source_mod.Item;
const How = source_mod.How;

pub const Prefix = struct {
    char: u8,
    /// Shown in the footer with the field empty ("arquivos").
    label: []const u8,
    source: Source,
};

pub const Pending = struct {
    source: Source,
    id: []u8,
    how: How,
};

pub const Palette = struct {
    gpa: std.mem.Allocator,
    commands: Source,
    prefixes: std.ArrayList(Prefix) = .empty,
    /// The list opened directly (commands, files...); null when closed.
    opened: ?Source = null,
    query: ui_mod.TextBuffer = .{},
    field_scroll: ui_mod.text_field.Scroll = .{},
    list_scroll: ui_mod.list.Scroll = .{},
    selected: usize = 0,
    arena: std.heap.ArenaAllocator,
    pending: ?Pending = null,
    /// The query the current list last saw, to reset it on change.
    last_query: std.ArrayList(u8) = .empty,
    field_id: ui_mod.Id = ui_mod.id("palette.field", 0),

    pub fn init(gpa: std.mem.Allocator, commands: Source) Palette {
        return .{ .gpa = gpa, .commands = commands, .arena = .init(gpa) };
    }

    pub fn deinit(self: *Palette) void {
        self.prefixes.deinit(self.gpa);
        self.query.deinit(self.gpa);
        self.arena.deinit();
        self.last_query.deinit(self.gpa);
        if (self.pending) |p| self.gpa.free(p.id);
    }

    pub fn addPrefix(self: *Palette, prefix: Prefix) void {
        self.prefixes.append(self.gpa, prefix) catch {};
    }

    pub fn isOpen(self: *const Palette) bool {
        return self.opened != null;
    }

    /// Shows `source`; the same one again closes the palette.
    pub fn toggle(self: *Palette, ui: *Ui, source: Source) void {
        if (self.opened) |o| {
            if (o.context == source.context and std.mem.eql(u8, o.placeholder, source.placeholder)) return self.close(ui);
        }
        self.resetCurrent();
        self.opened = source;
        self.query.set(self.gpa, "") catch {};
        self.selected = 0;
        self.list_scroll = .{};
        ui.focus = self.field_id;
    }

    pub fn close(self: *Palette, ui: *Ui) void {
        self.resetCurrent();
        self.opened = null;
        if (ui.focus == self.field_id) ui.focus = ui_mod.context.none;
    }

    fn resetCurrent(self: *Palette) void {
        if (self.opened == null) return;
        const shown = self.current().source;
        if (shown.reset) |r| r(shown.context);
        self.last_query.clearRetainingCapacity();
    }

    /// The list in use and the query it gets, after a prefix.
    fn current(self: *Palette) struct { source: Source, query: []const u8 } {
        const opened = self.opened.?;
        const text = self.query.text();
        if (opened.context == self.commands.context and text.len > 0) {
            if (text[0] == '>') return .{ .source = self.commands, .query = std.mem.trimStart(u8, text[1..], " ") };
            for (self.prefixes.items) |p| {
                if (text[0] == p.char) return .{ .source = p.source, .query = std.mem.trimStart(u8, text[1..], " ") };
            }
        }
        return .{ .source = opened, .query = text };
    }

    /// The row the user chose, taken once, after the frame that chose it.
    pub fn takePending(self: *Palette) ?Pending {
        const p = self.pending orelse return null;
        self.pending = null;
        return p;
    }

    pub fn draw(self: *Palette, ui: *Ui) void {
        if (self.opened == null) return;
        _ = self.arena.reset(.retain_capacity);
        const a = self.arena.allocator();
        const list = self.current();
        if (!std.mem.eql(u8, list.query, self.last_query.items)) {
            if (list.source.reset) |r| r(list.source.context);
            self.last_query.clearRetainingCapacity();
            self.last_query.appendSlice(self.gpa, list.query) catch {};
            self.selected = 0;
            self.list_scroll = .{};
        }
        var items: std.ArrayList(Item) = .empty;
        const note = list.source.search(list.source.context, a, list.query, &items);

        const width = @min(ui.px(640), ui.size.x - ui.px(32));
        const box_x = (ui.size.x - width) / 2;
        const field_h = ui.px(46);
        const row_h = ui.px(34);
        const header_h = ui.px(26);
        const footer_h = ui.px(30);
        var content_h: f32 = 0;
        for (items.items) |item| content_h += row_h + if (item.section.len > 0) header_h else 0;
        const list_h = @min(@max(content_h, row_h), ui.px(420));
        const box: gfx.Rect = .{ .x = box_x, .y = ui.px(56), .w = width, .h = field_h + list_h + footer_h + ui.px(8) };

        ui.beginOverlay(.{ .x = 0, .y = 0, .w = ui.size.x, .h = ui.size.y });
        defer ui.endOverlay();
        const radius = ui.px(14);
        ui.painter.fillRounded(box.inset(-1, -1), radius, ui.style.panel_border);
        ui.painter.fillRounded(box, radius, ui.style.panel);

        var inner = box;
        var field_row = inner.takeTop(field_h);
        ui.painter.icon(list.source.icon, ui.px(18), field_row.takeLeft(ui.px(44)), ui.style.secondary_text);
        if (note) |n| {
            const nw = ui.painter.measure(n, ui.style.small()) + ui.px(16);
            ui.painter.text(n, ui.style.small(), field_row.takeRight(nw), ui.style.secondary_text, .{ .@"align" = .center });
        }
        const result = ui_mod.text_field.textField(ui, self.field_id, field_row, &self.query, &self.field_scroll, .{
            .placeholder = list.source.placeholder,
            .framed = false,
            .spec = ui.style.font(15),
        });
        ui.painter.fill(.{ .x = box.x, .y = inner.y, .w = box.w, .h = @max(1, ui.px(1)) }, ui.style.panel_border);

        const list_area = inner.takeTop(list_h).inset(ui.px(6), ui.px(4));
        const footer = inner.takeBottom(footer_h);
        self.handleKeys(ui, items.items, list.source, result, @intFromFloat(list_area.h / row_h));
        if (self.opened == null) return;
        self.drawRows(ui, list_area, items.items, row_h, header_h, list.source, content_h);
        if (items.items.len == 0) ui.painter.text(list.source.empty_text, ui.style.ui(), list_area, ui.style.secondary_text, .{ .@"align" = .center });
        self.drawFooter(ui, footer, list.source);

        // A click outside closes it, as losing focus does on the Mac.
        if ((ui.input.pressed[0] or ui.input.pressed[1]) and !box.contains(ui.input.mouse)) self.close(ui);
    }

    fn handleKeys(self: *Palette, ui: *Ui, items: []const Item, source: Source, result: ui_mod.text_field.Result, page: usize) void {
        if (result.cancelled) return self.close(ui);
        if (items.len == 0) return;
        self.selected = ui_mod.list.keyboardSelect(ui, self.selected, items.len, @max(page, 1));
        const c = w.c;
        var how: ?How = if (result.submitted) .normal else null;
        if (source.opens_files) {
            if (ui.key(c.VK_RETURN, .{ .alt = true })) how = .beside;
            if (ui.key(c.VK_RETURN, .{ .ctrl = true })) how = .new_tab;
        }
        if (how) |h| self.choose(ui, source, items[@min(self.selected, items.len - 1)].id, h);
    }

    fn choose(self: *Palette, ui: *Ui, source: Source, id: []const u8, how: How) void {
        if (self.pending) |p| self.gpa.free(p.id);
        self.pending = .{ .source = source, .id = self.gpa.dupe(u8, id) catch return, .how = how };
        self.close(ui);
    }

    fn drawRows(self: *Palette, ui: *Ui, area: gfx.Rect, items: []const Item, row_h: f32, header_h: f32, source: Source, content_h: f32) void {
        ui_mod.list.scrollArea(ui, ui_mod.id("palette.list", 0), area, content_h, &self.list_scroll);
        // Keep the selection in view.
        var top: f32 = 0;
        for (items[0..@min(self.selected, items.len)], 0..) |item, i| {
            _ = i;
            top += row_h + if (item.section.len > 0) header_h else 0;
        }
        if (self.selected < items.len and items[self.selected].section.len > 0) top += header_h;
        self.list_scroll.reveal(top, row_h, area.h);
        self.list_scroll.clamp(content_h, area.h);

        ui.painter.pushClip(area);
        defer ui.painter.popClip();
        var y = area.y - self.list_scroll.offset;
        for (items, 0..) |item, i| {
            if (item.section.len > 0) {
                if (y + header_h > area.y and y < area.bottom())
                    ui.painter.text(item.section, ui.style.small(), .{ .x = area.x + ui.px(10), .y = y, .w = area.w, .h = header_h }, ui.style.secondary_text, .{});
                y += header_h;
            }
            const row: gfx.Rect = .{ .x = area.x, .y = y, .w = area.w, .h = row_h };
            y += row_h;
            if (row.bottom() < area.y or row.y > area.bottom()) continue;
            const row_id = ui_mod.child(ui_mod.id("palette.row", 0), i);
            if (ui.mouseOver(row) and (ui.input.mouse.x != 0 or ui.input.mouse.y != 0)) {
                ui.next_hot = row_id;
                if (ui.input.pressed[0]) self.selected = i;
            }
            if (ui.clickable(row_id, row)) self.choose(ui, source, item.id, .normal);
            if (i == self.selected) ui.painter.fillRounded(row, ui.px(8), ui.style.tab_active);
            var content = row.inset(ui.px(10), 0);
            const icon_rect = content.takeLeft(ui.px(26));
            const material = item.file_name.len > 0 and icons.material.drawNamed(ui.painter, item.file_name, false, @round(ui.px(16)), icon_rect);
            if (!material) ui.painter.icon(item.icon, ui.px(16), icon_rect, item.icon_color orelse ui.style.secondary_text);
            if (item.shortcut.len > 0) {
                const sw = ui.painter.measure(item.shortcut, ui.style.small()) + ui.px(16);
                const chip = content.takeRight(sw);
                ui.painter.fillRounded(.{ .x = chip.x, .y = chip.center().y - ui.px(10), .w = chip.w, .h = ui.px(20) }, ui.px(5), ui.style.field);
                ui.painter.text(item.shortcut, ui.style.small(), chip, ui.style.secondary_text, .{ .@"align" = .center, .ellipsis = false });
            }
            const title_w = ui.painter.measure(item.title, ui.style.ui()) + ui.px(10);
            ui.painter.textBold(item.title, ui.style.ui(), content.takeLeft(@min(title_w, content.w)), ui.style.text, item.bold);
            if (item.detail.len > 0) ui.painter.text(item.detail, ui.style.small(), content, ui.style.secondary_text, .{});
        }
        if (self.opened == null) return;
    }

    fn drawFooter(self: *Palette, ui: *Ui, r: gfx.Rect, source: Source) void {
        ui.painter.fill(.{ .x = r.x, .y = r.y, .w = r.w, .h = @max(1, ui.px(1)) }, ui.style.panel_border);
        var row = r.inset(ui.px(14), 0);
        const a = self.arena.allocator();
        var hints: std.ArrayList([]const u8) = .empty;
        hints.append(a, "↩ executar") catch {};
        if (source.opens_files) {
            hints.append(a, "Alt+↩ ao lado") catch {};
            hints.append(a, "Ctrl+↩ nova aba") catch {};
        }
        hints.append(a, "↑↓ mover") catch {};
        hints.append(a, "esc fechar") catch {};
        if (self.query.text().len == 0 and source.context == self.commands.context) {
            for (self.prefixes.items) |p| hints.append(a, std.fmt.allocPrint(a, "{c} {s}", .{ p.char, p.label }) catch continue) catch {};
        }
        for (hints.items) |hint| {
            const hw = ui.painter.measure(hint, ui.style.small()) + ui.px(16);
            if (hw > row.w) break;
            ui.painter.text(hint, ui.style.small(), row.takeLeft(hw), ui.style.secondary_text, .{ .ellipsis = false });
        }
    }
};

test {
    @import("win32").refAllDeep(@This());
}
