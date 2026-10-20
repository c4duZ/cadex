//! The history pane (the Mac's HistoryView): the search and "Só a branch
//! atual" on top, the commits with the graph (rows.zig), and the selected
//! commit's details in the bottom third (details.zig).

const std = @import("std");
const gfx = @import("gfx");
const ui = @import("ui");
const strings = @import("strings");
const w = @import("win32");
const HistoryDocument = @import("document.zig").HistoryDocument;
const rows = @import("rows.zig");
const details = @import("details.zig");
const commands = @import("commands.zig");

const Rect = gfx.Rect;

pub const State = struct {
    search: ui.TextBuffer = .{},
    search_scroll: ui.text_field.Scroll = .{},
    list_scroll: ui.list.Scroll = .{},
    files_scroll: ui.list.Scroll = .{},
    menu: ui.menu.Menu = .{},
    /// The row the keyboard is on.
    cursor: usize = 0,
};

pub fn listId(doc: *const HistoryDocument) ui.Id {
    return ui.child(ui.id("history.list", 0), @intFromPtr(doc));
}

pub fn searchId(doc: *const HistoryDocument) ui.Id {
    return ui.child(ui.id("history.search", 0), @intFromPtr(doc));
}

pub fn draw(doc: *HistoryDocument, u: *ui.Ui, area: Rect, focused: bool) void {
    _ = focused;
    u.painter.fill(area, u.style.panel);
    reloadAfterDiskChange(doc, u);
    if (doc.focus_search) {
        doc.focus_search = false;
        u.focus = searchId(doc);
        doc.view.search.selectAll();
    }
    var r = area;
    topBar(doc, u, r.takeTop(u.px(44)).inset(u.px(10), u.px(7)));
    const bottom = r.takeBottom(@round(area.h * 0.34));
    rows.draw(doc, u, r);
    emptyText(doc, u, r);
    ui.widgets.separator(u, bottom);
    details.draw(doc, u, bottom);
}

/// A burst of changes in .git reloads once, half a second after (the Mac's).
fn reloadAfterDiskChange(doc: *HistoryDocument, u: *ui.Ui) void {
    if (doc.disk_dirty) {
        doc.disk_dirty = false;
        if (doc.reload_due_ms == null) doc.reload_due_ms = u.now_ms + 500;
    }
    const due = doc.reload_due_ms orelse return;
    if (u.now_ms < due) return u.requestFrame(@intCast(due - u.now_ms));
    doc.reload_due_ms = null;
    doc.reload();
}

fn topBar(doc: *HistoryDocument, u: *ui.Ui, area: Rect) void {
    var r = area;
    const shown = doc.shown();
    var buf: [48]u8 = undefined;
    const n = shown.len();
    const count = if (doc.search != null)
        std.fmt.bufPrint(&buf, "{d} {s}", .{ n, strings.t("found", "encontrados") }) catch ""
    else if (n == 1) "1 commit" else std.fmt.bufPrint(&buf, "{d} commits", .{n}) catch "";
    const count_w = u.painter.measure(count, u.style.small()) + u.px(12);
    u.painter.text(count, u.style.small(), r.takeRight(count_w), u.style.secondary_text, .{ .@"align" = .trailing });
    const feed = if (doc.search) |*s| s else &doc.main;
    if (feed.loading) spinner(u, r.takeRight(r.h));

    const label = strings.t("Current branch only", "Só a branch atual");
    const label_w = u.painter.measure(label, u.style.ui()) + u.px(50);
    const toggle_r = r.takeRight(label_w);
    _ = r.takeRight(u.px(10));
    if (ui.widgets.toggle(u, ui.child(listId(doc), 0x70), toggle_r, doc.current_only)) |_| commands.run("history.current-branch");
    u.painter.text(label, u.style.ui(), .{ .x = toggle_r.x + u.px(42), .y = toggle_r.y, .w = toggle_r.w - u.px(42), .h = toggle_r.h }, u.style.text, .{});

    const field_id = searchId(doc);
    if (u.focus == field_id and u.key(w.c.VK_DOWN, .{})) u.focus = listId(doc);
    const result = ui.text_field.textField(u, field_id, r, &doc.view.search, &doc.view.search_scroll, .{
        .placeholder = strings.t("Filter by subject, author or SHA (Enter searches the repository)", "Filtrar por assunto, autor ou sha (Enter busca no repositório)"),
    });
    if (result.cancelled) {
        doc.view.search.set(u.gpa, "") catch {};
        doc.setFilter("");
    } else if (result.changed) doc.setFilter(doc.view.search.text());
    if (result.submitted) doc.searchRepository();
}

fn emptyText(doc: *HistoryDocument, u: *ui.Ui, area: Rect) void {
    const m = &doc.main;
    const text = if (m.commits.items.len > 0 or doc.search != null)
        ""
    else if (m.failed)
        strings.t("Couldn't read this repository's history", "Não foi possível ler o histórico deste repositório")
    else if (m.ended)
        strings.t("No commits yet", "Nenhum commit ainda")
    else
        strings.t("Loading history…", "Carregando o histórico…");
    if (text.len == 0) return;
    u.painter.text(text, u.style.ui(), area, u.style.secondary_text, .{ .@"align" = .center });
}

/// Eight dots around a circle, the brightest turning every 90 ms (the same
/// as source control's: features do not share code but through shared/).
pub fn spinner(u: *ui.Ui, r: Rect) void {
    const center = r.center();
    const radius = @min(r.w, r.h) * 0.28;
    const step: usize = @intCast(@mod(@divTrunc(u.now_ms, 90), 8));
    for (0..8) |i| {
        const angle = @as(f32, @floatFromInt(i)) * std.math.pi / 4;
        const at: gfx.Point = .{ .x = center.x + radius * @cos(angle), .y = center.y + radius * @sin(angle) };
        const age = (i + 8 - step) % 8;
        u.painter.fillEllipse(at, u.px(1.6), u.px(1.6), u.style.secondary_text.alpha(1 - @as(f32, @floatFromInt(age)) / 9));
    }
    u.requestFrame(90);
}

/// Opens a web address in the default browser (the commit on origin).
pub fn openUrl(gpa: std.mem.Allocator, url: []const u8) void {
    const wide = std.unicode.wtf8ToWtf16LeAllocZ(gpa, url) catch return;
    defer gpa.free(wide);
    _ = w.c.ShellExecuteW(null, w.L("open"), wide.ptr, null, null, w.c.SW_SHOWNORMAL);
}

/// Whether `path` is in `root`'s .git folder; either separator, any case.
pub fn isInGitFolder(root: []const u8, path: []const u8) bool {
    if (path.len < root.len + 5) return false;
    for (root, path[0..root.len]) |a, b| {
        if (norm(a) != norm(b)) return false;
    }
    const rest = path[root.len..];
    if (norm(rest[0]) != '/' or !std.ascii.eqlIgnoreCase(rest[1..5], ".git")) return false;
    return rest.len == 5 or norm(rest[5]) == '/';
}

fn norm(ch: u8) u8 {
    return if (ch == '\\') '/' else std.ascii.toLower(ch);
}

test "only changes in .git reload the history" {
    try std.testing.expect(isInGitFolder("C:/src/cadex", "C:\\src\\cadex\\.git\\refs\\heads\\main"));
    try std.testing.expect(isInGitFolder("C:/src/cadex", "c:/src/cadex/.git"));
    try std.testing.expect(!isInGitFolder("C:/src/cadex", "C:/src/cadex/.github/x"));
    try std.testing.expect(!isInGitFolder("C:/src/cadex", "C:/src/cadex/src/a.zig"));
}

test {
    @import("win32").refAllDeep(@This());
}
