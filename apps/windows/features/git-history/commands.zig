//! The history's commands (ADR 0005), the Mac's ids, titles, keywords and
//! shortcut (HistoryCommands.swift). The pane's menu and toggle run these
//! ids; they act on the history in the focused pane.

const std = @import("std");
const palette = @import("command-palette");
const strings = @import("strings");
const host_mod = @import("host.zig");
const HistoryDocument = @import("document.zig").HistoryDocument;

var host: host_mod.Host = undefined;
var gpa: std.mem.Allocator = undefined;
var registry: ?*palette.Registry = null;

/// Runs a registered command by id (the pane's menu and toggle).
pub fn run(id: []const u8) void {
    if (registry) |r| _ = r.run(id);
}

fn active() ?*HistoryDocument {
    const doc = host.focused_document(host.context) orelse return null;
    return HistoryDocument.from(doc);
}

fn hasRepository(_: ?*anyopaque) bool {
    return host.repository(host.context) != null;
}
fn hasTab(_: ?*anyopaque) bool {
    return active() != null;
}
fn hasCommit(_: ?*anyopaque) bool {
    const doc = active() orelse return false;
    return doc.hasSelection();
}

/// git.history: the Git page's repository in a pane (the same one again
/// goes to the pane that shows it: the tabs compare identities).
fn openHow(how: palette.How) void {
    const root = host.repository(host.context) orelse return;
    const doc = HistoryDocument.create(gpa, host, root) orelse return;
    host.open_document(host.context, doc, how);
}
fn open(_: ?*anyopaque) void {
    openHow(.normal);
}
fn openInTab(_: ?*anyopaque) void {
    openHow(.new_tab);
}
fn copySha(_: ?*anyopaque) void {
    if (active()) |d| d.copySha();
}
fn openRemote(_: ?*anyopaque) void {
    if (active()) |d| d.openRemote();
}
fn search(_: ?*anyopaque) void {
    if (active()) |d| d.focusSearch();
}
fn currentBranch(_: ?*anyopaque) void {
    if (active()) |d| d.toggleCurrentOnly();
}
fn refresh(_: ?*anyopaque) void {
    if (active()) |d| d.reload();
}

pub fn register(into: *palette.Registry, allocator: std.mem.Allocator, with: host_mod.Host) void {
    host = with;
    gpa = allocator;
    registry = into;
    into.add(.{ .id = "git.history", .title = strings.t("Open Git History", "Abrir o histórico do git"), .keywords = &.{ "log", "grafo", "graph", "commits" }, .run = open, .available = hasRepository });
    into.add(.{ .id = "git.history-in-tab", .title = strings.t("Open Git History in New Tab", "Abrir o histórico do git em nova aba"), .keywords = &.{ "log", "grafo", "graph", "commits", "aba", "tab" }, .run = openInTab, .available = hasRepository });
    into.add(.{ .id = "history.copy-sha", .title = strings.t("Copy Commit SHA", "Copiar o sha do commit"), .keywords = &.{ "sha", "hash", "copiar", "copy" }, .run = copySha, .available = hasCommit });
    into.add(.{ .id = "history.open-remote", .title = strings.t("Open Commit on Remote", "Abrir o commit no remoto"), .keywords = &.{ "github", "gitlab", "bitbucket", "navegador", "browser" }, .run = openRemote, .available = hasCommit });
    into.add(.{ .id = "history.search", .title = strings.t("Search History", "Buscar no histórico"), .keywords = &.{ "filtrar", "commit", "autor", "filter", "author" }, .run = search, .available = hasTab });
    into.add(.{ .id = "history.current-branch", .title = strings.t("Toggle Current Branch Only in History", "Histórico só da branch atual (ligar/desligar)"), .keywords = &.{ "branch", "filtro", "HEAD", "filter" }, .run = currentBranch, .available = hasTab });
    into.add(.{ .id = "history.refresh", .title = strings.t("Refresh History", "Atualizar o histórico"), .keywords = &.{ "recarregar", "log", "reload" }, .run = refresh, .available = hasTab });
}

test {
    @import("win32").refAllDeep(@This());
}
