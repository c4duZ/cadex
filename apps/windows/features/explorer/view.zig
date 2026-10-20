//! The tree in the sidebar, in the look of VS Code's explorer
//! (docs/spec/explorer.md, "Aparência"): 22-DIP rows, 8 DIPs per level after
//! the arrow, indent guides with the pointer over the tree, a light
//! background under the pointer, the selection in the theme's color (with
//! a thin border while the tree has the focus), git colors and letters,
//! hidden and ignored entries dimmed. One click opens; Ctrl or Shift only
//! select. The tree's own keys (Enter, F2, Del, Ctrl+C, Ctrl+V) run the
//! same commands the context menu does.

const std = @import("std");
const gfx = @import("gfx");
const ui = @import("ui");
const w = @import("win32");
const icons = @import("icons");
const explorer = @import("explorer.zig");
const actions = @import("actions.zig");
const tree_mod = @import("tree.zig");

const Explorer = explorer.Explorer;
const c = w.c;
const p = icons.phosphor;

pub const Result = struct {
    /// Rows dragged out of the tree and dropped at `at` (the app pastes
    /// them into the terminal there).
    dropped_outside: ?[]const []const u8 = null,
    at: gfx.Point = .{},
};

var dragging = false;
var drag_from: gfx.Point = .{};

const menu_items = [_]struct { ?[]const u8, []const u8 }{
    .{ "explorer.open", "Abrir arquivo" },               .{ "explorer.open-beside", "Abrir ao lado" },
    .{ "explorer.open-in-tab", "Abrir em nova aba" },     .{ null, "" },
    .{ "explorer.new-file", "Novo arquivo" },             .{ "explorer.new-folder", "Nova pasta" },
    .{ null, "" },                                        .{ "explorer.rename", "Renomear" },
    .{ "explorer.copy-files", "Copiar arquivos" },        .{ "explorer.paste-files", "Colar arquivos" },
    .{ "explorer.trash", "Mover para a Lixeira" },        .{ null, "" },
    .{ "explorer.copy-path", "Copiar caminho" },          .{ "explorer.copy-relative-path", "Copiar caminho relativo" },
    .{ "explorer.reveal", "Revelar no Explorador" },      .{ "explorer.open-in-terminal", "Abrir no terminal" },
};

/// `run` runs a command by id (the context menu and the tree's keys).
pub fn draw(self: *Explorer, u: *ui.Ui, area: gfx.Rect, run: *const fn (context: *anyopaque, id: []const u8) void, run_context: *anyopaque) Result {
    var result: Result = .{};
    var rest = area;
    header(self, u, rest.takeTop(u.px(30)), run, run_context);
    if (self.message.items.len > 0) {
        const m = rest.takeBottom(u.px(24));
        u.painter.text(self.message.items, u.style.small(), m.inset(u.px(10), 0), u.style.secondary_text, .{});
    }
    const t = &(self.tree orelse {
        u.painter.text("Nenhuma pasta aberta", u.style.ui(), rest.inset(u.px(12), 0), u.style.secondary_text, .{});
        return result;
    });
    var arena: std.heap.ArenaAllocator = .init(u.gpa);
    defer arena.deinit();
    const rows = t.rows(arena.allocator()) catch return result;
    const row_h = u.px(22);
    const focused = u.focus == self.focus_id;
    if (u.pressedOn(rest, .left) or u.pressedOn(rest, .right)) u.focus = self.focus_id;
    if (focused) keys(self, u, rows, run, run_context);
    const view = ui.list.begin(u, ui.id("explorer.list", 0), rest, rows.len, row_h, &self.scroll);
    defer ui.list.end(u);
    const over_tree = u.mouseOver(rest);
    for (view.first..view.last) |i| {
        const row = rows[i];
        const r = view.row(i);
        if (row.note != .none) {
            const note = if (row.note == .empty) "Pasta vazia" else "Sem permissão";
            u.painter.text(note, u.style.small(), indent(u, r, row.depth).inset(u.px(20), 0), u.style.secondary_text.alpha(0.7), .{});
            continue;
        }
        drawRow(self, u, row, r, focused, over_tree, run, run_context);
    }
    if (over_tree) guides(u, rows, view, row_h);
    if (dragging and u.input.released[0]) {
        dragging = false;
        if (!rest.contains(u.input.mouse)) {
            // The paths are the selection's, which outlives this frame.
            result.dropped_outside = @ptrCast(self.selection.items);
            result.at = u.input.mouse;
        } else if (dropTarget(rows, view, u.input.mouse)) |folder| {
            actions.move(self, @ptrCast(self.selection.items), folder.path);
        }
    }
    contextMenu(self, u, run, run_context);
    return result;
}

fn indent(u: *ui.Ui, r: gfx.Rect, depth: u16) gfx.Rect {
    const x = u.px(8) + @as(f32, @floatFromInt(depth)) * u.px(16);
    return .{ .x = r.x + x, .y = r.y, .w = @max(r.w - x, 0), .h = r.h };
}

fn header(self: *Explorer, u: *ui.Ui, r: gfx.Rect, run: *const fn (*anyopaque, []const u8) void, ctx: *anyopaque) void {
    var row = r.inset(u.px(8), 0);
    const buttons = [_]struct { u21, []const u8 }{
        .{ p.arrows_in_line_vertical, "explorer.collapse-all" }, .{ p.arrow_clockwise, "explorer.refresh" },
        .{ p.folder_plus, "explorer.new-folder" },              .{ p.file_plus, "explorer.new-file" },
        .{ p.magnifying_glass, "search.files" },
    };
    for (buttons, 0..) |b, i| {
        const br = row.takeRight(u.px(24));
        if (ui.widgets.iconButton(u, ui.child(ui.id("explorer.header", 0), i), br.inset(0, u.px(3)), b[0], .{ .icon_size = 14, .radius = 4, .color = u.style.secondary_text })) run(ctx, b[1]);
    }
    var name_buf: [128]u8 = undefined;
    const root_name = if (self.root()) |root| tree_mod.baseName(root) else "";
    const upper = std.ascii.upperString(name_buf[0..@min(root_name.len, name_buf.len)], root_name[0..@min(root_name.len, name_buf.len)]);
    u.painter.text(upper, u.style.small(), row, u.style.secondary_text, .{});
}

fn gitColor(letter: u8) ?gfx.Color {
    return switch (letter) {
        'M' => gfx.Color.rgb(0xE2C08D),
        'A', 'U', '?' => gfx.Color.rgb(0x73C991),
        'D' => gfx.Color.rgb(0xC74E39),
        'R' => gfx.Color.rgb(0x73C991),
        else => null,
    };
}

fn drawRow(self: *Explorer, u: *ui.Ui, row: tree_mod.Row, r: gfx.Rect, focused: bool, over_tree: bool, run: *const fn (*anyopaque, []const u8) void, ctx: *anyopaque) void {
    _ = over_tree;
    const node = row.node;
    const id = ui.child(ui.id("explorer.row", 0), std.hash.Wyhash.hash(0, node.path));
    const selected = self.isSelected(node.path);
    const over = u.mouseOver(r);
    if (over) u.next_hot = id;
    if (selected) {
        u.painter.fill(r, u.style.tab_active.alpha(if (focused) 1 else 0.6));
        if (focused) u.painter.stroke(r, 0, u.style.accent.alpha(0.8), @max(1, u.px(1)));
    } else if (over) u.painter.fill(r, u.style.hover());
    if (u.pressedOn(r, .left)) {
        const mods = u.input.mods;
        self.select(node.path, mods.ctrl or mods.shift);
        drag_from = u.input.mouse;
        if (!mods.ctrl and !mods.shift) {
            if (node.isFolder()) {
                if (self.tree) |*t| t.toggle(node);
            } else run(ctx, "explorer.open");
        }
    }
    if (u.pressedOn(r, .right)) {
        if (!selected) self.select(node.path, false);
        self.menu.open(ui.id("explorer.menu", 0), u.input.mouse);
    }
    if (u.input.down[0] and self.isSelected(node.path) and !dragging and over and
        (@abs(u.input.mouse.x - drag_from.x) > u.px(4) or @abs(u.input.mouse.y - drag_from.y) > u.px(4))) dragging = true;

    var content = indent(u, r, row.depth);
    const arrow = content.takeLeft(u.px(16));
    if (node.isFolder()) u.painter.icon(if (node.expanded) p.caret_down else p.caret_right, u.px(11), arrow, u.style.secondary_text);
    const icon_rect = content.takeLeft(u.px(20));
    const dim = node.ignored or (node.name.len > 0 and node.name[0] == '.');
    const alpha: f32 = if (dim) 0.55 else 1;
    // The Material drawing for names the pack knows (ADR 0011), not dimmed:
    // its colors are the point. The rest in Phosphor.
    if (icons.material.drawNamed(u.painter, node.name, node.isFolder(), @round(u.px(16)), icon_rect)) {} else if (node.isFolder()) {
        u.painter.icon(if (node.expanded) p.folder_open else p.folder, u.px(15), icon_rect, u.style.accent.alpha(alpha));
    } else {
        const color = icons.colorForFileNamed(node.name) orelse u.style.secondary_text;
        u.painter.icon(icons.forFileNamed(node.name), u.px(15), icon_rect, color.alpha(alpha));
    }
    const letter: u8 = if (self.host.git_mark) |f| f(self.host.context, node.path) else 0;
    const git = gitColor(letter);
    if (letter != 0 and !node.isFolder()) {
        const lr = content.takeRight(u.px(18));
        u.painter.text(&[_]u8{letter}, u.style.small(), lr, git orelse u.style.secondary_text, .{ .@"align" = .center, .ellipsis = false });
    }
    if (self.renaming) |renaming| if (std.mem.eql(u8, renaming, node.path)) {
        const field = ui.id("explorer.rename", 0);
        const problem = actions.renameProblem(self, node.path, self.rename_text.text());
        const res = ui.text_field.textField(u, field, content.inset(0, u.px(1)), &self.rename_text, &self.rename_scroll, .{ .autofocus = true, .spec = u.style.ui() });
        if (u.focus != field and !res.submitted and !res.cancelled) u.focus = field;
        if (problem != null) u.painter.stroke(content.inset(0, u.px(1)), u.px(6), gfx.Color.rgb(0xE5484D), @max(1, u.px(1)));
        if (res.submitted) {
            actions.finishRename(self);
            u.focus = self.focus_id;
        } else if (res.cancelled) {
            u.gpa.free(renaming);
            self.renaming = null;
            u.focus = self.focus_id;
        }
        return;
    };
    const fg = (git orelse u.style.text).alpha(alpha);
    u.painter.text(row.label, u.style.ui(), content, fg, .{});
}

/// Thin vertical lines from each open folder's arrow down through its children.
fn guides(u: *ui.Ui, rows: []const tree_mod.Row, view: ui.list.View, row_h: f32) void {
    _ = row_h;
    for (rows, 0..) |row, i| {
        if (row.note != .none or !row.node.expanded) continue;
        var end = i + 1;
        while (end < rows.len and rows[end].depth > row.depth) end += 1;
        if (end == i + 1) continue;
        const top = view.row(i + 1).y;
        const bottom = view.row(end - 1).bottom();
        const x = view.area.x + u.px(8) + @as(f32, @floatFromInt(row.depth)) * u.px(16) + u.px(8);
        u.painter.fill(.{ .x = x, .y = top, .w = @max(1, u.px(1)), .h = bottom - top }, u.style.text.alpha(0.12));
    }
}

fn dropTarget(rows: []const tree_mod.Row, view: ui.list.View, at: gfx.Point) ?*tree_mod.Node {
    for (view.first..view.last) |i| {
        if (view.row(i).contains(at)) {
            const node = rows[i].node;
            return if (node.isFolder()) node else null;
        }
    }
    return null;
}

fn keys(self: *Explorer, u: *ui.Ui, rows: []const tree_mod.Row, run: *const fn (*anyopaque, []const u8) void, ctx: *anyopaque) void {
    if (self.renaming != null) return;
    var index: usize = 0;
    for (rows, 0..) |row, i| if (row.note == .none and self.isSelected(row.node.path)) {
        index = i;
        break;
    };
    const none: ui.Mods = .{};
    if (rows.len > 0) {
        var next = index;
        if (u.key(c.VK_DOWN, none)) next = @min(index + 1, rows.len - 1);
        if (u.key(c.VK_UP, none)) next = index -| 1;
        while (next < rows.len and rows[next].note != .none) next += 1;
        if (next != index and next < rows.len) self.select(rows[next].node.path, false);
        const node = rows[@min(index, rows.len - 1)].node;
        if (u.key(c.VK_RIGHT, none) and node.isFolder() and !node.expanded) if (self.tree) |*t| t.toggle(node);
        if (u.key(c.VK_LEFT, none)) {
            if (node.isFolder() and node.expanded) {
                if (self.tree) |*t| t.toggle(node);
            } else if (std.fs.path.dirnameWindows(node.path)) |parent| self.select(parent, false);
        }
    }
    if (u.key(c.VK_RETURN, none)) run(ctx, "explorer.open");
    if (u.key(c.VK_F2, none)) run(ctx, "explorer.rename");
    if (u.key(c.VK_DELETE, none)) run(ctx, "explorer.trash");
    if (u.key('C', .{ .ctrl = true })) run(ctx, "explorer.copy-files");
    if (u.key('V', .{ .ctrl = true })) run(ctx, "explorer.paste-files");
}

fn contextMenu(self: *Explorer, u: *ui.Ui, run: *const fn (*anyopaque, []const u8) void, ctx: *anyopaque) void {
    const owner = ui.id("explorer.menu", 0);
    if (!self.menu.isOpen(owner)) return;
    var items: [menu_items.len]ui.menu.Item = undefined;
    for (menu_items, 0..) |m, i| items[i] = if (m[0] == null) .{ .separator = true } else .{ .label = m[1] };
    if (ui.menu.show(u, &self.menu, owner, &items)) |i| if (menu_items[i][0]) |id| run(ctx, id);
}

test {
    @import("win32").refAllDeep(@This());
}
