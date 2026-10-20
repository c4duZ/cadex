//! The history's git work, as worker jobs (worker.zig): the next page of a
//! log, closing a log, a commit's details and remote address. The core's
//! log handle lives in a Log that only jobs touch, on the worker.

const std = @import("std");
const cadex = @import("cadex");
const worker_mod = @import("worker.zig");
const log = @import("log.zig");
const HistoryDocument = @import("document.zig").HistoryDocument;

const Job = worker_mod.Job;

/// Pages of 500, as the Mac's (docs/spec/git-history.md).
pub const page_size = 500;

/// A log of the core (cadex_history_open), on the worker only.
pub const Log = struct {
    gpa: std.mem.Allocator,
    handle: ?*cadex.cadex_history = null,
    repo: [:0]u8,
    query: [:0]u8,
    current_only: bool,

    pub fn create(gpa: std.mem.Allocator, repo: []const u8, query: []const u8, current_only: bool) !*Log {
        const self = try gpa.create(Log);
        errdefer gpa.destroy(self);
        const r = try gpa.dupeZ(u8, repo);
        errdefer gpa.free(r);
        self.* = .{ .gpa = gpa, .repo = r, .query = try gpa.dupeZ(u8, query), .current_only = current_only };
        return self;
    }

    pub fn destroy(self: *Log) void {
        cadex.cadex_history_close(self.handle);
        self.gpa.free(self.repo);
        self.gpa.free(self.query);
        self.gpa.destroy(self);
    }
};

/// A page of commits; every slice points into its arena.
pub const Page = struct {
    arena: std.heap.ArenaAllocator,
    commits: []log.Commit = &.{},
    /// The widest row of the graph in the page.
    lanes: usize = 0,

    pub fn destroy(self: *Page, gpa: std.mem.Allocator) void {
        self.arena.deinit();
        gpa.destroy(self);
    }
};

/// The core's text, copied into `arena`; null when the call failed.
fn take(arena: std.mem.Allocator, code: cadex.cadex_status, out: [*c]u8, len: usize) ?[]u8 {
    defer cadex.cadex_free(out);
    if (code != cadex.CADEX_OK) return null;
    if (out == null) return arena.alloc(u8, 0) catch null;
    return arena.dupe(u8, out[0..len]) catch null;
}

pub const NextPage = struct {
    job: Job = .{ .work = work, .finish = finish },
    gpa: std.mem.Allocator,
    owner: *HistoryDocument,
    log: *Log,
    feed: u32,
    page: ?*Page = null,
    ended: bool = false,
    failed: bool = false,

    pub fn submit(owner: *HistoryDocument, target: *Log, feed: u32) bool {
        const self = owner.gpa.create(NextPage) catch return false;
        self.* = .{ .gpa = owner.gpa, .owner = owner, .log = target, .feed = feed };
        owner.worker.submit(&self.job);
        return true;
    }

    fn work(job: *Job) void {
        const self: *NextPage = @fieldParentPtr("job", job);
        const l = self.log;
        if (l.handle == null and cadex.cadex_history_open(l.repo.ptr, l.query.ptr, l.current_only, &l.handle) != cadex.CADEX_OK) {
            self.failed = true;
            self.ended = true;
            return;
        }
        const page = self.gpa.create(Page) catch return self.fail();
        page.* = .{ .arena = .init(self.gpa) };
        self.page = page;
        const a = page.arena.allocator();
        var out: [*c]u8 = null;
        var len: usize = 0;
        const text = take(a, cadex.cadex_history_next(l.handle, page_size, &out, &len), out, len) orelse return self.fail();
        page.commits = log.parsePage(a, text) catch return self.fail();
        for (page.commits) |cm| if (cm.graph) |g| {
            page.lanes = @max(page.lanes, g.width());
        };
        if (page.commits.len < page_size) self.ended = true;
    }

    fn fail(self: *NextPage) void {
        self.failed = true;
        self.ended = true;
    }

    fn finish(job: *Job, cancelled: bool) void {
        const self: *NextPage = @fieldParentPtr("job", job);
        if (!cancelled) {
            self.owner.received(self.feed, self.page, self.ended, self.failed);
        } else if (self.page) |p| p.destroy(self.gpa);
        self.gpa.destroy(self);
    }
};

/// Closes a log after the pages asked before it (the worker keeps order).
pub const Retire = struct {
    job: Job = .{ .work = work, .finish = finish },
    gpa: std.mem.Allocator,
    log: ?*Log,

    pub fn submit(owner: *HistoryDocument, target: *Log) void {
        const self = owner.gpa.create(Retire) catch return;
        self.* = .{ .gpa = owner.gpa, .log = target };
        owner.worker.submit(&self.job);
    }

    fn work(job: *Job) void {
        const self: *Retire = @fieldParentPtr("job", job);
        if (self.log) |l| l.destroy();
        self.log = null;
    }

    /// Cancelled before it ran: the worker is stopping and runs no more
    /// pages, so closing here is safe.
    fn finish(job: *Job, _: bool) void {
        const self: *Retire = @fieldParentPtr("job", job);
        if (self.log) |l| l.destroy();
        self.gpa.destroy(self);
    }
};

/// A commit's message, files and web address on origin.
pub const Details = struct {
    job: Job = .{ .work = work, .finish = finish },
    gpa: std.mem.Allocator,
    owner: *HistoryDocument,
    arena: std.heap.ArenaAllocator,
    repo: [:0]const u8 = "",
    sha: [:0]const u8 = "",
    text: ?[]u8 = null,
    url: ?[]u8 = null,
    /// Only the address, to open it (history.open-remote before the details came).
    open_url: bool = false,

    pub fn submit(owner: *HistoryDocument, sha: []const u8, open_url: bool) void {
        const self = owner.gpa.create(Details) catch return;
        self.* = .{ .gpa = owner.gpa, .owner = owner, .arena = .init(owner.gpa), .open_url = open_url };
        const a = self.arena.allocator();
        self.repo = a.dupeZ(u8, owner.root) catch return self.destroy();
        self.sha = a.dupeZ(u8, sha) catch return self.destroy();
        owner.worker.submit(&self.job);
    }

    fn destroy(self: *Details) void {
        self.arena.deinit();
        self.gpa.destroy(self);
    }

    fn work(job: *Job) void {
        const self: *Details = @fieldParentPtr("job", job);
        const a = self.arena.allocator();
        var out: [*c]u8 = null;
        var len: usize = 0;
        if (!self.open_url) self.text = take(a, cadex.cadex_history_details(self.repo.ptr, self.sha.ptr, &out, &len), out, len);
        out = null;
        len = 0;
        self.url = take(a, cadex.cadex_history_remote_url(self.repo.ptr, self.sha.ptr, &out, &len), out, len);
    }

    fn finish(job: *Job, cancelled: bool) void {
        const self: *Details = @fieldParentPtr("job", job);
        if (!cancelled) {
            if (self.open_url) self.owner.remoteFound(self.url) else self.owner.detailsRead(self.sha, self.text, self.url);
        }
        self.destroy();
    }
};

test {
    @import("win32").refAllDeep(@This());
}
