//! A one-line text field: the palette's query, a rename, a search, a
//! setting. Draws a TextBuffer, takes keys and typed text while focused,
//! shows the IME composition at the caret and scrolls to keep it in view.

const std = @import("std");
const gfx = @import("gfx");
const w = @import("win32");
const context = @import("context.zig");
const TextBuffer = @import("text_buffer.zig").TextBuffer;
const clipboard = @import("clipboard.zig");
const Mods = @import("input.zig").Mods;

const Ui = context.Ui;
const Id = context.Id;
const c = w.c;

pub const Options = struct {
    placeholder: []const u8 = "",
    /// Takes the keys from the first frame (the palette, a rename).
    autofocus: bool = false,
    /// Draws a field background; off inside the palette's own box.
    framed: bool = true,
    spec: ?gfx.FontSpec = null,
};

pub const Result = struct {
    changed: bool = false,
    /// Enter was pressed.
    submitted: bool = false,
    /// Escape was pressed.
    cancelled: bool = false,
};

/// Horizontal scroll of each field, by id, so long text keeps the caret in view.
pub const Scroll = struct {
    offset: f32 = 0,
};

pub fn textField(ui: *Ui, widget: Id, r: gfx.Rect, buffer: *TextBuffer, scroll: *Scroll, options: Options) Result {
    var result: Result = .{};
    const spec = options.spec orelse ui.style.ui();
    if (options.autofocus and ui.focus == context.none) ui.focus = widget;
    const focused = ui.focus == widget;
    const pad = ui.px(8);
    const inner = r.inset(pad, 0);

    if (ui.mouseOver(r)) {
        ui.next_hot = widget;
        ui.cursor = .ibeam;
    }
    if (ui.pressedOn(r, .left)) {
        ui.focus = widget;
        ui.active = widget;
        const at = ui.painter.hitIndex(buffer.text(), spec, ui.input.mouse.x - inner.x + scroll.offset);
        if (ui.input.clicks == 2) buffer.selectWordAt(at) else if (ui.input.clicks == 3) buffer.selectAll() else buffer.place(at, ui.input.mods.shift);
    } else if (ui.active == widget and ui.input.down[0]) {
        buffer.place(ui.painter.hitIndex(buffer.text(), spec, ui.input.mouse.x - inner.x + scroll.offset), true);
    }

    if (focused) result = handleKeys(ui, buffer);

    if (options.framed) {
        ui.painter.fillRounded(r, ui.px(6), ui.style.field);
        if (focused) ui.painter.stroke(r, ui.px(6), ui.style.accent.alpha(0.6), @max(1, ui.px(1)));
    }
    keepCaretVisible(ui, buffer, spec, inner.w, scroll);
    ui.painter.pushClip(inner);
    defer ui.painter.popClip();
    const origin_x = inner.x - scroll.offset;
    if (buffer.hasSelection() and focused) {
        const s = buffer.selection();
        const x0 = ui.painter.caretX(buffer.text(), spec, s.start);
        const x1 = ui.painter.caretX(buffer.text(), spec, s.end);
        ui.painter.fill(.{ .x = origin_x + x0, .y = r.center().y - spec.size * 0.7, .w = x1 - x0, .h = spec.size * 1.4 }, ui.style.selection());
    }
    const text_rect: gfx.Rect = .{ .x = origin_x, .y = r.y, .w = 100_000, .h = r.h };
    if (buffer.text().len == 0 and ui.input.composition.items.len == 0) {
        ui.painter.text(options.placeholder, spec, inner, ui.style.secondary_text.alpha(0.7), .{});
    } else {
        ui.painter.text(buffer.text(), spec, text_rect, ui.style.text, .{ .ellipsis = false });
    }
    if (focused) drawCaret(ui, buffer, spec, r, origin_x);
    return result;
}

fn handleKeys(ui: *Ui, buffer: *TextBuffer) Result {
    var result: Result = .{};
    const gpa = ui.gpa;
    for (ui.input.keys.items) |*k| {
        if (k.used) continue;
        const shift = k.mods.shift;
        const ctrl = k.mods.ctrl;
        const word = ctrl and !k.mods.alt;
        k.used = true;
        switch (k.vk) {
            c.VK_LEFT => buffer.move(if (word) .word_left else .left, shift),
            c.VK_RIGHT => buffer.move(if (word) .word_right else .right, shift),
            c.VK_HOME => buffer.move(.home, shift),
            c.VK_END => buffer.move(.end, shift),
            c.VK_BACK => {
                buffer.backspace(word);
                result.changed = true;
            },
            c.VK_DELETE => {
                buffer.delete(word);
                result.changed = true;
            },
            c.VK_RETURN => result.submitted = true,
            c.VK_ESCAPE => result.cancelled = true,
            'A' => if (ctrl and !shift) buffer.selectAll() else {
                k.used = false;
            },
            'C', 'X' => if (ctrl and buffer.hasSelection()) {
                clipboard.writeText(gpa, ui.hwnd, buffer.selected());
                if (k.vk == 'X') {
                    buffer.backspace(false);
                    result.changed = true;
                }
            } else {
                k.used = false;
            },
            'V' => if (ctrl) {
                if (clipboard.readText(gpa, ui.hwnd)) |pasted| {
                    defer gpa.free(pasted);
                    buffer.insert(gpa, pasted) catch {};
                    result.changed = true;
                }
            } else {
                k.used = false;
            },
            // Arrows up and down, Tab and the rest belong to whoever holds
            // the field (the palette moves its selection with them).
            else => k.used = false,
        }
    }
    if (ui.input.text.items.len > 0) {
        buffer.insert(gpa, ui.input.text.items) catch {};
        ui.input.text.clearRetainingCapacity();
        result.changed = true;
    }
    return result;
}

fn keepCaretVisible(ui: *Ui, buffer: *TextBuffer, spec: gfx.FontSpec, width: f32, scroll: *Scroll) void {
    const x = ui.painter.caretX(buffer.text(), spec, buffer.caret);
    const margin = ui.px(4);
    if (x - scroll.offset > width - margin) scroll.offset = x - width + margin;
    if (x - scroll.offset < 0) scroll.offset = @max(x - margin, 0);
}

fn drawCaret(ui: *Ui, buffer: *TextBuffer, spec: gfx.FontSpec, r: gfx.Rect, origin_x: f32) void {
    const x = origin_x + ui.painter.caretX(buffer.text(), spec, buffer.caret);
    const h = spec.size * 1.3;
    const caret: gfx.Rect = .{ .x = x, .y = r.center().y - h / 2, .w = @max(1, ui.px(1.5)), .h = h };
    ui.ime_caret = caret;
    if (ui.input.composition.items.len > 0) {
        // The IME's text in progress, underlined, where it will land.
        const width = ui.painter.measure(ui.input.composition.items, spec);
        ui.painter.fill(.{ .x = x, .y = caret.y, .w = width, .h = h }, ui.style.panel);
        ui.painter.text(ui.input.composition.items, spec, .{ .x = x, .y = r.y, .w = width + 4, .h = r.h }, ui.style.text, .{ .ellipsis = false });
        ui.painter.fill(.{ .x = x, .y = caret.bottom(), .w = width, .h = @max(1, ui.px(1)) }, ui.style.text);
        return;
    }
    // Blinks every 530 ms, the Windows default caret rate.
    const on = @mod(@divTrunc(ui.now_ms, 530), 2) == 0;
    if (on) ui.painter.fill(caret, ui.style.accent);
    ui.requestFrame(530 - @as(u32, @intCast(@mod(ui.now_ms, 530))));
}

test {
    @import("win32").refAllDeep(@This());
}
