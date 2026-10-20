//! Entry point of the Git page (docs/spec/source-control.md), the Mac's
//! SourceControlController: finds the repository of the workspace's
//! folder, keeps its status, and runs the actions on the worker. Results
//! come back in frame(), on the window's thread. Destructive actions ask
//! first (question.zig).

const std = @import("std");
const ui = @import("ui");
const palette = @import("command-palette");
const host_mod = @import("host.zig");
const status_mod = @import("status.zig");
const repository = @import("repository.zig");
const worker_mod = @import("worker.zig");
const jobs = @import("jobs.zig");
const selection_mod = @import("selection.zig");
const question = @import("question.zig");
const branches_mod = @import("branches.zig");
const panel = @import("panel.zig");

const Host = host_mod.Host;
const Entry = status_mod.Entry;

pub const State = enum { searching, git_missing, no_repository, ready };

pub const SourceControl = struct {
    gpa: std.mem.Allocator,
    host: Host,
    worker: *worker_mod.Worker,
    /// Set by commands.register: buttons and menus run commands by id (ADR 0005).
    registry: ?*palette.Registry = null,
    folder: std.ArrayList(u8) = .empty,
    /// Bumped when the folder changes: answers about an older one are dropped.
    generation: u32 = 0,
    state: State = .searching,
    root: ?[]u8 = null,
    status: ?status_mod.Status = null,
    rows: []status_mod.Row = &.{},
    refreshing: bool = false,
    refresh_again: bool = false,
    /// A disk change came: refresh at this time (one per burst, as the Mac's 0.3 s).
    refresh_due_ms: ?i64 = null,
    disk_changed: bool = false,
    /// git's last message, or ours ("Escreva uma mensagem para o commit").
    error_text: std.ArrayList(u8) = .empty,
    message: ui.TextBuffer = .{},
    selection: selection_mod.Selection = .{},
    question: ?question.Pending = null,
    branches: branches_mod.Branches = .{},
    view: panel.View = .{},

    pub fn create(gpa: std.mem.Allocator, host: Host) !*SourceControl {
        const self = try gpa.create(SourceControl);
        errdefer gpa.destroy(self);
        const worker = try worker_mod.Worker.create(gpa, .{ .context = host.context, .post = host.post_redraw });
        self.* = .{ .gpa = gpa, .host = host, .worker = worker };
        self.branches.owner = self;
        return self;
    }

    pub fn destroy(self: *SourceControl) void {
        const gpa = self.gpa;
        self.worker.stop();
        self.clearRepository();
        self.folder.deinit(gpa);
        self.error_text.deinit(gpa);
        self.message.deinit(gpa);
        self.selection.deinit(gpa);
        if (self.question) |*q| q.deinit(gpa);
        self.branches.deinit(gpa);
        gpa.destroy(self);
    }

    /// The workspace's (or the focused terminal's) folder: find its
    /// repository. The same folder again does nothing.
    pub fn setFolder(self: *SourceControl, path: []const u8) void {
        if (std.mem.eql(u8, path, self.folder.items) and self.generation != 0) return;
        self.folder.clearRetainingCapacity();
        self.folder.appendSlice(self.gpa, path) catch return;
        self.refind();
    }

    fn refind(self: *SourceControl) void {
        self.generation +%= 1;
        self.clearRepository();
        self.state = .searching;
        jobs.Find.submit(self, self.folder.items);
    }

    fn clearRepository(self: *SourceControl) void {
        if (self.status) |*s| s.deinit(self.gpa);
        self.status = null;
        self.gpa.free(self.rows);
        self.rows = &.{};
        if (self.root) |r| self.gpa.free(r);
        self.root = null;
        self.refreshing = false;
        self.refresh_again = false;
    }

    /// The repository's top folder, for the history (git-history).
    pub fn repositoryRoot(self: *const SourceControl) ?[]const u8 {
        return self.root;
    }

    /// The explorer's letter for `path` (absolute, either separator): the
    /// file's change, or for a folder the first change inside it; 0 for
    /// none. As the Mac's marks: unstaged first, a conflict is U.
    pub fn markOf(self: *const SourceControl, path: []const u8) u8 {
        const root = self.root orelse return 0;
        const s = self.status orelse return 0;
        if (path.len <= root.len or !samePath(path[0..root.len], root) or !isSeparator(path[root.len])) return 0;
        const rel = path[root.len + 1 ..];
        for (s.entries) |e| {
            const exact = samePath(e.path, rel);
            const inside = e.path.len > rel.len and samePath(e.path[0..rel.len], rel) and e.path[rel.len] == '/';
            if (exact or inside) return if (e.kind == .conflict) 'U' else e.letter(!e.isUnstaged());
        }
        return 0;
    }

    /// Something changed on disk (the explorer's watcher, .git included):
    /// read the status again, once per burst.
    pub fn diskChanged(self: *SourceControl, paths: []const []const u8) void {
        const root = self.root orelse return;
        for (paths) |p| {
            if (isWithin(root, p)) {
                self.disk_changed = true;
                return;
            }
        }
    }

    /// Every frame, visible or not: applies what git finished, refreshes
    /// after disk changes and draws an open question over the window.
    pub fn frame(self: *SourceControl, u: *ui.Ui) void {
        _ = self.worker.drain();
        if (self.disk_changed) {
            self.disk_changed = false;
            if (self.refresh_due_ms == null) self.refresh_due_ms = u.now_ms + 300;
        }
        if (self.refresh_due_ms) |due| {
            if (u.now_ms >= due) {
                self.refresh_due_ms = null;
                self.refresh();
            } else u.requestFrame(@intCast(due - u.now_ms));
        }
        if (self.question != null) question.draw(self, u);
    }

    pub fn busy(self: *const SourceControl) bool {
        return self.worker.busy();
    }

    /// git.refresh.
    pub fn refresh(self: *SourceControl) void {
        const root = self.root orelse return;
        if (self.refreshing) {
            self.refresh_again = true;
            return;
        }
        self.refreshing = jobs.Status.submit(self, root);
    }

    // The jobs' answers (jobs.zig), on the window's thread.

    pub fn found(self: *SourceControl, git: bool, root: ?[]u8) void {
        self.root = root;
        self.state = if (!git) .git_missing else if (root == null) .no_repository else .ready;
        self.refresh();
    }

    pub fn statusRead(self: *SourceControl, text: ?[]u8) void {
        self.refreshing = false;
        if (text) |t| {
            if (status_mod.parse(self.gpa, t)) |s| {
                if (status_mod.rows(self.gpa, s)) |r| {
                    if (self.status) |*old| old.deinit(self.gpa);
                    self.gpa.free(self.rows);
                    self.status = s;
                    self.rows = r;
                } else |_| {
                    var dropped = s;
                    dropped.deinit(self.gpa);
                }
            } else |_| {}
        }
        if (self.refresh_again) {
            self.refresh_again = false;
            self.refresh();
        }
    }

    pub fn actionDone(self: *SourceControl, message: *const repository.Message, kind: std.meta.Tag(jobs.Action)) void {
        self.showError(if (message.failed) message.text() else null);
        if (kind == .commit and !message.failed) self.message.set(self.gpa, "") catch {};
        if (kind == .init) return self.refind();
        self.refresh();
    }

    pub fn showError(self: *SourceControl, text: ?[]const u8) void {
        self.error_text.clearRetainingCapacity();
        if (text) |t| self.error_text.appendSlice(self.gpa, t) catch {};
    }

    // Actions (the commands call these).

    /// The paths of `entries` for git, with the old name of a rename too.
    fn pathsOf(self: *SourceControl, entries: []const Entry) ?[][:0]u8 {
        var list: std.ArrayList([:0]u8) = .empty;
        for (entries) |e| {
            list.append(self.gpa, repository.z(self.gpa, e.path) catch break) catch break;
            if (e.orig.len > 0) list.append(self.gpa, repository.z(self.gpa, e.orig) catch break) catch break;
        }
        return list.toOwnedSlice(self.gpa) catch null;
    }

    pub fn onPaths(self: *SourceControl, which: repository.PathAction, entries: []const Entry) void {
        const root = self.root orelse return;
        if (entries.len == 0) return;
        const list = self.pathsOf(entries) orelse return;
        jobs.Run.submit(self, root, .{ .paths = .{ .which = which, .list = list } });
    }

    pub fn stageAll(self: *SourceControl) void {
        self.onAll(.stage, Entry.isUnstaged);
    }

    pub fn unstageAll(self: *SourceControl) void {
        self.onAll(.unstage, Entry.isStaged);
    }

    fn onAll(self: *SourceControl, which: repository.PathAction, in: *const fn (Entry) bool) void {
        const s = self.status orelse return;
        var list: std.ArrayList(Entry) = .empty;
        defer list.deinit(self.gpa);
        for (s.entries) |e| if (in(e) and e.kind != .conflict) list.append(self.gpa, e) catch return;
        self.onPaths(which, list.items);
    }

    pub fn sync(self: *SourceControl, which: repository.Sync) void {
        const root = self.root orelse return;
        jobs.Run.submit(self, root, .{ .sync = which });
    }

    /// git.push: without an upstream, offers to publish the branch first.
    pub fn push(self: *SourceControl) void {
        const root = self.root orelse return;
        const s = self.status orelse return jobs.Run.submit(self, root, .{ .push = null });
        if (s.upstream.len == 0 and !s.detached()) return question.askPublish(self, s.branch);
        jobs.Run.submit(self, root, .{ .push = null });
    }

    /// git.commit (Ctrl+Enter in the message). Nothing staged: asks to take every change.
    pub fn commit(self: *SourceControl) void {
        const root = self.root orelse return;
        const text = std.mem.trim(u8, self.message.text(), " \t\r\n");
        if (text.len == 0) return self.showError("Escreva uma mensagem para o commit");
        const s = self.status orelse return;
        if (!s.hasStaged()) {
            if (s.entries.len == 0) return self.showError("Nenhuma mudança para o commit");
            return question.askCommitAll(self);
        }
        self.commitNow(root, false);
    }

    pub fn commitNow(self: *SourceControl, root: []const u8, all: bool) void {
        const text = repository.z(self.gpa, self.message.text()) catch return;
        jobs.Run.submit(self, root, .{ .commit = .{ .text = text, .all = all } });
    }

    pub fn switchBranch(self: *SourceControl, name: []const u8, remote: bool) void {
        const root = self.root orelse return;
        const n = repository.z(self.gpa, name) catch return;
        jobs.Run.submit(self, root, .{ .switch_to = .{ .name = n, .remote = remote } });
    }

    pub fn initRepository(self: *SourceControl) void {
        const folder = repository.z(self.gpa, self.folder.items) catch return;
        jobs.Run.submit(self, "", .{ .init = folder });
    }

    /// Discards with a question first; new files go to the Recycle Bin.
    pub fn discard(self: *SourceControl, entries: []const Entry) void {
        if (self.root == null or entries.len == 0) return;
        question.askDiscard(self, entries);
    }

    /// Runs a registered command (buttons, menus and keys go through the registry).
    pub fn run(self: *SourceControl, id: []const u8) void {
        if (self.registry) |r| _ = r.run(id);
    }
};

/// Whether `path` is `root` or inside it; either separator, any case
/// (Windows paths are case-insensitive).
pub fn isWithin(root: []const u8, path: []const u8) bool {
    if (path.len < root.len) return false;
    for (root, path[0..root.len]) |a, b| {
        const x = if (a == '\\') '/' else std.ascii.toLower(a);
        const y = if (b == '\\') '/' else std.ascii.toLower(b);
        if (x != y) return false;
    }
    return path.len == root.len or path[root.len] == '/' or path[root.len] == '\\';
}

test "a disk change counts inside the repository only" {
    try std.testing.expect(isWithin("C:/src/cadex", "C:\\src\\cadex\\.git\\index"));
    try std.testing.expect(isWithin("C:/src/cadex", "c:/SRC/cadex"));
    try std.testing.expect(!isWithin("C:/src/cadex", "C:/src/cadex2/a"));
    try std.testing.expect(!isWithin("C:/src/cadex", "C:/src"));
}

test {
    @import("win32").refAllDeep(@This());
}

fn isSeparator(b: u8) bool {
    return b == '/' or b == '\\';
}

/// Equal ignoring case and which separator (Windows paths).
fn samePath(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |x, y| {
        if (isSeparator(x) and isSeparator(y)) continue;
        if (std.ascii.toLower(x) != std.ascii.toLower(y)) return false;
    }
    return true;
}
