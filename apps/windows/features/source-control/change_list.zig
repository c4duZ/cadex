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
const strings = @import("strings");
const status_mod = @import("status.zig");
const controller = @import("controller.zig");
const opening = @import("opening.zig");

const SourceControl = controller.SourceControl;
const Row = status_mod.Row;
const Rect = gfx.Rect;

pub const list_id = ui.id("scm.list", 0);
const menu_owner = ui.id("scm.menu", 0);

/// The context menu (the Mac's SourceControlMenu): only what applies to
/// the clicked files (owner, 2026-10-20): Stage on changes, Unstage on
/// staged ones, no file to open or reveal when every one was deleted. The
/// diff and the file open where the settings say, beside or in a new tab.
/// null is a separator. The label is English then Portuguese: t runs at
/// draw time, not in a const table.
const MenuItem = struct { label: [2][]const u8, id: []const u8, icon: u21, when: When };
const When = enum { always, on_disk, unstaged, staged };
const menu_items = [_]?MenuItem{
    .{ .label = .{ "Open File", "Abrir o arquivo" }, .id = "git.open-file", .icon = icons.phosphor.file, .when = .on_disk },
    .{ .label = .{ "Open Beside", "Abrir ao lado" }, .id = "git.open-file-beside", .icon = icons.phosphor.square_split_horizontal, .when = .on_disk },
    .{ .label = .{ "Open in New Tab", "Abrir em nova aba" }, .id = "git.open-file-in-tab", .icon = icons.phosphor.plus, .when = .on_disk },
    null,
    .{ .label = .{ "Open Diff", "Ver o diff" }, .id = "git.open-diff", .icon = icons.phosphor.git_diff, .when = .always },
    .{ .label = .{ "Open Diff Beside", "Ver o diff ao lado" }, .id = "git.open-diff-beside", .icon = icons.phosphor.square_split_horizontal, .when = .always },
    .{ .label = .{ "Open Diff in New Tab", "Ver o diff em nova aba" }, .id = "git.open-diff-in-tab", .icon = icons.phosphor.plus, .when = .always },
    null,
    .{ .label = .{ "Stage", "Stage" }, .id = "git.stage", .icon = icons.phosphor.plus, .when = .unstaged },
    .{ .label = .{ "Unstage", "Unstage" }, .id = "git.unstage", .icon = icons.phosphor.minus, .when = .staged },
    .{ .label = .{ "Discard Changes", "Descartar as mudanças" }, .id = "git.discard", .icon = icons.phosphor.arrow_u_up_left, .when = .always },
    null,
    .{ .label = .{ "Reveal in File Explorer", "Revelar no Explorador de Arquivos" }, .id = "git.reveal", .icon = icons.phosphor.folder_open, .when = .on_disk },
};

/// Gone from the disk: deleted in the working tree, or staged as deleted
/// with nothing after.
fn isDeleted(e: status_mod.Entry, staged: bool) bool {
    return if (staged) e.index == 'D' and e.worktree == '.' else e.worktree == 'D';
}

/// The menu for the current selection, separators tidied; returns the count.
fn buildMenu(sc: *SourceControl, items: *[menu_items.len]ui.menu.Item, ids: *[menu_items.len]?[]const u8) usize {
    const picked = sc.selection.entries(sc.gpa, sc.status);
    defer sc.gpa.free(picked);
    if (picked.len == 0) return 0;
    var on_disk = false;
    var any_staged = false;
    var any_unstaged = false;
    for (picked) |p| {
        if (!isDeleted(p.entry, p.staged)) on_disk = true;
        if (p.staged) any_staged = true else any_unstaged = true;
    }
    var n: usize = 0;
    for (menu_items) |slot| {
        if (slot) |m| {
            const applies = switch (m.when) {
                .always => true,
                .on_disk => on_disk,
                .unstaged => any_unstaged,
                .staged => any_staged,
            };
            if (!applies) continue;
            items[n] = .{ .label = strings.t(m.label[0], m.label[1]), .icon = m.icon };
            ids[n] = m.id;
        } else {
            if (n == 0 or ids[n - 1] == null) continue;
            items[n] = .{ .separator = true };
            ids[n] = null;
        }
        n += 1;
    }
    if (n > 0 and ids[n - 1] == null) n -= 1;
    return n;
}

pub fn draw(sc: *SourceControl, u: *ui.Ui, area: Rect) void {
    const row_h = u.rowPx(24);
    if (u.pressedOn(area, .left) or u.pressedOn(area, .right)) u.focus = list_id;
    keyboard(sc, u, area, row_h);
    const view = ui.list.begin(u, list_id, area, sc.rows.len, row_h, &sc.view.list_scroll);
    for (view.first..view.last) |i| drawRow(sc, u, i, view.row(i).inset(u.px(4), 0));
    ui.list.end(u);
    if (sc.view.menu.isOpen(menu_owner)) {
        var items: [menu_items.len]ui.menu.Item = undefined;
        var ids: [menu_items.len]?[]const u8 = undefined;
        const n = buildMenu(sc, &items, &ids);
        if (ui.menu.show(u, &sc.view.menu, menu_owner, items[0..n])) |chosen| if (ids[chosen]) |id| sc.run(id);
    }
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
            const text = if (strings.language == .pt)
                std.fmt.bufPrint(&buf, "Mostrando {d} de {d}: veja o resto com git status", .{ o.shown, o.total }) catch ""
            else
                std.fmt.bufPrint(&buf, "Showing {d} of {d}: see the rest with git status", .{ o.shown, o.total }) catch "";
            u.painter.text(text, u.style.small(), r.inset(u.px(6), 0), u.style.secondary_text, .{});
        },
    }
}

/// The Mac's titles are uppercase; ç has no ASCII uppercase. status.zig's
/// titles are the keys, each with its English and Portuguese.
fn upper(title: []const u8) []const u8 {
    const map = [_][3][]const u8{
        .{ "Conflitos", "CONFLICTS", "CONFLITOS" },
        .{ "Staged", "STAGED", "STAGED" },
        .{ "Mudanças", "CHANGES", "MUDANÇAS" },
        .{ "Nenhuma mudança", "NO CHANGES", "NENHUMA MUDANÇA" },
    };
    for (map) |m| if (std.mem.eql(u8, m[0], title)) return strings.t(m[1], m[2]);
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
        if (!u.input.mods.ctrl) opening.openDiff(sc, e, staged, .normal);
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
