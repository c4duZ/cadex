//! A file's diff in a pane (docs/spec/source-control.md, "Diff"), the
//! Mac's DiffDocument: before and after side by side, removed lines red on
//! the left and added ones green on the right, scrolling together; or the
//! patch in one column (diff.toggle-layout). Binary and huge files say so.
//! The diff is read on its own worker: the core blocks on git.

const std = @import("std");
const gfx = @import("gfx");
const ui = @import("ui");
const icons = @import("icons");
const tabs = @import("tabs");
const host_mod = @import("host.zig");
const repository = @import("repository.zig");
const worker_mod = @import("worker.zig");
const diff_lines = @import("diff_lines.zig");
const diff_view = @import("diff_view.zig");
const status_mod = @import("status.zig");

const Host = host_mod.Host;
const DiffRequest = host_mod.DiffRequest;
const Job = worker_mod.Job;

pub const DiffDocument = struct {
    gpa: std.mem.Allocator,
    host: Host,
    worker: *worker_mod.Worker,
    repo: [:0]u8,
    path: [:0]u8,
    orig: [:0]u8,
    staged: bool,
    commit: ?[:0]u8,
    identity_text: []u8,
    title_text: []u8,
    state: enum { loading, ready, failed } = .loading,
    diff: ?repository.Diff = null,
    before_lines: []u32 = &.{},
    after_lines: []u32 = &.{},
    patch_lines: []u32 = &.{},
    marks: ?diff_lines.Marks = null,
    side_by_side: bool = true,
    view: diff_view.State = .{},

    const vtable: tabs.Document.VTable = .{
        .title = title,
        .identity = identity,
        .icon = icon,
        .unsaved = unsaved,
        .draw = draw,
        .focus_id = focusId,
        .destroy = destroy,
    };

    /// A new diff document, reading in the background; null without memory.
    pub fn create(gpa: std.mem.Allocator, host: Host, request: DiffRequest) ?tabs.Document {
        const self = gpa.create(DiffDocument) catch return null;
        self.init(gpa, host, request) catch {
            gpa.destroy(self);
            return null;
        };
        self.load();
        return .{ .ptr = self, .vtable = &vtable };
    }

    fn init(self: *DiffDocument, gpa: std.mem.Allocator, host: Host, r: DiffRequest) !void {
        const repo = try gpa.dupeZ(u8, r.repo);
        errdefer gpa.free(repo);
        const path = try gpa.dupeZ(u8, r.path);
        errdefer gpa.free(path);
        const orig = try gpa.dupeZ(u8, r.orig);
        errdefer gpa.free(orig);
        const commit: ?[:0]u8 = if (r.commit) |cm| try gpa.dupeZ(u8, cm) else null;
        errdefer if (commit) |cm| gpa.free(cm);
        const side = if (commit) |cm| try std.fmt.allocPrint(gpa, "commit {s}", .{cm}) else try gpa.dupe(u8, if (r.staged) "staged" else "work");
        defer gpa.free(side);
        const ident = try std.fmt.allocPrint(gpa, "diff:{s}:{s}/{s}", .{ side, r.repo, r.path });
        errdefer gpa.free(ident);
        const name = status_mod.splitPath(r.path).name;
        const t = if (commit) |cm|
            try std.fmt.allocPrint(gpa, "{s} ({s})", .{ name, cm[0..@min(cm.len, 7)] })
        else
            try std.fmt.allocPrint(gpa, "{s} ({s})", .{ name, if (r.staged) "staged" else "diff" });
        errdefer gpa.free(t);
        const worker = try worker_mod.Worker.create(gpa, .{ .context = host.context, .post = host.post_redraw });
        self.* = .{ .gpa = gpa, .host = host, .worker = worker, .repo = repo, .path = path, .orig = orig, .staged = r.staged, .commit = commit, .identity_text = ident, .title_text = t };
    }

    /// The DiffDocument behind `doc`, when it is one (diff.toggle-layout).
    pub fn from(doc: tabs.Document) ?*DiffDocument {
        return if (doc.vtable == &vtable) @ptrCast(@alignCast(doc.ptr)) else null;
    }

    /// Reads the diff again (the file changed on disk).
    pub fn load(self: *DiffDocument) void {
        Load.submit(self);
    }

    /// diff.toggle-layout: side by side or the patch.
    pub fn toggleLayout(self: *DiffDocument) void {
        self.side_by_side = !self.side_by_side;
    }

    fn loaded(self: *DiffDocument, diff: ?repository.Diff) void {
        self.clear();
        const d = diff orelse {
            self.state = .failed;
            return;
        };
        const gpa = self.gpa;
        self.before_lines = diff_lines.lineStarts(gpa, d.before) catch &.{};
        self.after_lines = diff_lines.lineStarts(gpa, d.after) catch &.{};
        self.patch_lines = diff_lines.lineStarts(gpa, d.patch) catch &.{};
        self.marks = diff_lines.marks(gpa, d.patch, self.before_lines.len, self.after_lines.len) catch null;
        self.diff = d;
        self.state = .ready;
    }

    fn clear(self: *DiffDocument) void {
        const gpa = self.gpa;
        if (self.diff) |*d| d.deinit(gpa);
        self.diff = null;
        gpa.free(self.before_lines);
        gpa.free(self.after_lines);
        gpa.free(self.patch_lines);
        self.before_lines = &.{};
        self.after_lines = &.{};
        self.patch_lines = &.{};
        if (self.marks) |*m| m.deinit(gpa);
        self.marks = null;
    }

    /// "Abrir o arquivo" of a file too big for the diff.
    pub fn openFile(self: *DiffDocument) void {
        const path = repository.absolute(self.gpa, self.repo, self.path) catch return;
        defer self.gpa.free(path);
        self.host.open_file(self.host.context, path, .normal);
    }

    fn get(ptr: *anyopaque) *DiffDocument {
        return @ptrCast(@alignCast(ptr));
    }
    fn title(ptr: *anyopaque) []const u8 {
        return get(ptr).title_text;
    }
    fn identity(ptr: *anyopaque) []const u8 {
        return get(ptr).identity_text;
    }
    fn icon(ptr: *anyopaque) u21 {
        return icons.forFileNamed(status_mod.splitPath(get(ptr).path).name);
    }
    fn unsaved(_: *anyopaque) bool {
        return false;
    }
    fn focusId(ptr: *anyopaque) ui.Id {
        return ui.child(ui.id("scm.diff", 0), @intFromPtr(ptr));
    }
    fn draw(ptr: *anyopaque, u: *ui.Ui, area: gfx.Rect, focused: bool) void {
        const self = get(ptr);
        _ = self.worker.drain();
        diff_view.draw(self, u, area, focused);
    }
    fn destroy(ptr: *anyopaque) void {
        const self = get(ptr);
        const gpa = self.gpa;
        self.worker.stop();
        self.clear();
        gpa.free(self.repo);
        gpa.free(self.path);
        gpa.free(self.orig);
        if (self.commit) |cm| gpa.free(cm);
        gpa.free(self.identity_text);
        gpa.free(self.title_text);
        gpa.destroy(self);
    }
};

/// The worker's job: the two sides and the patch, from copies of the request.
const Load = struct {
    job: Job = .{ .work = work, .finish = finish },
    gpa: std.mem.Allocator,
    owner: *DiffDocument,
    repo: [:0]u8,
    path: [:0]u8,
    orig: ?[:0]u8,
    staged: bool,
    commit: ?[:0]u8,
    diff: ?repository.Diff = null,

    fn submit(owner: *DiffDocument) void {
        const gpa = owner.gpa;
        const self = gpa.create(Load) catch return;
        self.* = .{ .gpa = gpa, .owner = owner, .repo = undefined, .path = undefined, .orig = null, .staged = owner.staged, .commit = null };
        self.copy(owner) catch {
            self.free();
            return;
        };
        owner.worker.submit(&self.job);
    }

    fn copy(self: *Load, owner: *DiffDocument) !void {
        self.repo = try self.gpa.dupeZ(u8, owner.repo);
        errdefer self.gpa.free(self.repo);
        self.path = try self.gpa.dupeZ(u8, owner.path);
        errdefer self.gpa.free(self.path);
        if (owner.orig.len > 0) self.orig = try self.gpa.dupeZ(u8, owner.orig);
        errdefer if (self.orig) |o| self.gpa.free(o);
        if (owner.commit) |cm| self.commit = try self.gpa.dupeZ(u8, cm);
    }

    fn work(job: *Job) void {
        const self: *Load = @fieldParentPtr("job", job);
        self.diff = repository.diff(self.gpa, self.repo, self.path, self.orig, self.staged, self.commit);
    }

    fn finish(job: *Job, cancelled: bool) void {
        const self: *Load = @fieldParentPtr("job", job);
        if (!cancelled) {
            self.owner.loaded(self.diff);
            self.diff = null;
        }
        if (self.diff) |*d| d.deinit(self.gpa);
        self.gpa.free(self.repo);
        self.gpa.free(self.path);
        if (self.orig) |o| self.gpa.free(o);
        if (self.commit) |cm| self.gpa.free(cm);
        self.gpa.destroy(self);
    }

    /// Only for a copy that failed half way (copy() undid its own part).
    fn free(self: *Load) void {
        self.gpa.destroy(self);
    }
};

test {
    @import("win32").refAllDeep(@This());
}
