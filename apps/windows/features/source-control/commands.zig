//! The source-control commands (ADR 0005), the Mac's ids, titles and
//! keywords (SourceControlCommands.swift). The buttons, the lists' menu
//! and Ctrl+Enter in the message run these ids. git.show (show the Git
//! page, ⇧⌘G) belongs to the app, which owns the sidebar, as on the Mac.

const std = @import("std");
const palette = @import("command-palette");
const strings = @import("strings");
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
    registry.add(.{ .id = "git.commit", .title = strings.t("Commit", "Fazer o commit"), .keywords = &.{ "commit", "git" }, .run = commit, .available = hasRepo });
    registry.add(.{ .id = "git.stage-all", .title = strings.t("Stage All Changes", "Stage de todas as mudanças"), .keywords = &.{ "git add", "stage" }, .run = stageAll, .available = hasRepo });
    registry.add(.{ .id = "git.unstage-all", .title = strings.t("Unstage All", "Unstage de tudo"), .keywords = &.{ "git reset", "unstage" }, .run = unstageAll, .available = hasRepo });
    registry.add(.{ .id = "git.stage", .title = strings.t("Stage File", "Stage do arquivo"), .keywords = &.{"git add"}, .run = stage, .available = hasSelection });
    registry.add(.{ .id = "git.unstage", .title = strings.t("Unstage File", "Unstage do arquivo"), .keywords = &.{"git reset"}, .run = unstage, .available = hasSelection });
    registry.add(.{ .id = "git.discard", .title = strings.t("Discard File Changes", "Descartar as mudanças do arquivo"), .keywords = &.{ "git restore", "desfazer", "undo" }, .run = discard, .available = hasSelection });
    registry.add(.{ .id = "git.open-diff", .title = strings.t("Open File Diff", "Ver o diff do arquivo"), .keywords = &.{"diff"}, .run = openDiff, .available = hasSelection });
    registry.add(.{ .id = "git.open-diff-beside", .title = strings.t("Open Diff Beside", "Ver o diff ao lado"), .keywords = &.{"diff"}, .run = openDiffBeside, .available = hasSelection });
    registry.add(.{ .id = "git.open-diff-in-tab", .title = strings.t("Open Diff in New Tab", "Ver o diff em nova aba"), .keywords = &.{"diff"}, .run = openDiffInTab, .available = hasSelection });
    registry.add(.{ .id = "git.open-file", .title = strings.t("Open Changed File", "Abrir o arquivo alterado"), .keywords = &.{ "abrir", "open" }, .run = openFile, .available = hasSelection });
    registry.add(.{ .id = "git.open-file-beside", .title = strings.t("Open File Beside", "Abrir o arquivo ao lado"), .keywords = &.{ "abrir", "open" }, .run = openFileBeside, .available = hasSelection });
    registry.add(.{ .id = "git.open-file-in-tab", .title = strings.t("Open File in New Tab", "Abrir o arquivo em nova aba"), .keywords = &.{ "abrir", "open" }, .run = openFileInTab, .available = hasSelection });
    // The Mac says "in Finder"; here it is File Explorer.
    registry.add(.{ .id = "git.reveal", .title = strings.t("Reveal Changed File in File Explorer", "Revelar o arquivo alterado no Explorador de Arquivos"), .keywords = &.{ "explorer", "finder", "mostrar", "show" }, .run = reveal, .available = hasSelection });
    registry.add(.{ .id = "git.fetch", .title = strings.t("Git Fetch", "Git fetch"), .keywords = &.{ "buscar", "remoto" }, .run = fetch, .available = hasRepo });
    registry.add(.{ .id = "git.pull", .title = strings.t("Git Pull (Fast-Forward Only)", "Git pull (só fast-forward)"), .keywords = &.{ "puxar", "atualizar" }, .run = pull, .available = hasRepo });
    registry.add(.{ .id = "git.push", .title = strings.t("Git Push", "Git push"), .keywords = &.{ "enviar", "publicar" }, .run = push, .available = hasRepo });
    registry.add(.{ .id = "git.refresh", .title = strings.t("Refresh Git Status", "Atualizar o status do git"), .keywords = &.{ "status", "refresh" }, .run = refresh, .available = hasRepo });
    registry.add(.{ .id = "diff.toggle-layout", .title = strings.t("Toggle Side-by-Side/Unified Diff", "Alternar diff lado a lado/unificado"), .keywords = &.{ "diff", "patch", "unified" }, .run = toggleLayout, .available = hasDiff });
    registry.add(.{ .id = "git.switch-branch", .title = strings.t("Switch Branch", "Trocar de branch"), .keywords = &.{ "checkout", "switch", "branch" }, .run = switchBranch, .available = hasRepo });
}

test {
    @import("win32").refAllDeep(@This());
}
