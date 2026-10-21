//! The selected commit (docs/spec/git-history.md), the Mac's
//! HistoryDetailsView: the whole message, author, date and parents on the
//! left; its files with the kind of change and +/− lines on the right.
//! Clicking a file opens its diff in that commit.

const std = @import("std");
const gfx = @import("gfx");
const ui = @import("ui");
const strings = @import("strings");
const log = @import("log.zig");
const dates = @import("dates.zig");
const HistoryDocument = @import("document.zig").HistoryDocument;

const Rect = gfx.Rect;
const Color = gfx.Color;

pub fn draw(doc: *HistoryDocument, u: *ui.Ui, area: Rect) void {
    var r = area.inset(u.px(10), u.px(8));
    const commit = selectedCommit(doc) orelse {
        u.painter.text(strings.t("Select a commit", "Selecione um commit"), u.style.ui(), r, u.style.secondary_text, .{ .vcenter = false });
        return;
    };
    const left = r.takeLeft(@floor(r.w / 2));
    _ = r.takeLeft(u.px(10));
    info(doc, u, left, commit);
    files(doc, u, r);
}

/// The selected commit among those loaded (its sha is kept across reloads).
fn selectedCommit(doc: *HistoryDocument) ?log.Commit {
    if (!doc.hasSelection()) return null;
    const lists = [_][]const log.Commit{ if (doc.search) |s| s.commits.items else &.{}, doc.main.commits.items };
    for (lists) |list| {
        for (list) |c| if (std.mem.eql(u8, c.sha, doc.selected.items)) return c;
    }
    return null;
}

fn info(doc: *HistoryDocument, u: *ui.Ui, area: Rect, commit: log.Commit) void {
    u.painter.pushClip(area);
    defer u.painter.popClip();
    var r = area;
    const message = if (doc.details) |d| d.message else commit.subject;
    var meta_buf: [1024]u8 = undefined;
    var date_buf: [64]u8 = undefined;
    const meta = metaText(&meta_buf, commit, dates.full(&date_buf, commit.time));
    const meta_lines: f32 = @floatFromInt(std.mem.count(u8, meta, "\n") + 1);
    const meta_r = r.takeBottom(meta_lines * u.px(16) + u.px(4));
    u.painter.text(message, u.style.font(13), r, u.style.text, .{ .vcenter = false });
    u.painter.text(meta, u.style.mono(11), meta_r, u.style.secondary_text, .{ .vcenter = false, .ellipsis = false });
}

/// "Ana <ana@x>\nOctober 17…\ncommit <sha>\nparents abc1234 def5678".
pub fn metaText(buf: []u8, commit: log.Commit, date: []const u8) []const u8 {
    var n = (std.fmt.bufPrint(buf, "{s} <{s}>\n{s}\ncommit {s}", .{ commit.author, commit.email, date, commit.sha }) catch return "").len;
    const parents = std.mem.trim(u8, commit.parents, " ");
    if (parents.len == 0) return buf[0..n];
    const label = if (std.mem.indexOfScalar(u8, parents, ' ') != null) strings.t("parents", "pais") else strings.t("parent", "pai");
    n += (std.fmt.bufPrint(buf[n..], "\n{s}", .{label}) catch return buf[0..n]).len;
    var it = std.mem.tokenizeScalar(u8, parents, ' ');
    while (it.next()) |p| {
        n += (std.fmt.bufPrint(buf[n..], " {s}", .{p[0..@min(p.len, 7)]}) catch break).len;
    }
    return buf[0..n];
}

fn files(doc: *HistoryDocument, u: *ui.Ui, area: Rect) void {
    const d = doc.details orelse return;
    const row_h = u.rowPx(20);
    const base = ui.child(ui.id("history.files", 0), @intFromPtr(doc));
    const list = ui.list.begin(u, base, area, d.files.len, row_h, &doc.view.files_scroll);
    defer ui.list.end(u);
    for (list.first..list.last) |i| {
        const f = d.files[i];
        const r = list.row(i);
        const id = ui.child(base, i + 1);
        // A click, not a selection: the same file again opens its diff again
        // (its pane may have been closed).
        if (u.clickable(id, r)) doc.openDiff(f);
        if (u.mouseOver(r)) {
            u.painter.fillRounded(r, u.px(4), u.style.hover());
            u.cursor = .hand;
        }
        fileRow(u, r.inset(u.px(4), 0), f);
    }
}

/// "M  src/a.zig  +3 −1", the letter in the color the Git page uses.
fn fileRow(u: *ui.Ui, area: Rect, f: log.File) void {
    var r = area;
    u.painter.text(&.{f.letter}, u.style.mono(11), r.takeLeft(u.px(18)), letterColor(f.letter), .{});
    var counts_buf: [40]u8 = undefined;
    if (f.added != null and f.removed != null) {
        const minus = std.fmt.bufPrint(counts_buf[20..], "−{d}", .{f.removed.?}) catch "";
        const plus = std.fmt.bufPrint(counts_buf[0..20], "+{d}", .{f.added.?}) catch "";
        const mw = u.painter.measure(minus, u.style.mono(11)) + u.px(6);
        const pw = u.painter.measure(plus, u.style.mono(11)) + u.px(6);
        u.painter.text(minus, u.style.mono(11), r.takeRight(mw), Color.rgb(0xff453a), .{ .@"align" = .trailing });
        u.painter.text(plus, u.style.mono(11), r.takeRight(pw), Color.rgb(0x30d158), .{ .@"align" = .trailing });
    } else {
        const binary = strings.t("binary", "binário");
        const bw = u.painter.measure(binary, u.style.small()) + u.px(6);
        u.painter.text(binary, u.style.small(), r.takeRight(bw), u.style.secondary_text, .{ .@"align" = .trailing });
    }
    var name_buf: [1024]u8 = undefined;
    const name = if (f.orig.len > 0) std.fmt.bufPrint(&name_buf, "{s} → {s}", .{ f.orig, f.path }) catch f.path else f.path;
    u.painter.text(name, u.style.ui(), r, u.style.text, .{});
}

/// The Git page's colors (source control's status.zig, the Mac's system colors).
fn letterColor(letter: u8) Color {
    return switch (letter) {
        'A' => Color.rgb(0x30d158),
        'D' => Color.rgb(0xff453a),
        'R', 'C' => Color.rgb(0x0a84ff),
        else => Color.rgb(0xff9f0a),
    };
}

test "the details' lines name the author, the commit and the parents" {
    const c: log.Commit = .{ .sha = "abcdef1234", .parents = "1111111aaa 2222222bbb", .author = "Ana", .email = "a@x", .time = 0, .refs = "", .subject = "s", .graph = null };
    var buf: [256]u8 = undefined;
    try std.testing.expectEqualStrings("Ana <a@x>\ntoday\ncommit abcdef1234\nparents 1111111 2222222", metaText(&buf, c, "today"));
    strings.language = .pt;
    defer strings.language = .en;
    try std.testing.expectEqualStrings("Ana <a@x>\nhoje\ncommit abcdef1234\npais 1111111 2222222", metaText(&buf, c, "hoje"));
}

test {
    @import("win32").refAllDeep(@This());
}
