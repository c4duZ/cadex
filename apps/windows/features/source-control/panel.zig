//! The Git page of the sidebar (docs/spec/source-control.md, "Painel"), as
//! the Mac's SourceControlView: branch and sync buttons on top, the lists
//! of changes (change_list.zig), the commit message and its button, git's
//! last message, and the states without a repository. Buttons run
//! commands by id (ADR 0005).

const std = @import("std");
const gfx = @import("gfx");
const ui = @import("ui");
const w = @import("win32");
const icons = @import("icons");
const controller = @import("controller.zig");
const change_list = @import("change_list.zig");

const SourceControl = controller.SourceControl;
const Rect = gfx.Rect;
const p = icons.phosphor;

/// What the page keeps between frames.
pub const View = struct {
    list_scroll: ui.list.Scroll = .{},
    message_scroll: ui.text_field.Scroll = .{},
    menu: ui.menu.Menu = .{},
    /// The row the keyboard is on (Up/Down in the list).
    cursor: usize = 0,
};

pub const message_id = ui.id("scm.message", 0);

pub fn draw(sc: *SourceControl, u: *ui.Ui, area: Rect) void {
    switch (sc.state) {
        .searching => _ = centered(u, area, "Procurando o repositório…", null),
        .git_missing => gitMissing(sc, u, area),
        .no_repository => if (centered(u, area, "Esta pasta não é um repositório git.", "Inicializar repositório")) sc.initRepository(),
        .ready => ready(sc, u, area),
    }
}

/// A grey line in the middle and, maybe, a button under it; true when clicked.
fn centered(u: *ui.Ui, area: Rect, text: []const u8, button: ?[]const u8) bool {
    const mid = area.y + area.h * 0.4;
    const line: Rect = .{ .x = area.x + u.px(16), .y = mid - u.px(11), .w = area.w - u.px(32), .h = u.px(22) };
    u.painter.text(text, u.style.ui(), line, u.style.secondary_text, .{ .@"align" = .center });
    const title = button orelse return false;
    const bw = u.painter.measure(title, u.style.ui()) + u.px(28);
    const r: Rect = .{ .x = area.x + (area.w - bw) / 2, .y = line.bottom() + u.px(10), .w = bw, .h = u.px(30) };
    u.painter.fillRounded(r, u.px(6), u.style.field);
    return ui.widgets.button(u, ui.id("scm.center-button", 0), r, title, .{});
}

/// The Windows text of the spec: the link to Git for Windows.
fn gitMissing(sc: *SourceControl, u: *ui.Ui, area: Rect) void {
    _ = sc;
    const mid = area.y + area.h * 0.35;
    var y = mid;
    for ([_][]const u8{ "O git não foi encontrado.", "Instale o Git for Windows:" }) |text| {
        const line: Rect = .{ .x = area.x + u.px(16), .y = y, .w = area.w - u.px(32), .h = u.px(22) };
        u.painter.text(text, u.style.ui(), line, u.style.secondary_text, .{ .@"align" = .center });
        y += u.px(22);
    }
    const link = "git-scm.com/download/win";
    const bw = u.painter.measure(link, u.style.ui()) + u.px(20);
    const r: Rect = .{ .x = area.x + (area.w - bw) / 2, .y = y + u.px(6), .w = bw, .h = u.px(28) };
    if (ui.widgets.button(u, ui.id("scm.git-link", 0), r, link, .{ .color = u.style.accent })) {
        openUrl(u.gpa, "https://git-scm.com/download/win");
    }
    if (u.mouseOver(r)) u.cursor = .hand;
}

/// Opens a web address in the default browser.
pub fn openUrl(gpa: std.mem.Allocator, url: []const u8) void {
    const wide = std.unicode.wtf8ToWtf16LeAllocZ(gpa, url) catch return;
    defer gpa.free(wide);
    _ = w.c.ShellExecuteW(null, w.L("open"), wide.ptr, null, null, w.c.SW_SHOWNORMAL);
}

fn ready(sc: *SourceControl, u: *ui.Ui, area: Rect) void {
    var r = area;
    top(sc, u, r.takeTop(u.px(34)).inset(u.px(8), u.px(3)));
    if (sc.error_text.items.len > 0) {
        const box = r.takeBottom(u.px(48)).inset(u.px(10), u.px(4));
        u.painter.text(sc.error_text.items, u.style.small(), box, gfx.Color.rgb(0xff453a), .{ .vcenter = false });
    }
    var commit_row = r.takeBottom(u.px(38)).inset(u.px(8), u.px(4));
    const commit_r = commit_row.takeRight(u.px(96));
    if (ui.widgets.button(u, ui.id("scm.commit", 0), commit_r, "Commit", .{ .primary = true })) sc.run("git.commit");
    const field = r.takeBottom(u.px(34)).inset(u.px(8), u.px(2));
    // Ctrl+Enter commits, before the field takes the key (the Mac's ⌘Enter).
    if (u.focus == message_id and u.key(w.c.VK_RETURN, .{ .ctrl = true })) sc.run("git.commit");
    _ = ui.text_field.textField(u, message_id, field, &sc.message, &sc.view.message_scroll, .{
        .placeholder = "Mensagem do commit (Ctrl+Enter)",
    });
    _ = r.takeBottom(u.px(4));
    change_list.draw(sc, u, r);
}

/// Branch (click: switch), ahead/behind, the spinner and fetch, pull, push.
fn top(sc: *SourceControl, u: *ui.Ui, area: Rect) void {
    var r = area;
    const size = r.h;
    const buttons = [_]struct { id: []const u8, icon: u21 }{
        .{ .id = "git.push", .icon = p.arrow_up },
        .{ .id = "git.pull", .icon = p.arrow_down },
        .{ .id = "git.fetch", .icon = p.arrows_clockwise },
    };
    for (buttons, 0..) |b, i| {
        if (ui.widgets.iconButton(u, ui.id("scm.sync", i), r.takeRight(size), b.icon, .{ .icon_size = 15, .color = u.style.secondary_text })) sc.run(b.id);
    }
    if (sc.busy()) spinner(u, r.takeRight(size));
    const s = sc.status orelse return;
    var name_buf: [96]u8 = undefined;
    const name = if (s.detached())
        std.fmt.bufPrint(&name_buf, "HEAD destacado em {s}", .{s.oid[0..@min(s.oid.len, 7)]}) catch "HEAD"
    else
        s.branch;
    var sync_buf: [48]u8 = undefined;
    const sync_text = syncText(&sync_buf, s.ahead, s.behind, s.upstream.len == 0 and !s.detached());
    const sync_w = if (sync_text.len > 0) u.painter.measure(sync_text, u.style.small()) + u.px(10) else 0;
    const name_w = @min(u.painter.measure(name, u.style.bold()) + u.px(34), @max(r.w - sync_w, u.px(40)));
    const branch_r = r.takeLeft(name_w);
    const branch_id = ui.id("scm.branch", 0);
    if (u.clickable(branch_id, branch_r)) sc.run("git.switch-branch");
    if (u.isHot(branch_id)) u.painter.fillRounded(branch_r, u.px(6), u.style.hover());
    var inner = branch_r.inset(u.px(6), 0);
    u.painter.icon(p.git_branch, u.px(14), inner.takeLeft(u.px(18)), u.style.text);
    u.painter.text(name, u.style.bold(), inner, u.style.text, .{});
    if (sync_text.len > 0) u.painter.text(sync_text, u.style.small(), r.takeLeft(sync_w).inset(u.px(5), 0), u.style.secondary_text, .{});
}

/// "↑2 ↓1", or "sem upstream".
pub fn syncText(buf: []u8, ahead: u32, behind: u32, no_upstream: bool) []const u8 {
    var n: usize = 0;
    if (ahead > 0) n += (std.fmt.bufPrint(buf[n..], "↑{d} ", .{ahead}) catch return "").len;
    if (behind > 0) n += (std.fmt.bufPrint(buf[n..], "↓{d} ", .{behind}) catch return "").len;
    if (no_upstream) n += (std.fmt.bufPrint(buf[n..], "sem upstream", .{}) catch return "").len;
    return std.mem.trimEnd(u8, buf[0..n], " ");
}

/// Eight dots around a circle, the brightest turning every 90 ms: git is
/// running. A frame is asked for as long as it shows.
pub fn spinner(u: *ui.Ui, r: Rect) void {
    const center = r.center();
    const radius = @min(r.w, r.h) * 0.28;
    const step: usize = @intCast(@mod(@divTrunc(u.now_ms, 90), 8));
    for (0..8) |i| {
        const angle = @as(f32, @floatFromInt(i)) * std.math.pi / 4;
        const at: gfx.Point = .{ .x = center.x + radius * @cos(angle), .y = center.y + radius * @sin(angle) };
        const age = (i + 8 - step) % 8;
        const alpha = 1 - @as(f32, @floatFromInt(age)) / 9;
        u.painter.fillEllipse(at, u.px(1.6), u.px(1.6), u.style.secondary_text.alpha(alpha));
    }
    u.requestFrame(90);
}

test "ahead, behind and the missing upstream read like the Mac's" {
    var buf: [48]u8 = undefined;
    try std.testing.expectEqualStrings("↑2 ↓1", syncText(&buf, 2, 1, false));
    try std.testing.expectEqualStrings("sem upstream", syncText(&buf, 0, 0, true));
    try std.testing.expectEqualStrings("", syncText(&buf, 0, 0, false));
}

test {
    @import("win32").refAllDeep(@This());
}
