//! Buttons, labels, toggles and the small pieces every feature draws.

const std = @import("std");
const gfx = @import("gfx");
const context = @import("context.zig");

const Ui = context.Ui;
const Id = context.Id;
const Rect = gfx.Rect;
const Color = gfx.Color;

pub const ButtonOptions = struct {
    /// A Phosphor code point (shared/icons) drawn before the label.
    icon: ?u21 = null,
    icon_size: f32 = 16,
    /// The icon in the fill weight (on), instead of the outline.
    filled: bool = false,
    selected: bool = false,
    enabled: bool = true,
    /// A filled button (the default choice of a dialog).
    primary: bool = false,
    radius: f32 = 6,
    @"align": gfx.TextOptions = .{ .@"align" = .center },
    color: ?Color = null,
};

/// A clickable area with a hover background, an optional icon and label.
/// True when clicked.
pub fn button(ui: *Ui, widget: Id, r: Rect, title: []const u8, options: ButtonOptions) bool {
    const clicked = ui.clickable(widget, r) and options.enabled;
    const style = ui.style;
    const background: Color = if (options.primary)
        style.accent
    else if (ui.isActive(widget) and ui.mouseOver(r))
        style.pressed()
    else if (options.selected)
        style.tab_active
    else if (ui.isHot(widget) and options.enabled)
        style.hover()
    else
        Color.transparent;
    ui.painter.fillRounded(r, ui.px(options.radius), background);
    if (ui.isHot(widget) and options.enabled) ui.cursor = .arrow;
    const fg = options.color orelse if (options.primary)
        (if (style.accent.luminance() > 0.5) Color.black else Color.white)
    else if (options.enabled) style.text else style.secondary_text.alpha(0.6);
    var content = r.inset(ui.px(8), 0);
    if (options.icon) |cp| {
        const size = ui.px(options.icon_size);
        const box = if (title.len == 0) r else content.takeLeft(size + ui.px(6));
        ui.painter.iconWeight(cp, size, if (title.len == 0) box else .{ .x = box.x, .y = box.y, .w = size, .h = box.h }, fg, options.filled);
    }
    if (title.len > 0) ui.painter.text(title, style.ui(), content, fg, if (options.icon != null) .{} else options.@"align");
    return clicked;
}

/// An icon-only square button, as in the title and status bars.
pub fn iconButton(ui: *Ui, widget: Id, r: Rect, codepoint: u21, options: ButtonOptions) bool {
    var o = options;
    o.icon = codepoint;
    return button(ui, widget, r, "", o);
}

pub fn label(ui: *Ui, r: Rect, value: []const u8, color: ?Color) void {
    ui.painter.text(value, ui.style.ui(), r, color orelse ui.style.text, .{});
}

pub fn secondary(ui: *Ui, r: Rect, value: []const u8) void {
    ui.painter.text(value, ui.style.small(), r, ui.style.secondary_text, .{});
}

/// A switch for a setting. Returns the new value when clicked.
pub fn toggle(ui: *Ui, widget: Id, r: Rect, on: bool) ?bool {
    const clicked = ui.clickable(widget, r);
    const track: Rect = .{ .x = r.x, .y = r.center().y - ui.px(9), .w = ui.px(34), .h = ui.px(18) };
    ui.painter.fillRounded(track, track.h / 2, if (on) ui.style.accent else ui.style.field);
    ui.painter.stroke(track, track.h / 2, ui.style.panel_border, 1);
    const knob_x = if (on) track.right() - track.h + ui.px(3) else track.x + ui.px(3);
    const knob_fg: Color = if (on) (if (ui.style.accent.luminance() > 0.5) Color.black else Color.white) else ui.style.secondary_text;
    ui.painter.fillEllipse(.{ .x = knob_x + (track.h - ui.px(6)) / 2, .y = track.center().y }, (track.h - ui.px(6)) / 2, (track.h - ui.px(6)) / 2, knob_fg);
    return if (clicked) !on else null;
}

/// A horizontal line across `r`'s top.
pub fn separator(ui: *Ui, r: Rect) void {
    ui.painter.fill(.{ .x = r.x, .y = r.y, .w = r.w, .h = @max(1, ui.px(1)) }, ui.style.separator());
}

/// Keyboard shortcut chips ("Ctrl", "Shift", "T") right-aligned in `r`;
/// the width they took.
pub fn keys(ui: *Ui, r: Rect, parts: []const []const u8) f32 {
    var x = r.right();
    const pad = ui.px(5);
    const h = ui.px(18);
    var i = parts.len;
    while (i > 0) {
        i -= 1;
        const width = ui.painter.measure(parts[i], ui.style.small()) + 2 * pad;
        x -= width;
        const chip: Rect = .{ .x = x, .y = r.center().y - h / 2, .w = width, .h = h };
        ui.painter.fillRounded(chip, ui.px(4), ui.style.field);
        ui.painter.text(parts[i], ui.style.small(), chip, ui.style.secondary_text, .{ .@"align" = .center, .ellipsis = false });
        x -= ui.px(3);
    }
    return r.right() - x;
}

test {
    @import("win32").refAllDeep(@This());
}
