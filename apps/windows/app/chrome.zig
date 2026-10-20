//! The title bar the app draws (the Mac's TitleBarView): on the left the
//! sidebar, the search for everything (the palette) and the space; then
//! the tabs and "+"; on the right the settings and Windows' minimize,
//! maximize and close. Every button runs a command by id (ADR 0005); the
//! rectangles become "holes" in the caption for the hit test.

const std = @import("std");
const w = @import("win32");
const gfx = @import("gfx");
const ui = @import("ui");
const icons = @import("icons");
const App = @import("app.zig").App;

const c = w.c;

/// Segoe Fluent Icons, which Windows 11 ships for its caption buttons.
const caption_font = "Segoe Fluent Icons";
const glyph_minimize: u21 = 0xE921;
const glyph_maximize: u21 = 0xE922;
const glyph_restore: u21 = 0xE923;
const glyph_close: u21 = 0xE8BB;
/// The close button's hover red, as Windows paints it.
const close_red = gfx.Color.rgb(0xC42B1C);

fn hole(app: *App, r: gfx.Rect) gfx.Rect {
    app.holes.append(app.gpa, r) catch {};
    return r;
}

pub fn titleBar(app: *App, area: gfx.Rect) void {
    const u = &app.u;
    var row = area;
    const caption_w = u.px(46);
    const close_r = row.takeRight(caption_w);
    const max_r = row.takeRight(caption_w);
    const min_r = row.takeRight(caption_w);
    captionButtons(app, min_r, max_r, close_r);

    const h = u.px(26);
    const top = area.y + (area.h - h) / 2;
    _ = row.takeLeft(u.px(8));
    const left_group = row.takeLeft(u.px(8));
    _ = left_group;
    // Keep-awake, before the space as on the Mac: filled while on, the
    // outline while off; a click runs power.toggle (docs/spec/power.md).
    const power_r = hole(app, .{ .x = row.x, .y = top, .w = u.px(30), .h = h });
    _ = row.takeLeft(u.px(30) + u.px(10));
    if (ui.widgets.iconButton(u, ui.id("title.power", 0), power_r, icons.phosphor.coffee, .{ .icon_size = 15, .filled = app.power.mode != .off, .color = u.style.secondary_text })) {
        _ = app.registry.run("power.toggle");
    }
    // The space: its icon, and its name once there are several (the Mac's).
    const several = app.spaces.list.items.len > 1;
    const space_w = if (several) u.painter.measure(app.spaces.name(), u.style.small()) + u.px(36) else u.px(30);
    const space_r = hole(app, .{ .x = row.x, .y = top, .w = space_w, .h = h });
    _ = row.takeLeft(space_w + u.px(6));
    if (ui.widgets.button(u, ui.id("title.space", 0), space_r, if (several) app.spaces.name() else "", .{ .icon = icons.phosphor.stack, .icon_size = 14, .radius = 7, .color = u.style.secondary_text })) _ = app.registry.run("space.switch");
    const search_label = app.shortcutLabelOrEmpty("palette.open");
    const search_w = u.painter.measure(search_label, u.style.small()) + u.px(40);
    const search = hole(app, .{ .x = row.x, .y = top, .w = search_w, .h = h });
    _ = row.takeLeft(search_w + u.px(10));
    u.painter.fillRounded(search, u.px(7), u.style.field);
    if (ui.widgets.button(u, ui.id("title.search", 0), search, search_label, .{ .icon = icons.phosphor.magnifying_glass, .icon_size = 14, .radius = 7, .color = u.style.secondary_text })) {
        _ = app.registry.run("palette.open");
    }

    const settings_r = hole(app, .{ .x = row.right() - u.px(34), .y = top, .w = u.px(30), .h = h });
    _ = row.takeRight(u.px(40));
    if (ui.widgets.iconButton(u, ui.id("title.settings", 0), settings_r, icons.phosphor.gear_six, .{ .icon_size = 15 })) _ = app.registry.run("settings.open");
    // Tabs take what is left; each one is a hole.
    const result = app.bar.draw(u, app.tabs, row);
    var arena: std.heap.ArenaAllocator = .init(app.gpa);
    defer arena.deinit();
    const tab_count: f32 = @floatFromInt(@max(app.tabs.list.order.items.len, 1));
    const tabs_w = @min(u.px(222) * tab_count + u.px(34), row.w);
    _ = hole(app, .{ .x = row.x, .y = row.y, .w = tabs_w, .h = row.h });
    if (result.plus_at) |at| app.plus_menu.open(ui.id("plus.menu", 0), at);
}

fn captionButtons(app: *App, min_r: gfx.Rect, max_r: gfx.Rect, close_r: gfx.Rect) void {
    const u = &app.u;
    app.max_button = max_r;
    _ = hole(app, min_r);
    _ = hole(app, close_r);
    const spec: gfx.FontSpec = .{ .family = caption_font, .size = u.px(10) };
    const glyph = struct {
        fn draw(p: *gfx.Painter, s: gfx.FontSpec, cp: u21, r: gfx.Rect, color: gfx.Color) void {
            var buf: [4]u8 = undefined;
            const n = std.unicode.utf8Encode(cp, &buf) catch return;
            p.text(buf[0..n], s, r, color, .{ .@"align" = .center, .ellipsis = false });
        }
    }.draw;
    // Minimize and close are ours; maximize is reported to Windows as such
    // (Snap Layouts) and hovered from WM_NCMOUSEMOVE.
    const min_id = ui.id("title.minimize", 0);
    if (u.clickable(min_id, min_r)) _ = c.ShowWindow(app.window.hwnd, c.SW_MINIMIZE);
    if (u.isHot(min_id)) u.painter.fill(min_r, u.style.hover());
    glyph(u.painter, spec, glyph_minimize, min_r, u.style.text);

    if (u.input.mouse_inside and max_r.contains(u.input.mouse)) u.painter.fill(max_r, u.style.hover());
    glyph(u.painter, spec, if (app.window.isMaximized()) glyph_restore else glyph_maximize, max_r, u.style.text);

    const close_id = ui.id("title.close", 0);
    if (u.clickable(close_id, close_r)) _ = c.PostMessageW(app.window.hwnd, c.WM_CLOSE, 0, 0);
    const hot = u.isHot(close_id);
    if (hot) u.painter.fill(close_r, close_red);
    glyph(u.painter, spec, glyph_close, close_r, if (hot) gfx.Color.white else u.style.text);
}

test {
    @import("win32").refAllDeep(@This());
}
