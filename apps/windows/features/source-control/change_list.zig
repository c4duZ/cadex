//! The lists of the Git page (the Mac's SourceControlRow): section titles
//! with "stage all" (+) or "unstage all" (−), and one row per file with
//! its icon, name, folder in grey, the letter in its color and + or − on
//! hover. Click selects and opens the diff, Ctrl+click adds to the
//! selection, right click opens the menu of git.* commands. Only the rows
//! in view are drawn.

const std = @import("std");
const gfx = @import("gfx");
const ui = @import("ui");
const w = @import("win32");
const icons = @import("icons");
const status_mod = @import("status.zig");
const controller = @import("controller.zig");
const opening = @import("opening.zig");

const SourceControl = controller.SourceControl;
const Row = status_mod.Row;
const Rect = gfx.Rect;

pub const list_id = ui.id("scm.list", 0);
const menu_owner = ui.id("scm.menu", 0);

/// The context menu: each item runs a registered command on the selection.
const menu_items = [_]struct { label: []const u8, id: []const u8 }{
    .{ .label = "Abrir o arquivo", .id = "git.open-file" },
    .{ .label = "Ver o diff", .id = "git.open-diff" },
    .{ .label = "Stage", .id = "git.stage" },
    .{ .label = "Unstage", .id = "git.unstage" },
    .{ .label = "Descartar as mudanças", .id = "git.discard" },
    .{ .label = "Revelar no Explorador de Arquivos", .id = "git.reveal" },
};

const menu_rows = blk: {
    var items: [menu_items.len]ui.menu.Item = undefined;
    for (menu_items, 0..) |m, i| items[i] = .{ .label = m.label };
    break :blk items;
};

pub fn draw(sc: *SourceControl, u: *ui.Ui, area: Rect) void {
    const row_h = u.px(24);
    if (u.pressedOn(area, .left) or u.pressedOn(area, .right)) u.focus = list_id;
    keyboard(sc, u, area, row_h);
    const view = ui.list.begin(u, list_id, area, sc.rows.len, row_h, &sc.view.list_scroll);
    for (view.first..view.last) |i| drawRow(sc, u, i, view.row(i).inset(u.px(4), 0));
    ui.list.end(u);
    if (ui.menu.show(u, &sc.view.menu, menu_owner, &menu_rows)) |chosen| sc.run(menu_items[chosen].id);
}

/// Up and Down move between files, Enter opens the diff, Delete discards.
fn keyboard(sc: *SourceControl, u: *ui.Ui, area: Rect, row_h: f32) void {
    if (u.focus != list_id or sc.rows.len == 0) return;
    const before = sc.view.cursor;
    var at = ui.list.keyboardSelect(u, before, sc.rows.len, @intFromFloat(@max(area.h / row_h, 1)));
    // Skip titles in the direction of travel.
    while (at < sc.rows.len and sc.rows[at] != .entry) {
        if (at > before) at += 1 else if (at == 0) break else at -= 1;
    }
    if (at >= sc.rows.len or sc.rows[at] != .entry) at = before;
    if (at != before and at < sc.rows.len and sc.rows[at] == .entry) {
        sc.view.cursor = at;
        select(sc, at, false);
        sc.view.list_scroll.reveal(@as(f32, @floatFromInt(at)) * row_h, row_h, area.h);
    }
    if (u.key(w.c.VK_RETURN, .{})) sc.run("git.open-diff");
    if (u.key(w.c.VK_DELETE, .{})) sc.run("git.discard");
}

fn select(sc: *SourceControl, index: usize, add: bool) void {
    const row = sc.rows[index].entry;
    const s = sc.status orelse return;
    const path = s.entries[row.index].path;
    if (add) sc.selection.toggle(sc.gpa, row.staged, path) else sc.selection.only(sc.gpa, row.staged, path);
}

fn drawRow(sc: *SourceControl, u: *ui.Ui, i: usize, r: Rect) void {
    switch (sc.rows[i]) {
        .header => |h| header(sc, u, i, r, h),
        .entry => |e| entry(sc, u, i, r, e.index, e.staged),
        .overflow => |o| {
            var buf: [96]u8 = undefined;
            const text = std.fmt.bufPrint(&buf, "Mostrando {d} de {d}: veja o resto com git status", .{ o.shown, o.total }) catch "";
            u.painter.text(text, u.style.small(), r.inset(u.px(6), 0), u.style.secondary_text, .{});
        },
    }
}

/// The Mac's titles are uppercase; ç has no ASCII uppercase.
fn upper(title: []const u8) []const u8 {
    const map = [_][2][]const u8{ .{ "Conflitos", "CONFLITOS" }, .{ "Staged", "STAGED" }, .{ "Mudanças", "MUDANÇAS" }, .{ "Nenhuma mudança", "NENHUMA MUDANÇA" } };
    for (map) |m| if (std.mem.eql(u8, m[0], title)) return m[1];
    return title;
}

fn header(sc: *SourceControl, u: *ui.Ui, i: usize, r: Rect, h: status_mod.Header) void {
    var inner = r.inset(u.px(6), 0);
    const row_id = ui.child(list_id, i);
    const over = u.mouseOver(r);
    if (h.list != .conflicts and h.count > 0 and over) {
        const b = inner.takeRight(r.h);
        const staged = h.list == .staged;
        if (ui.widgets.button(u, ui.child(row_id, 1), b, if (staged) "−" else "+", .{ .color = u.style.secondary_text })) {
            if (staged) sc.run("git.unstage-all") else sc.run("git.stage-all");
        }
    }
    var buf: [64]u8 = undefined;
    const text = if (h.count > 0) std.fmt.bufPrint(&buf, "{s}  {d}", .{ upper(h.title), h.count }) catch h.title else upper(h.title);
    var spec = u.style.small();
    spec.weight = .semibold;
    u.painter.text(text, spec, inner, u.style.secondary_text, .{});
}

fn entry(sc: *SourceControl, u: *ui.Ui, i: usize, r: Rect, index: usize, staged: bool) void {
    const s = sc.status orelse return;
    const e = s.entries[index];
    const row_id = ui.child(list_id, i);
    const selected = sc.selection.has(staged, e.path);
    if (u.clickable(row_id, r)) {
        sc.view.cursor = i;
        select(sc, i, u.input.mods.ctrl);
        if (!u.input.mods.ctrl) opening.openDiff(sc, e, staged);
    }
    if (u.pressedOn(r, .right)) {
        if (!selected) select(sc, i, false);
        sc.view.menu.open(menu_owner, u.input.mouse);
    }
    const over = u.isHot(row_id) or u.mouseOver(r);
    if (selected) u.painter.fillRounded(r, u.px(5), u.style.selection()) else if (over) u.painter.fillRounded(r, u.px(5), u.style.hover());

    var inner = r.inset(u.px(6), 0);
    const letter = e.letter(staged);
    u.painter.text(&.{letter}, u.style.mono(11), inner.takeRight(u.px(14)), status_mod.letterColor(letter), .{ .@"align" = .center });
    if (e.kind != .conflict and over) {
        const b = inner.takeRight(r.h);
        if (ui.widgets.button(u, ui.child(row_id, 1), b, if (staged) "−" else "+", .{ .color = u.style.secondary_text })) {
            sc.onPaths(if (staged) .unstage else .stage, &.{e});
        }
    }
    const parts = status_mod.splitPath(e.path);
    u.painter.icon(icons.forFileNamed(parts.name), u.px(14), inner.takeLeft(u.px(20)), u.style.secondary_text);
    const name_w = @min(u.painter.measure(parts.name, u.style.ui()) + u.px(8), inner.w);
    u.painter.text(parts.name, u.style.ui(), inner.takeLeft(name_w), u.style.text, .{});
    var detail_buf: [512]u8 = undefined;
    const detail = if (e.kind == .renamed)
        std.fmt.bufPrint(&detail_buf, "{s} → {s}", .{ status_mod.splitPath(e.orig).name, parts.folder }) catch parts.folder
    else
        parts.folder;
    if (detail.len > 0) u.painter.text(detail, u.style.small(), inner, u.style.secondary_text, .{});
}

test {
    @import("win32").refAllDeep(@This());
}
