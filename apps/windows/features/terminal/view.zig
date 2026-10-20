//! A terminal pane: sizes the session to its rectangle, draws its frame,
//! and handles the mouse (selection, the wheel, programs that track the
//! mouse, Ctrl+click on links). Keys come from the window directly
//! (keyDown, typeText), before any widget, so nothing is lost or delayed.

const std = @import("std");
const gfx = @import("gfx");
const ui_mod = @import("ui");
const w = @import("win32");
const cadex = @import("cadex");
const session_mod = @import("session.zig");
const font_mod = @import("font.zig");
const renderer = @import("renderer.zig");
const keys = @import("keys.zig");
const find_mod = @import("find.zig");

const Session = session_mod.Session;
const Ui = ui_mod.Ui;
const c = w.c;

/// Space around the grid, as on the Mac (8 pt).
const padding_dips = 8;

/// What the pane asks of whoever holds it (the tabs, the app).
pub const Hooks = struct {
    context: ?*anyopaque = null,
    /// Ctrl+click on a link: a URL (kind CADEX_LINK_URL) or an existing path.
    open_link: ?*const fn (context: ?*anyopaque, kind: u8, target: []const u8) void = null,
};

pub const View = struct {
    gpa: std.mem.Allocator,
    session: *Session,
    id: ui_mod.Id,
    hooks: Hooks = .{},
    cols: u16 = 0,
    rows: u16 = 0,
    cell_w: f32 = 0,
    cell_h: f32 = 0,
    /// The theme's selection color.
    selection_color: ?u32 = null,
    find: find_mod.Find = .{},
    /// Bell flash start (ms), to fade it.
    flash_from: i64 = 0,
    /// Last scroll by the user (ms): the scrollbar shows for a moment.
    scrolled_at: i64 = 0,
    autoscroll: i8 = 0,
    selecting: bool = false,
    /// The program asked for the mouse and got the press.
    tracking_press: ?u8 = null,
    wheel_rest: i32 = 0,

    pub fn init(gpa: std.mem.Allocator, session: *Session, id: ui_mod.Id) View {
        return .{ .gpa = gpa, .session = session, .id = id };
    }

    pub fn deinit(self: *View) void {
        self.find.deinit(self.gpa);
        self.session.close();
    }

    fn padding(ui: *const Ui) f32 {
        return ui.px(padding_dips);
    }

    /// The grid for `area`; resizes the session when it changes.
    fn fit(self: *View, ui: *Ui, font: *font_mod.Font, area: gfx.Rect) void {
        const m = font.metrics;
        const pad = 2 * padding(ui);
        const cols: u16 = @intFromFloat(@max(@floor((area.w - pad) / m.cell_width), 2));
        const rows: u16 = @intFromFloat(@max(@floor((area.h - pad) / m.cell_height), 1));
        if (cols == self.cols and rows == self.rows and m.cell_width == self.cell_w and m.cell_height == self.cell_h) return;
        self.cols = cols;
        self.rows = rows;
        self.cell_w = m.cell_width;
        self.cell_h = m.cell_height;
        _ = cadex.cadex_terminal_resize(self.session.terminal, cols, rows, @intFromFloat(m.cell_width), @intFromFloat(m.cell_height));
    }

    pub fn draw(self: *View, ui: *Ui, font: *font_mod.Font, area: gfx.Rect, focused: bool) void {
        self.fit(ui, font, area);
        if (focused) self.handleMouse(ui, font, area) else if (ui.pressedOn(area, .left)) ui.focus = self.id;
        if (ui.mouseOver(area)) ui.cursor = .ibeam;
        const link = self.hoveredLink(ui, font, area);
        var frame_ptr: [*c]const cadex.cadex_terminal_frame = null;
        if (cadex.cadex_terminal_update_frame(self.session.terminal, &frame_ptr) != cadex.CADEX_OK or frame_ptr == null) return;
        const frame: *const cadex.cadex_terminal_frame = frame_ptr;
        self.session.drew();
        const flash = 1 - @min(@as(f32, @floatFromInt(ui.now_ms - self.flash_from)) / 250, 1);
        if (flash > 0) ui.requestFrame(16);
        const blink_hidden = frame.cursor_blinking and focused and @mod(@divTrunc(ui.now_ms, 530), 2) == 1;
        if (frame.cursor_blinking and focused) ui.requestFrame(530 - @as(u32, @intCast(@mod(ui.now_ms, 530))));
        const scrollbar = frame.scroll_offset + frame.rows < frame.scroll_total or ui.now_ms - self.scrolled_at < 1000;
        if (ui.now_ms - self.scrolled_at < 1000) ui.requestFrame(@intCast(1000 - (ui.now_ms - self.scrolled_at)));
        renderer.draw(ui.painter, font, frame, area, padding(ui), .{
            .selection = self.selection_color,
            .link = link,
            .hide_cursor = blink_hidden or self.find.open,
            .flash = flash,
            .focused = focused,
            .composition = if (focused) ui.input.composition.items else "",
            .show_scrollbar = scrollbar,
        });
        if (focused) {
            const pad = padding(ui);
            ui.ime_caret = .{
                .x = area.x + pad + @as(f32, @floatFromInt(frame.cursor_x)) * font.metrics.cell_width,
                .y = area.y + pad + @as(f32, @floatFromInt(frame.cursor_y)) * font.metrics.cell_height,
                .w = font.metrics.cell_width,
                .h = font.metrics.cell_height,
            };
        }
        if (self.find.open) self.find.draw(ui, self.session, area, self.id);
        if (self.autoscroll != 0 and ui.input.down[0]) ui.requestFrame(15);
    }

    fn cellAt(self: *const View, ui: *const Ui, area: gfx.Rect, p: gfx.Point) struct { col: u16, row: u16 } {
        const pad = padding(ui);
        const col = @max((p.x - area.x - pad) / self.cell_w, 0);
        const row = @max((p.y - area.y - pad) / self.cell_h, 0);
        return .{
            .col = @min(@as(u16, @intFromFloat(col)), self.cols -| 1),
            .row = @min(@as(u16, @intFromFloat(row)), self.rows -| 1),
        };
    }

    fn pointer(self: *const View, ui: *const Ui, area: gfx.Rect) cadex.cadex_terminal_pointer {
        const p = ui.input.mouse;
        const cell = self.cellAt(ui, area, p);
        return .{
            .x = p.x - area.x,
            .y = p.y - area.y,
            .col = cell.col,
            .row = cell.row,
            .cell_width = @intFromFloat(self.cell_w),
            .padding_left = @intFromFloat(padding(ui)),
            .view_height = @intFromFloat(area.h),
        };
    }

    fn mouseEvent(self: *const View, ui: *const Ui, area: gfx.Rect, action: u8, button: u8) cadex.cadex_terminal_mouse_event {
        return .{
            .x = ui.input.mouse.x - area.x,
            .y = ui.input.mouse.y - area.y,
            .view_width = @intFromFloat(area.w),
            .view_height = @intFromFloat(area.h),
            .cell_width = @intFromFloat(self.cell_w),
            .cell_height = @intFromFloat(self.cell_h),
            .padding = @intFromFloat(padding(ui)),
            .action = action,
            .button = button,
            .mods = keys.modsOf(ui.input.mods),
        };
    }

    fn handleMouse(self: *View, ui: *Ui, font: *font_mod.Font, area: gfx.Rect) void {
        _ = font;
        const t = self.session.terminal;
        const over = ui.mouseOver(area);
        // Shift forces the local selection even when the program tracks the mouse.
        const tracking = cadex.cadex_terminal_mouse_tracking(t) != cadex.CADEX_MOUSE_TRACKING_NONE and !ui.input.mods.shift;
        if (over and ui.input.wheel != 0) {
            // Three rows a notch, as Windows scrolls; fractions carry over (touchpads).
            self.wheel_rest += ui.input.wheel * 3;
            const rows = @divTrunc(self.wheel_rest, 120);
            self.wheel_rest -= rows * 120;
            if (rows != 0) {
                const event = self.mouseEvent(ui, area, cadex.CADEX_MOUSE_PRESS, cadex.CADEX_MOUSE_BUTTON_NONE);
                _ = cadex.cadex_terminal_wheel(t, &event, -rows);
                self.scrolled_at = ui.now_ms;
            }
            ui.input.wheel = 0;
        }
        if (tracking) return self.trackMouse(ui, area);
        if (ui.pressedOn(area, .left) and !ui.input.mods.ctrl) {
            ui.focus = self.id;
            ui.active = self.id;
            self.selecting = true;
            const p = self.pointer(ui, area);
            _ = cadex.cadex_terminal_select_press(t, &p, ui.input.clicks, ui.input.mods.shift);
        } else if (self.selecting and ui.input.down[0]) {
            const p = self.pointer(ui, area);
            if (self.autoscroll != 0) {
                _ = cadex.cadex_terminal_select_autoscroll(t, &p, &self.autoscroll);
            } else {
                _ = cadex.cadex_terminal_select_drag(t, &p, &self.autoscroll);
            }
        } else if (self.selecting and ui.input.released[0]) {
            const p = self.pointer(ui, area);
            _ = cadex.cadex_terminal_select_release(t, &p);
            self.selecting = false;
            self.autoscroll = 0;
        }
    }

    fn trackMouse(self: *View, ui: *Ui, area: gfx.Rect) void {
        const t = self.session.terminal;
        const buttons = [_]struct { ui_mod.Button, u8 }{ .{ .left, cadex.CADEX_MOUSE_BUTTON_LEFT }, .{ .right, cadex.CADEX_MOUSE_BUTTON_RIGHT }, .{ .middle, cadex.CADEX_MOUSE_BUTTON_MIDDLE } };
        for (buttons) |b| {
            if (ui.pressedOn(area, b[0])) {
                ui.focus = self.id;
                self.tracking_press = b[1];
                const e = self.mouseEvent(ui, area, cadex.CADEX_MOUSE_PRESS, b[1]);
                _ = cadex.cadex_terminal_mouse(t, &e);
            }
            if (ui.input.released[@intFromEnum(b[0])] and self.tracking_press == b[1]) {
                self.tracking_press = null;
                const e = self.mouseEvent(ui, area, cadex.CADEX_MOUSE_RELEASE, b[1]);
                _ = cadex.cadex_terminal_mouse(t, &e);
            }
        }
        if (ui.mouseOver(area)) {
            const e = self.mouseEvent(ui, area, cadex.CADEX_MOUSE_MOTION, self.tracking_press orelse cadex.CADEX_MOUSE_BUTTON_NONE);
            _ = cadex.cadex_terminal_mouse(t, &e);
        }
    }

    /// With Ctrl held over a link: underlined, and a click opens it.
    fn hoveredLink(self: *View, ui: *Ui, font: *font_mod.Font, area: gfx.Rect) ?cadex.cadex_terminal_link {
        _ = font;
        if (!ui.input.mods.ctrl or !ui.mouseOver(area) or self.cols == 0) return null;
        const cell = self.cellAt(ui, area, ui.input.mouse);
        var link: cadex.cadex_terminal_link = undefined;
        var target: [*c]u8 = null;
        var len: usize = 0;
        if (cadex.cadex_terminal_link_at(self.session.terminal, cell.col, cell.row, &link, &target, &len) != cadex.CADEX_OK) return null;
        defer cadex.cadex_free(target);
        if (link.kind == cadex.CADEX_LINK_NONE or target == null) return null;
        ui.cursor = .hand;
        if (ui.pressedOn(area, .left)) {
            if (self.hooks.open_link) |open| open(self.hooks.context, link.kind, target[0..len]);
        }
        return link;
    }

    /// A key press while the pane has the focus, before WM_CHAR. True when
    /// it went to the shell (the window then drops its WM_CHAR).
    pub fn keyDown(self: *View, vk: u16, scan: u16, mods: ui_mod.Mods) bool {
        if (self.find.open) return false;
        if (keys.isAltGr(mods)) return false;
        const named = keys.named(vk);
        if (named == null and !mods.ctrl and !mods.alt) return false;
        if (vk == c.VK_SHIFT or vk == c.VK_CONTROL or vk == c.VK_MENU or vk == c.VK_LWIN or vk == c.VK_RWIN or vk == c.VK_CAPITAL) return false;
        const typed = keys.typed(vk, scan, mods.shift);
        if (named == null and typed.len == 0) return false;
        _ = cadex.cadex_terminal_select_clear(self.session.terminal);
        self.session.key(named orelse cadex.CADEX_KEY_NONE, keys.modsOf(mods), typed.text[0..typed.len], typed.unshifted);
        return true;
    }

    /// Text from WM_CHAR (the layout's characters, accents composed).
    pub fn typeText(self: *View, utf8: []const u8) void {
        if (utf8.len == 0) return;
        self.session.write(utf8);
    }

    pub fn bell(self: *View, now_ms: i64) void {
        self.flash_from = now_ms;
    }

    pub fn copySelection(self: *View, ui: *Ui) bool {
        var out: [*c]u8 = null;
        var len: usize = 0;
        if (cadex.cadex_terminal_copy_selection(self.session.terminal, &out, &len) != cadex.CADEX_OK or out == null) return false;
        defer cadex.cadex_free(out);
        ui_mod.clipboard.writeText(ui.gpa, ui.hwnd, out[0..len]);
        return true;
    }

    pub fn hasSelection(self: *View) bool {
        return cadex.cadex_terminal_has_selection(self.session.terminal);
    }

    pub fn selectAll(self: *View) void {
        _ = cadex.cadex_terminal_select_all(self.session.terminal);
    }

    pub fn clear(self: *View) void {
        // Ctrl+L: the shell clears its screen and keeps the history.
        self.session.write("\x0c");
    }

    pub fn scrollTo(self: *View, top: bool) void {
        _ = cadex.cadex_terminal_scroll_to(self.session.terminal, if (top) cadex.CADEX_SCROLL_TOP else cadex.CADEX_SCROLL_BOTTOM);
    }

    pub fn focusChanged(self: *View, focused: bool) void {
        _ = cadex.cadex_terminal_focus(self.session.terminal, focused);
    }
};

test {
    std.testing.refAllDecls(@This());
}
