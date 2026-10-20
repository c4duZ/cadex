//! What a log brought (the full history or a search) and the rows the
//! list shows from it.

const std = @import("std");
const jobs = @import("jobs.zig");
const log = @import("log.zig");

/// One log and what it brought: the full history, or a search.
pub const Feed = struct {
    id: u32,
    log: *jobs.Log,
    pages: std.ArrayList(*jobs.Page) = .empty,
    commits: std.ArrayList(log.Commit) = .empty,
    lanes: usize = 1,
    loading: bool = false,
    ended: bool = false,
    failed: bool = false,

    pub fn deinit(self: *Feed, gpa: std.mem.Allocator) void {
        for (self.pages.items) |p| p.destroy(gpa);
        self.pages.deinit(gpa);
        self.commits.deinit(gpa);
    }
};

/// The rows of the list: `commits`, or only the indices in `only`.
pub const Shown = struct {
    commits: []const log.Commit,
    only: ?[]const u32 = null,

    pub fn len(self: Shown) usize {
        return if (self.only) |o| o.len else self.commits.len;
    }

    pub fn at(self: Shown, i: usize) *const log.Commit {
        return &self.commits[if (self.only) |o| o[i] else i];
    }
};

test {
    @import("win32").refAllDeep(@This());
}
