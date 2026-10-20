//! Entry point of the history (docs/spec/git-history.md), the Mac's
//! HistoryDocument: a repository's log in a pane. Pages come from the
//! worker as the list scrolls; typing filters what is loaded, Enter
//! searches the whole repository; the selected commit's details and
//! remote address are read in the background.

const std = @import("std");
const gfx = @import("gfx");
const ui = @import("ui");
const icons = @import("icons");
const tabs = @import("tabs");
const host_mod = @import("host.zig");
const worker_mod = @import("worker.zig");
const jobs = @import("jobs.zig");
const log = @import("log.zig");
const view = @import("view.zig");
const feed_mod = @import("feed.zig");

pub const Feed = feed_mod.Feed;
pub const Shown = feed_mod.Shown;

const Host = host_mod.Host;

pub const HistoryDocument = struct {
    gpa: std.mem.Allocator,
    host: Host,
    worker: *worker_mod.Worker,
    root: [:0]u8,
    identity_text: []u8,
    title_text: []u8,
    main: Feed,
    search: ?Feed = null,
    next_feed: u32 = 1,
    filter: std.ArrayList(u8) = .empty,
    current_only: bool = false,
    /// The loaded commits that match the filter (indices into main).
    filtered: std.ArrayList(u32) = .empty,
    filtered_for: usize = std.math.maxInt(usize),
    selected: std.ArrayList(u8) = .empty,
    details_text: ?[]u8 = null,
    details: ?log.Details = null,
    remote_url: ?[]u8 = null,
    disk_dirty: bool = false,
    reload_due_ms: ?i64 = null,
    /// history.search came without a frame: the next one focuses the field.
    focus_search: bool = false,
    /// The window, for the clipboard (history.copy-sha runs without a frame).
    hwnd: @import("win32").c.HWND = null,
    view: view.State = .{},

    const vtable: tabs.Document.VTable = .{
        .title = title,
        .identity = identity,
        .icon = icon,
        .unsaved = unsaved,
        .draw = draw,
        .focus_id = focusId,
        .destroy = destroy,
    };

    /// The history of the repository at `root`; null when it cannot start.
    pub fn create(gpa: std.mem.Allocator, host: Host, root: []const u8) ?tabs.Document {
        const self = gpa.create(HistoryDocument) catch return null;
        self.init(gpa, host, root) catch {
            gpa.destroy(self);
            return null;
        };
        self.loadMore();
        return .{ .ptr = self, .vtable = &vtable };
    }

    fn init(self: *HistoryDocument, gpa: std.mem.Allocator, host: Host, root: []const u8) !void {
        const r = try gpa.dupeZ(u8, root);
        errdefer gpa.free(r);
        const ident = try identityFor(gpa, root);
        errdefer gpa.free(ident);
        const slash = std.mem.lastIndexOfAny(u8, root, "/\\");
        const name = if (slash) |s| root[s + 1 ..] else root;
        const t = try std.fmt.allocPrint(gpa, "Histórico: {s}", .{name});
        errdefer gpa.free(t);
        const l = try jobs.Log.create(gpa, root, "", false);
        errdefer l.destroy();
        const worker = try worker_mod.Worker.create(gpa, .{ .context = host.context, .post = host.post_redraw });
        self.* = .{ .gpa = gpa, .host = host, .worker = worker, .root = r, .identity_text = ident, .title_text = t, .main = .{ .id = 0, .log = l } };
    }

    /// "history:<repo>": opening it again goes to the pane that shows it.
    pub fn identityFor(gpa: std.mem.Allocator, root: []const u8) ![]u8 {
        return std.fmt.allocPrint(gpa, "history:{s}", .{root});
    }

    /// The HistoryDocument behind `doc`, when it is one (the commands).
    pub fn from(doc: tabs.Document) ?*HistoryDocument {
        return if (doc.vtable == &vtable) @ptrCast(@alignCast(doc.ptr)) else null;
    }

    fn newFeed(self: *HistoryDocument, query: []const u8) ?Feed {
        const l = jobs.Log.create(self.gpa, self.root, query, self.current_only) catch return null;
        defer self.next_feed +%= 1;
        return .{ .id = self.next_feed, .log = l };
    }

    fn retire(self: *HistoryDocument, feed: *Feed) void {
        jobs.Retire.submit(self, feed.log);
        feed.deinit(self.gpa);
    }

    /// The next page of whichever log the list shows.
    pub fn loadMore(self: *HistoryDocument) void {
        const feed = if (self.search) |*s| s else &self.main;
        if (feed.loading or feed.ended) return;
        feed.loading = jobs.NextPage.submit(self, feed.log, feed.id);
    }

    pub fn received(self: *HistoryDocument, id: u32, page: ?*jobs.Page, ended: bool, failed: bool) void {
        const feed = if (self.main.id == id) &self.main else if (self.search != null and self.search.?.id == id) &self.search.? else {
            if (page) |p| p.destroy(self.gpa);
            return;
        };
        feed.loading = false;
        feed.ended = ended;
        feed.failed = failed and feed.commits.items.len == 0;
        const p = page orelse return;
        feed.pages.append(self.gpa, p) catch return p.destroy(self.gpa);
        feed.commits.appendSlice(self.gpa, p.commits) catch {};
        feed.lanes = @max(feed.lanes, p.lanes);
        self.filtered_for = std.math.maxInt(usize);
    }

    /// Reads the log again from the top (a commit, a checkout), keeping the
    /// selected commit when it is still there.
    pub fn reload(self: *HistoryDocument) void {
        var fresh = self.newFeed("") orelse return;
        std.mem.swap(Feed, &self.main, &fresh);
        self.retire(&fresh);
        self.filtered_for = std.math.maxInt(usize);
        self.loadMore();
    }

    /// The repository changed on disk: refs and HEAD live in .git.
    pub fn diskChanged(self: *HistoryDocument, paths: []const []const u8) void {
        for (paths) |p| {
            if (view.isInGitFolder(self.root, p)) {
                self.disk_dirty = true;
                return;
            }
        }
    }

    pub fn setFilter(self: *HistoryDocument, text: []const u8) void {
        if (text.ptr != self.filter.items.ptr) {
            self.filter.clearRetainingCapacity();
            self.filter.appendSlice(self.gpa, text) catch {};
        }
        if (self.search) |*s| self.retire(s);
        self.search = null;
        self.filtered_for = std.math.maxInt(usize);
    }

    /// Enter in the search field: the whole repository, not only what is loaded.
    pub fn searchRepository(self: *HistoryDocument) void {
        if (self.filter.items.len == 0) return self.setFilter("");
        if (self.search) |*s| self.retire(s);
        self.search = self.newFeed(self.filter.items);
        self.loadMore();
    }

    /// history.current-branch
    pub fn toggleCurrentOnly(self: *HistoryDocument) void {
        self.current_only = !self.current_only;
        if (self.search != null) self.searchRepository();
        self.reload();
    }

    /// What the list shows: the search's results, the loaded commits that
    /// match the filter, or all of them.
    pub fn shown(self: *HistoryDocument) Shown {
        if (self.search) |*s| return .{ .commits = s.commits.items };
        if (self.filter.items.len == 0) return .{ .commits = self.main.commits.items };
        if (self.filtered_for != self.main.commits.items.len) {
            self.filtered.clearRetainingCapacity();
            for (self.main.commits.items, 0..) |cm, i| {
                if (cm.matches(self.filter.items)) self.filtered.append(self.gpa, @intCast(i)) catch break;
            }
            self.filtered_for = self.main.commits.items.len;
        }
        return .{ .commits = self.main.commits.items, .only = self.filtered.items };
    }

    pub fn showsGraph(self: *const HistoryDocument) bool {
        return self.search == null and self.filter.items.len == 0;
    }

    pub fn select(self: *HistoryDocument, commit: log.Commit) void {
        if (std.mem.eql(u8, self.selected.items, commit.sha)) return;
        self.selected.clearRetainingCapacity();
        self.selected.appendSlice(self.gpa, commit.sha) catch return;
        self.clearDetails();
        jobs.Details.submit(self, commit.sha, false);
    }

    pub fn hasSelection(self: *const HistoryDocument) bool {
        return self.selected.items.len > 0;
    }

    fn clearDetails(self: *HistoryDocument) void {
        if (self.details) |d| self.gpa.free(d.files);
        self.details = null;
        if (self.details_text) |t| self.gpa.free(t);
        self.details_text = null;
        if (self.remote_url) |u| self.gpa.free(u);
        self.remote_url = null;
    }

    pub fn detailsRead(self: *HistoryDocument, sha: []const u8, text: ?[]u8, url: ?[]u8) void {
        if (!std.mem.eql(u8, sha, self.selected.items)) return;
        self.clearDetails();
        if (url) |u| self.remote_url = self.gpa.dupe(u8, u) catch null;
        const t = self.gpa.dupe(u8, text orelse return) catch return;
        self.details_text = t;
        self.details = log.parseDetails(self.gpa, t) catch null;
    }

    pub fn remoteFound(self: *HistoryDocument, url: ?[]u8) void {
        if (url) |u| view.openUrl(self.gpa, u);
    }

    /// history.copy-sha
    pub fn copySha(self: *HistoryDocument) void {
        if (!self.hasSelection()) return;
        ui.clipboard.writeText(self.gpa, self.hwnd, self.selected.items);
    }

    /// history.open-remote: the address comes with the details; right
    /// after selecting it may still be on its way.
    pub fn openRemote(self: *HistoryDocument) void {
        if (self.remote_url) |u| return view.openUrl(self.gpa, u);
        if (self.hasSelection()) jobs.Details.submit(self, self.selected.items, true);
    }

    /// history.search
    pub fn focusSearch(self: *HistoryDocument) void {
        self.focus_search = true;
    }

    pub fn openDiff(self: *HistoryDocument, file: log.File) void {
        if (!self.hasSelection()) return;
        self.host.open_commit_diff(self.host.context, self.root, self.selected.items, file.path, file.orig);
    }

    fn get(ptr: *anyopaque) *HistoryDocument {
        return @ptrCast(@alignCast(ptr));
    }
    fn title(ptr: *anyopaque) []const u8 {
        return get(ptr).title_text;
    }
    fn identity(ptr: *anyopaque) []const u8 {
        return get(ptr).identity_text;
    }
    fn icon(_: *anyopaque) u21 {
        return icons.phosphor.git_branch;
    }
    fn unsaved(_: *anyopaque) bool {
        return false;
    }
    fn focusId(ptr: *anyopaque) ui.Id {
        return view.listId(get(ptr));
    }
    fn draw(ptr: *anyopaque, u: *ui.Ui, area: gfx.Rect, focused: bool) void {
        const self = get(ptr);
        self.hwnd = u.hwnd;
        _ = self.worker.drain();
        view.draw(self, u, area, focused);
    }
    fn destroy(ptr: *anyopaque) void {
        const self = get(ptr);
        const gpa = self.gpa;
        self.retire(&self.main);
        if (self.search) |*s| self.retire(s);
        self.worker.stop();
        self.clearDetails();
        self.filter.deinit(gpa);
        self.view.search.deinit(gpa);
        self.filtered.deinit(gpa);
        self.selected.deinit(gpa);
        gpa.free(self.root);
        gpa.free(self.identity_text);
        gpa.free(self.title_text);
        gpa.destroy(self);
    }
};

test {
    @import("win32").refAllDeep(@This());
}
