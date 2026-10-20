//! The source-control commands (ADR 0005), the Mac's ids, titles and
//! keywords (SourceControlCommands.swift). The buttons, the lists' menu
//! and Ctrl+Enter in the message run these ids. git.show (show the Git
//! page, ⇧⌘G) belongs to the app, which owns the sidebar, as on the Mac.

const std = @import("std");
const palette = @import("command-palette");
const controller = @import("controller.zig");
const opening = @import("opening.zig");
const status_mod = @import("status.zig");
const DiffDocument = @import("diff_document.zig").DiffDocument;

const SourceControl = controller.SourceControl;

var target: *SourceControl = undefined;

fn hasRepo(_: ?*anyopaque) bool {
    return target.root != null;
}

fn hasSelection(_: ?*anyopaque) bool {
    return target.root != null and !target.selection.isEmpty();
}

fn activeDiff() ?*DiffDocument {
    const doc = target.host.focused_document(target.host.context) orelse return null;
    return DiffDocument.from(doc);
}

fn hasDiff(_: ?*anyopaque) bool {
    return activeDiff() != null;
}

/// The selected files, gpa-owned (free with the gpa).
fn selected() []status_mod.Entry {
    const picked = target.selection.entries(target.gpa, target.status);
    defer target.gpa.free(picked);
    const out = target.gpa.alloc(status_mod.Entry, picked.len) catch return &.{};
    for (picked, out) |p, *e| e.* = p.entry;
    return out;
}

fn commit(_: ?*anyopaque) void {
    target.commit();
}
fn stageAll(_: ?*anyopaque) void {
    target.stageAll();
}
fn unstageAll(_: ?*anyopaque) void {
    target.unstageAll();
}
fn stage(_: ?*anyopaque) void {
    const list = selected();
    defer target.gpa.free(list);
    target.onPaths(.stage, list);
}
fn unstage(_: ?*anyopaque) void {
    const list = selected();
    defer target.gpa.free(list);
    target.onPaths(.unstage, list);
}
fn discard(_: ?*anyopaque) void {
    const list = selected();
    defer target.gpa.free(list);
    target.discard(list);
}
fn openDiffHow(how: palette.How) void {
    const picked = target.selection.entries(target.gpa, target.status);
    defer target.gpa.free(picked);
    if (picked.len > 0) opening.openDiff(target, picked[0].entry, picked[0].staged, how);
}
fn openDiff(_: ?*anyopaque) void {
    openDiffHow(.normal);
}
fn openDiffBeside(_: ?*anyopaque) void {
    openDiffHow(.beside);
}
fn openDiffInTab(_: ?*anyopaque) void {
    openDiffHow(.new_tab);
}
fn openFileHow(how: palette.How) void {
    const list = selected();
    defer target.gpa.free(list);
    if (list.len > 0) opening.openFile(target, list[0], how);
}
fn openFile(_: ?*anyopaque) void {
    openFileHow(.normal);
}
fn openFileBeside(_: ?*anyopaque) void {
    openFileHow(.beside);
}
fn openFileInTab(_: ?*anyopaque) void {
    openFileHow(.new_tab);
}
fn reveal(_: ?*anyopaque) void {
    const list = selected();
    defer target.gpa.free(list);
    opening.reveal(target, list);
}
fn fetch(_: ?*anyopaque) void {
    target.sync(.fetch);
}
fn pull(_: ?*anyopaque) void {
    target.sync(.pull);
}
fn push(_: ?*anyopaque) void {
    target.push();
}
fn refresh(_: ?*anyopaque) void {
    target.refresh();
}
fn toggleLayout(_: ?*anyopaque) void {
    if (activeDiff()) |d| d.toggleLayout();
}
fn switchBranch(_: ?*anyopaque) void {
    target.branches.open();
}

pub fn register(registry: *palette.Registry, sc: *SourceControl) void {
    target = sc;
    sc.registry = registry;
    registry.add(.{ .id = "git.commit", .title = "Fazer o commit", .keywords = &.{ "commit", "git" }, .run = commit, .available = hasRepo });
    registry.add(.{ .id = "git.stage-all", .title = "Stage de todas as mudanças", .keywords = &.{ "git add", "stage" }, .run = stageAll, .available = hasRepo });
    registry.add(.{ .id = "git.unstage-all", .title = "Unstage de tudo", .keywords = &.{ "git reset", "unstage" }, .run = unstageAll, .available = hasRepo });
    registry.add(.{ .id = "git.stage", .title = "Stage do arquivo", .keywords = &.{"git add"}, .run = stage, .available = hasSelection });
    registry.add(.{ .id = "git.unstage", .title = "Unstage do arquivo", .keywords = &.{"git reset"}, .run = unstage, .available = hasSelection });
    registry.add(.{ .id = "git.discard", .title = "Descartar as mudanças do arquivo", .keywords = &.{ "git restore", "desfazer" }, .run = discard, .available = hasSelection });
    registry.add(.{ .id = "git.open-diff", .title = "Ver o diff do arquivo", .keywords = &.{"diff"}, .run = openDiff, .available = hasSelection });
    registry.add(.{ .id = "git.open-diff-beside", .title = "Ver o diff ao lado", .keywords = &.{"diff"}, .run = openDiffBeside, .available = hasSelection });
    registry.add(.{ .id = "git.open-diff-in-tab", .title = "Ver o diff em nova aba", .keywords = &.{"diff"}, .run = openDiffInTab, .available = hasSelection });
    registry.add(.{ .id = "git.open-file", .title = "Abrir o arquivo alterado", .keywords = &.{"abrir"}, .run = openFile, .available = hasSelection });
    registry.add(.{ .id = "git.open-file-beside", .title = "Abrir o arquivo ao lado", .keywords = &.{"abrir"}, .run = openFileBeside, .available = hasSelection });
    registry.add(.{ .id = "git.open-file-in-tab", .title = "Abrir o arquivo em nova aba", .keywords = &.{"abrir"}, .run = openFileInTab, .available = hasSelection });
    // The Mac says "no Finder"; here it is File Explorer.
    registry.add(.{ .id = "git.reveal", .title = "Revelar o arquivo alterado no Explorador de Arquivos", .keywords = &.{ "explorer", "finder", "mostrar" }, .run = reveal, .available = hasSelection });
    registry.add(.{ .id = "git.fetch", .title = "Git fetch", .keywords = &.{ "buscar", "remoto" }, .run = fetch, .available = hasRepo });
    registry.add(.{ .id = "git.pull", .title = "Git pull (só fast-forward)", .keywords = &.{ "puxar", "atualizar" }, .run = pull, .available = hasRepo });
    registry.add(.{ .id = "git.push", .title = "Git push", .keywords = &.{ "enviar", "publicar" }, .run = push, .available = hasRepo });
    registry.add(.{ .id = "git.refresh", .title = "Atualizar o status do git", .keywords = &.{ "status", "refresh" }, .run = refresh, .available = hasRepo });
    registry.add(.{ .id = "diff.toggle-layout", .title = "Alternar diff lado a lado/unificado", .keywords = &.{ "diff", "patch", "unified" }, .run = toggleLayout, .available = hasDiff });
    registry.add(.{ .id = "git.switch-branch", .title = "Trocar de branch", .keywords = &.{ "checkout", "switch", "branch" }, .run = switchBranch, .available = hasRepo });
}

test {
    @import("win32").refAllDeep(@This());
}
