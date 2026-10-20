//! What the Git page hands to the app: a file's diff as a document, the
//! file itself, and the files in File Explorer (git.open-diff,
//! git.open-file, git.reveal).

const std = @import("std");
const status_mod = @import("status.zig");
const repository = @import("repository.zig");
const controller = @import("controller.zig");
const diff_document = @import("diff_document.zig");
const palette = @import("command-palette");

const SourceControl = controller.SourceControl;
const Entry = status_mod.Entry;

/// `how`: where the settings say (.normal), beside or in a new tab.
pub fn openDiff(sc: *SourceControl, e: Entry, staged: bool, how: palette.How) void {
    const root = sc.root orelse return;
    const doc = diff_document.DiffDocument.create(sc.gpa, sc.host, .{ .repo = root, .path = e.path, .orig = e.orig, .staged = staged }) orelse return;
    sc.host.open_document(sc.host.context, doc, how);
}

pub fn openFile(sc: *SourceControl, e: Entry, how: palette.How) void {
    const root = sc.root orelse return;
    const path = repository.absolute(sc.gpa, root, e.path) catch return;
    defer sc.gpa.free(path);
    sc.host.open_file(sc.host.context, path, how);
}

/// Deleted files are not there to show: they are left out.
pub fn reveal(sc: *SourceControl, entries: []const Entry) void {
    const root = sc.root orelse return;
    var paths: std.ArrayList([]const u8) = .empty;
    defer {
        for (paths.items) |p| sc.gpa.free(p);
        paths.deinit(sc.gpa);
    }
    for (entries) |e| {
        if (e.worktree == 'D' or (e.index == 'D' and e.worktree == '.')) continue;
        const path = repository.absolute(sc.gpa, root, e.path) catch continue;
        paths.append(sc.gpa, path) catch sc.gpa.free(path);
    }
    if (paths.items.len > 0) sc.host.reveal(sc.host.context, paths.items);
}

test {
    @import("win32").refAllDeep(@This());
}
