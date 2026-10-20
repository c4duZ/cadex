//! The Git side of the app (the Mac's main.swift wiring of source control
//! and history): the sidebar's Git page drawn by source-control, the hosts
//! of both features, git.show, the explorer's change letters, and the
//! repository following the workspace.

const std = @import("std");
const w = @import("win32");
const gfx = @import("gfx");
const tabs = @import("tabs");
const palette = @import("command-palette");
const source_control = @import("source-control");
const git_history = @import("git-history");
const viewers = @import("viewers.zig");
const opener = @import("opener.zig");
const window_mod = @import("window.zig");
const App = @import("app.zig").App;

const c = w.c;

fn of(context: *anyopaque) *App {
    return @ptrCast(@alignCast(context));
}

pub fn draw(app: *App, area: gfx.Rect) void {
    source_control.draw(app.git, &app.u, area);
}

/// Every frame, the page shown or not: git's answers, refreshes, questions.
pub fn frame(app: *App) void {
    app.git.frame(&app.u);
}

pub fn create(app: *App) !void {
    app.git = try source_control.SourceControl.create(app.gpa, .{
        .context = app,
        .post_redraw = postRedraw,
        .open_document = openDocument,
        .open_file = openFile,
        .trash = trash,
        .reveal = reveal,
        .open_palette = openPalette,
        .focused_document = viewers.focusedDocument,
    });
}

pub fn register(app: *App) void {
    source_control.register(&app.registry, app.git);
    git_history.register(&app.registry, app.gpa, historyHost(app));
    app.registry.add(.{ .id = "git.show", .title = "Mostrar o Git", .keywords = &.{ "source control", "git", "mudanças", "commit" }, .shortcut = "cmd+shift+g", .run = show, .context = app });
}

fn historyHost(app: *App) git_history.Host {
    return .{
        .context = app,
        .post_redraw = postRedraw,
        .open_document = openDocument,
        .focused_document = viewers.focusedDocument,
        .repository = repository,
        .open_commit_diff = openCommitDiff,
    };
}

/// A saved "history:<repo>" pane again, if the repository is still there.
pub fn restoreHistory(app: *App, root: []const u8) ?tabs.Document {
    const probe = std.fmt.allocPrint(app.gpa, "{s}\\.git", .{root}) catch return null;
    defer app.gpa.free(probe);
    if (!viewers.exists(app, probe) or !viewers.authorize(app, root)) return null;
    return git_history.HistoryDocument.create(app.gpa, historyHost(app), root);
}

fn show(context: ?*anyopaque) void {
    const app = of(context.?);
    app.sidebar.visible = true;
    app.sidebar.page = .git;
    app.git.refresh();
    app.window.redraw();
}

/// The workspace moved: the Git page looks for the repository there.
pub fn setFolder(app: *App, folder: []const u8) void {
    app.git.setFolder(folder);
}

/// The explorer's letter for a path (Host.git_mark).
pub fn mark(context: *anyopaque, path: []const u8) u8 {
    return of(context).git.markOf(path);
}

/// Disk changes reach the status and every open history.
pub fn diskChanged(app: *App, paths: []const []const u8) void {
    app.git.diskChanged(paths);
    var docs: std.ArrayList(tabs.Document) = .empty;
    defer docs.deinit(app.gpa);
    for (app.spaces.list.items) |s| s.tabs.documents(&docs);
    for (docs.items) |d| if (git_history.HistoryDocument.from(d)) |h| h.diskChanged(paths);
}

// ---- The hosts ----

/// From a worker thread: only wake the window.
fn postRedraw(context: *anyopaque) void {
    _ = c.PostMessageW(of(context).window.hwnd, window_mod.WM_APP_WAKE, 0, 0);
}

/// A diff or a history: after the frame, since a click in a document
/// (a file of a commit) asks for it while that document draws.
fn openDocument(context: *anyopaque, doc: tabs.Document, how: palette.How) void {
    viewers.defer_(of(context), .{ .document = .{ .doc = doc, .how = how } });
}

fn openFile(context: *anyopaque, path: []const u8, how: palette.How) void {
    const app = of(context);
    const copy = app.gpa.dupe(u8, path) catch return;
    const where: opener.How = switch (how) {
        .normal => .setting,
        .beside => .beside,
        .new_tab => .tab,
    };
    viewers.defer_(app, .{ .file = .{ .path = copy, .line = 0, .how = where } });
}

fn openPalette(context: *anyopaque, source: palette.Source) void {
    const app = of(context);
    app.palette.toggle(&app.u, source);
}

fn repository(context: *anyopaque) ?[]const u8 {
    return of(context).git.repositoryRoot();
}

fn openCommitDiff(context: *anyopaque, repo: []const u8, sha: []const u8, path: []const u8, orig: []const u8) void {
    const app = of(context);
    const doc = source_control.DiffDocument.create(app.gpa, app.git.host, .{ .repo = repo, .path = path, .orig = orig, .commit = sha }) orelse return;
    openDocument(context, doc, .normal);
}

/// "Descartar" of a new file: to the Recycle Bin, with undo.
fn trash(context: *anyopaque, path: []const u8) bool {
    const app = of(context);
    var list: std.ArrayList(u16) = .empty;
    defer list.deinit(app.gpa);
    const wide = std.unicode.wtf8ToWtf16LeAlloc(app.gpa, path) catch return false;
    defer app.gpa.free(wide);
    // SHFileOperation takes a list ended by two NULs.
    list.appendSlice(app.gpa, wide) catch return false;
    list.appendSlice(app.gpa, &.{ 0, 0 }) catch return false;
    var op: c.SHFILEOPSTRUCTW = std.mem.zeroes(c.SHFILEOPSTRUCTW);
    op.wFunc = c.FO_DELETE;
    op.pFrom = @ptrCast(list.items.ptr);
    op.fFlags = c.FOF_ALLOWUNDO | c.FOF_NOCONFIRMATION | c.FOF_SILENT;
    return c.SHFileOperationW(&op) == 0 and op.fAnyOperationsAborted == 0;
}

/// Windows Explorer with the first file selected (explorer.exe /select
/// takes one; the Mac's Finder shows them all).
fn reveal(context: *anyopaque, paths: []const []const u8) void {
    const app = of(context);
    if (paths.len == 0) return;
    const args = std.fmt.allocPrint(app.gpa, "/select,\"{s}\"", .{paths[0]}) catch return;
    defer app.gpa.free(args);
    const wide = std.unicode.wtf8ToWtf16LeAllocZ(app.gpa, args) catch return;
    defer app.gpa.free(wide);
    _ = c.ShellExecuteW(null, w.L("open"), w.L("explorer.exe"), wide.ptr, null, c.SW_SHOWNORMAL);
}

test {
    w.refAllDeep(@This());
}
