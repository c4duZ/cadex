//! The explorer's commands (ADR 0005), the Mac's table (ExplorerCommands.swift)
//! and the workspace's (WorkspaceCommands.swift), by id; the tree's own keys
//! and the context menu run these same ids.

const std = @import("std");
const w = @import("win32");
const ui = @import("ui");
const strings = @import("strings");
const palette = @import("command-palette");
const explorer = @import("explorer.zig");
const actions = @import("actions.zig");

const Explorer = explorer.Explorer;

/// title: { English, Portuguese }, read with strings.t at registration.
pub const Entry = struct { id: []const u8, title: [2][]const u8, keywords: []const []const u8, shortcut: ?[]const u8 = null };

pub const table = [_]Entry{
    .{ .id = "explorer.focus", .title = .{ "Show Files", "Mostrar os arquivos" }, .keywords = &.{ "explorer", "árvore", "focus" }, .shortcut = "cmd+shift+e" },
    .{ .id = "explorer.open", .title = .{ "Open File", "Abrir arquivo" }, .keywords = &.{ "open", "abrir", "open file" } },
    .{ .id = "explorer.open-beside", .title = .{ "Open to the Side", "Abrir ao lado" }, .keywords = &.{ "open beside", "split", "painel", "abrir" } },
    .{ .id = "explorer.open-in-tab", .title = .{ "Open in New Tab", "Abrir em nova aba" }, .keywords = &.{ "open in tab", "aba", "abrir" } },
    .{ .id = "explorer.new-file", .title = .{ "New File", "Novo arquivo" }, .keywords = &.{ "new file", "criar" } },
    .{ .id = "explorer.new-folder", .title = .{ "New Folder", "Nova pasta" }, .keywords = &.{ "new folder", "criar", "diretório" } },
    .{ .id = "explorer.rename", .title = .{ "Rename", "Renomear" }, .keywords = &.{ "rename", "nome" } },
    .{ .id = "explorer.trash", .title = .{ "Move to Recycle Bin", "Mover para a Lixeira" }, .keywords = &.{ "delete", "apagar", "excluir", "trash" } },
    .{ .id = "explorer.copy-files", .title = .{ "Copy Files", "Copiar arquivos" }, .keywords = &.{ "copy", "copiar" } },
    .{ .id = "explorer.paste-files", .title = .{ "Paste Files", "Colar arquivos" }, .keywords = &.{ "paste", "colar" } },
    .{ .id = "explorer.reveal", .title = .{ "Reveal in File Explorer", "Revelar no Explorador" }, .keywords = &.{ "reveal", "explorer", "finder", "mostrar" } },
    .{ .id = "explorer.open-in-finder", .title = .{ "Open in File Explorer", "Abrir no Explorador" }, .keywords = &.{ "open in explorer", "explorer", "finder", "pasta" } },
    .{ .id = "explorer.copy-path", .title = .{ "Copy Path", "Copiar caminho" }, .keywords = &.{ "copy path", "caminho" } },
    .{ .id = "explorer.copy-relative-path", .title = .{ "Copy Relative Path", "Copiar caminho relativo" }, .keywords = &.{ "copy relative path", "caminho" } },
    .{ .id = "explorer.open-in-terminal", .title = .{ "Open in Terminal", "Abrir no terminal" }, .keywords = &.{ "cd", "terminal", "pasta" } },
    .{ .id = "explorer.toggle-hidden", .title = .{ "Show or Hide Hidden Files", "Mostrar ou esconder arquivos ocultos" }, .keywords = &.{ "hidden", "ocultos", "dotfiles" }, .shortcut = "cmd+shift+." },
    .{ .id = "explorer.refresh", .title = .{ "Reload Files", "Recarregar arquivos" }, .keywords = &.{ "refresh", "atualizar" } },
    .{ .id = "explorer.collapse-all", .title = .{ "Collapse All Folders", "Recolher todas as pastas" }, .keywords = &.{ "collapse", "fechar" } },
    .{ .id = "workspace.open-folder", .title = .{ "Open Folder…", "Abrir pasta…" }, .keywords = &.{ "open folder", "workspace", "projeto" }, .shortcut = "cmd+o" },
    .{ .id = "workspace.use-terminal-folder", .title = .{ "Use the Terminal's Folder", "Usar a pasta do terminal" }, .keywords = &.{ "workspace", "cwd", "diretório", "seguir" } },
};

/// What the app gives the commands beyond the explorer: the window for
/// dialogs and the clipboard, focus, the hidden-files setting.
pub const Wiring = struct {
    context: *anyopaque,
    ui: *const fn (context: *anyopaque) *ui.Ui,
    /// explorer.focus: show the sidebar's Files page and give it the keys.
    show: *const fn (context: *anyopaque) void,
    /// explorer.toggle-hidden: flips explorer.showHidden in the settings.
    toggle_hidden: *const fn (context: *anyopaque) void,
    /// Ask before moving several items to the Recycle Bin; calls back with true.
    confirm_trash: *const fn (context: *anyopaque, count: usize) void,
};

var target: *Explorer = undefined;
var wiring: Wiring = undefined;
var slots: [table.len]usize = blk: {
    var s: [table.len]usize = undefined;
    for (&s, 0..) |*v, i| v.* = i;
    break :blk s;
};

pub fn registerWith(self: *Explorer, registry: *palette.Registry, with: Wiring) void {
    target = self;
    wiring = with;
    for (table, 0..) |e, i| registry.add(.{ .id = e.id, .title = strings.t(e.title[0], e.title[1]), .keywords = e.keywords, .shortcut = e.shortcut, .context = &slots[i], .run = runSlot, .available = availableSlot });
}

fn idOf(context: ?*anyopaque) []const u8 {
    const i: *usize = @ptrCast(@alignCast(context.?));
    return table[i.*].id;
}

fn availableSlot(context: ?*anyopaque) bool {
    return available(target, idOf(context));
}

/// Whether the command can run now; the context menu leaves out the rest.
pub fn available(self: *Explorer, id: []const u8) bool {
    const needs_selection = [_][]const u8{ "explorer.open", "explorer.open-beside", "explorer.open-in-tab", "explorer.rename", "explorer.trash", "explorer.copy-files", "explorer.reveal", "explorer.copy-path", "explorer.copy-relative-path" };
    for (needs_selection) |n| if (std.mem.eql(u8, n, id)) return self.selectedNode() != null;
    if (std.mem.eql(u8, id, "explorer.paste-files")) return self.copied.items.len > 0 and self.tree != null;
    if (std.mem.eql(u8, id, "explorer.open-in-finder")) return if (self.selectedNode()) |n| n.isFolder() else true;
    return true;
}

/// The command's title, for the context menu.
pub fn title(id: []const u8) []const u8 {
    for (table) |e| if (std.mem.eql(u8, e.id, id)) return strings.t(e.title[0], e.title[1]);
    return id;
}

fn runSlot(context: ?*anyopaque) void {
    perform(target, idOf(context));
}

pub fn perform(self: *Explorer, id: []const u8) void {
    const u = wiring.ui(wiring.context);
    const eq = struct {
        fn f(a: []const u8, b: []const u8) bool {
            return std.mem.eql(u8, a, b);
        }
    }.f;
    if (eq(id, "explorer.focus")) return wiring.show(wiring.context);
    if (eq(id, "explorer.open") or eq(id, "explorer.open-beside") or eq(id, "explorer.open-in-tab")) {
        const node = self.selectedNode() orelse return;
        if (node.isFolder()) {
            if (self.tree) |*t| t.toggle(node);
            return;
        }
        const how: explorer.OpenHow = if (eq(id, "explorer.open-beside")) .beside else if (eq(id, "explorer.open-in-tab")) .tab else .setting;
        return self.host.open_file(self.host.context, node.path, how);
    }
    if (eq(id, "explorer.new-file")) return actions.create(self, false);
    if (eq(id, "explorer.new-folder")) return actions.create(self, true);
    if (eq(id, "explorer.rename")) return actions.beginRename(self);
    if (eq(id, "explorer.trash")) {
        if (self.selection.items.len > 1) return wiring.confirm_trash(wiring.context, self.selection.items.len);
        return actions.trash(self);
    }
    if (eq(id, "explorer.copy-files")) return actions.copyFiles(self);
    if (eq(id, "explorer.paste-files")) return actions.pasteFiles(self);
    if (eq(id, "explorer.reveal")) return actions.reveal(self);
    if (eq(id, "explorer.open-in-finder")) return actions.openFolder(self);
    if (eq(id, "explorer.copy-path")) return actions.copyPath(self, u, false);
    if (eq(id, "explorer.copy-relative-path")) return actions.copyPath(self, u, true);
    if (eq(id, "explorer.open-in-terminal")) {
        const node = self.selectedNode() orelse return if (self.root()) |r| self.host.open_in_terminal(self.host.context, r);
        const folder = if (node.isFolder()) node.path else std.fs.path.dirnameWindows(node.path) orelse return;
        return self.host.open_in_terminal(self.host.context, folder);
    }
    if (eq(id, "explorer.toggle-hidden")) return wiring.toggle_hidden(wiring.context);
    if (eq(id, "explorer.refresh")) {
        if (self.tree) |*t| t.reload(&.{}, true);
        return;
    }
    if (eq(id, "explorer.collapse-all")) {
        if (self.tree) |*t| t.collapseAll();
        return;
    }
    if (eq(id, "workspace.open-folder")) {
        const folder = actions.pickFolder(self.gpa, u.hwnd) orelse return;
        defer self.gpa.free(folder);
        const hidden = if (self.tree) |t| t.show_hidden else true;
        return self.setRoot(folder, hidden);
    }
    if (eq(id, "workspace.use-terminal-folder")) {
        var buf: [2048]u8 = undefined;
        const folder = self.host.terminal_folder(self.host.context, &buf) orelse return self.say(strings.t("The terminal hasn't told its folder yet", "O terminal ainda não disse a pasta"));
        const hidden = if (self.tree) |t| t.show_hidden else true;
        return self.setRoot(folder, hidden);
    }
}

test {
    @import("win32").refAllDeep(@This());
}
