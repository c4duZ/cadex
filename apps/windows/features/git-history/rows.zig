//! The commits' list (the Mac's HistoryRows): graph, subject with the refs
//! as tinted labels, author, relative date and short sha. Only the rows in
//! view are drawn; nearing the end asks for the next page. Right click
//! opens the menu of history.* commands on that commit.

const std = @import("std");
const gfx = @import("gfx");
const ui = @import("ui");
const strings = @import("strings");
const w = @import("win32");
const log = @import("log.zig");
const graph = @import("graph.zig");
const dates = @import("dates.zig");
const view = @import("view.zig");
const commands = @import("commands.zig");
const document = @import("document.zig");

const HistoryDocument = document.HistoryDocument;
const Rect = gfx.Rect;
const Color = gfx.Color;

/// The next page is asked this many rows before the end (the Mac's).
const prefetch = 100;

/// English then Portuguese: t runs at draw time, not in a const table.
const menu_items = [_]struct { label: [2][]const u8, id: []const u8 }{
    .{ .label = .{ "Copy SHA", "Copiar sha" }, .id = "history.copy-sha" },
    .{ .label = .{ "Open on Remote", "Abrir no remoto" }, .id = "history.open-remote" },
};

const Columns = struct { graph: Rect, subject: Rect, author: ?Rect, date: ?Rect, sha: Rect };

/// Narrow panes drop the author, then the date.
fn columns(u: *ui.Ui, line: Rect, graph_w: f32) Columns {
    var r = line;
    const g = r.takeLeft(graph_w);
    const sha = r.takeRight(u.px(70));
    const date: ?Rect = if (line.w > u.px(420)) r.takeRight(u.px(120)) else null;
    const author: ?Rect = if (line.w > u.px(560)) r.takeRight(u.px(140)) else null;
    return .{ .graph = g, .subject = r, .author = author, .date = date, .sha = sha };
}

pub fn draw(doc: *HistoryDocument, u: *ui.Ui, area: Rect) void {
    const id = view.listId(doc);
    const shown = doc.shown();
    const count = shown.len();
    const graph_w = if (doc.showsGraph()) u.px(graph.width(doc.main.lanes)) else u.px(6);
    var r = area;
    header(u, r.takeTop(u.px(24)), graph_w);
    const row_h = u.rowPx(22);
    if (u.pressedOn(r, .left) or u.pressedOn(r, .right)) u.focus = id;
    keyboard(doc, u, shown, r, row_h);
    const list = ui.list.begin(u, id, r, count, row_h, &doc.view.list_scroll);
    // A local filter only looks at what is loaded; the full list and a
    // repository search grow.
    const filtering = doc.search == null and doc.filter.items.len > 0;
    if (!filtering and count > 0 and list.last + prefetch >= count) doc.loadMore();
    const now = dates.nowUnix();
    for (list.first..list.last) |i| row(doc, u, i, list.row(i), shown.at(i), graph_w, now);
    ui.list.end(u);
    var menu_rows: [menu_items.len]ui.menu.Item = undefined;
    for (menu_items, &menu_rows) |m, *item| item.* = .{ .label = strings.t(m.label[0], m.label[1]) };
    if (ui.menu.show(u, &doc.view.menu, ui.child(id, 0x6e), &menu_rows)) |chosen| commands.run(menu_items[chosen].id);
}

fn header(u: *ui.Ui, r: Rect, graph_w: f32) void {
    const cols = columns(u, r.inset(u.px(4), 0), graph_w);
    const spec = u.style.small();
    const fg = u.style.secondary_text;
    u.painter.text(strings.t("Description", "Descrição"), spec, cols.subject.inset(u.px(4), 0), fg, .{});
    if (cols.author) |a| u.painter.text(strings.t("Author", "Autor"), spec, a.inset(u.px(4), 0), fg, .{});
    if (cols.date) |d| u.painter.text(strings.t("Date", "Data"), spec, d.inset(u.px(4), 0), fg, .{});
    u.painter.text("Commit", spec, cols.sha.inset(u.px(4), 0), fg, .{});
    ui.widgets.separator(u, .{ .x = r.x, .y = r.bottom() - 1, .w = r.w, .h = 1 });
}

/// Up and Down move the selection when the list has the keys.
fn keyboard(doc: *HistoryDocument, u: *ui.Ui, shown: document.Shown, area: Rect, row_h: f32) void {
    if (u.focus != view.listId(doc) or shown.len() == 0) return;
    const before = @min(doc.view.cursor, shown.len() - 1);
    const at = ui.list.keyboardSelect(u, before, shown.len(), @intFromFloat(@max(area.h / row_h, 1)));
    doc.view.cursor = at;
    if (at != before) {
        doc.select(shown.at(at).*);
        doc.view.list_scroll.reveal(@as(f32, @floatFromInt(at)) * row_h, row_h, area.h);
    }
}

fn row(doc: *HistoryDocument, u: *ui.Ui, i: usize, r: Rect, commit: *const log.Commit, graph_w: f32, now: i64) void {
    const id = ui.child(view.listId(doc), i + 1);
    const selected = std.mem.eql(u8, doc.selected.items, commit.sha);
    if (u.clickable(id, r)) {
        doc.view.cursor = i;
        doc.select(commit.*);
    }
    if (u.pressedOn(r, .right)) {
        doc.view.cursor = i;
        doc.select(commit.*);
        doc.view.menu.open(ui.child(view.listId(doc), 0x6e), u.input.mouse);
    }
    if (selected) u.painter.fill(r, u.style.selection()) else if (u.mouseOver(r)) u.painter.fill(r, u.style.hover());
    const cols = columns(u, r.inset(u.px(4), 0), graph_w);
    if (doc.showsGraph()) if (commit.graph) |g| graph.draw(u, cols.graph, g, commit.isMerge(), commit.isHead());
    var subject = cols.subject.inset(u.px(4), 0);
    refLabels(u, &subject, commit.refs);
    u.painter.text(commit.subject, u.style.ui(), subject, u.style.text, .{});
    const fg = u.style.secondary_text;
    if (cols.author) |a| u.painter.text(commit.author, u.style.small(), a.inset(u.px(4), 0), fg, .{});
    if (cols.date) |d| {
        var buf: [48]u8 = undefined;
        u.painter.text(dates.relative(&buf, now, commit.time), u.style.small(), d.inset(u.px(4), 0), fg, .{});
    }
    u.painter.text(commit.shortSha(), u.style.mono(11), cols.sha.inset(u.px(4), 0), fg, .{});
}

/// Branches blue (the current one bold), remotes grey, tags yellow.
fn refLabels(u: *ui.Ui, r: *Rect, refs: []const u8) void {
    if (refs.len == 0) return;
    var it = log.refs(refs);
    while (it.next()) |ref| {
        if (ref.len == 0 or std.mem.eql(u8, ref, "HEAD")) continue;
        const current = std.mem.startsWith(u8, ref, "HEAD -> ");
        const tag = std.mem.startsWith(u8, ref, "tag: ");
        const name = if (current) ref[8..] else if (tag) ref[5..] else ref;
        const tint: Color = if (tag) Color.rgb(0xffd60a) else if (std.mem.indexOfScalar(u8, name, '/') != null) Color.rgb(0x98989d) else Color.rgb(0x0a84ff);
        var spec = u.style.small();
        spec.weight = if (current) .bold else .medium;
        const lw = u.painter.measure(name, spec) + u.px(10);
        if (lw > r.w * 0.6) break;
        const chip = r.takeLeft(lw);
        _ = r.takeLeft(u.px(4));
        const box: Rect = .{ .x = chip.x, .y = chip.center().y - u.px(8), .w = chip.w, .h = u.px(16) };
        u.painter.fillRounded(box, u.px(4), tint.alpha(0.15));
        u.painter.text(name, spec, box, tint, .{ .@"align" = .center, .ellipsis = false });
    }
}

test {
    @import("win32").refAllDeep(@This());
}
