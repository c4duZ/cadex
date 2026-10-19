//! The commit log in pages (docs/spec/git-history.md). A `Log` remembers
//! where the last page ended and the graph's lanes, so the next page
//! continues the lines. With a query it filters by subject, author or sha
//! instead, and has no graph (the filtered commits are not connected).

const std = @import("std");
const sc = @import("../source-control/source_control.zig");
const workspace = @import("../workspace/workspace.zig");
const graph = @import("graph.zig");

pub const page_size = 500;

/// One commit as git prints it with `format`; fields point into git's output.
pub const Commit = struct {
    sha: []const u8,
    parents: []const u8,
    author: []const u8,
    email: []const u8,
    time: []const u8,
    refs: []const u8,
    subject: []const u8,
};

/// Fields split by 0x1f, commits ended by 0x1e: neither appears in names
/// or subjects.
const format = "--format=%H%x1f%P%x1f%an%x1f%ae%x1f%at%x1f%D%x1f%s%x1e";

pub fn parse(record: []const u8) ?Commit {
    var fields = std.mem.splitScalar(u8, std.mem.trimStart(u8, record, "\n"), 0x1f);
    var c: Commit = undefined;
    inline for (.{ "sha", "parents", "author", "email", "time", "refs", "subject" }) |name| {
        @field(c, name) = fields.next() orelse return null;
    }
    if (c.sha.len == 0) return null;
    return c;
}

pub const Log = struct {
    gpa: std.mem.Allocator,
    registry: *workspace.Registry,
    repo: []u8,
    query: []u8,
    /// Only what HEAD reaches, instead of every branch, tag and remote.
    current_only: bool,
    skip: usize = 0,
    lanes: graph.Graph,

    pub fn init(gpa: std.mem.Allocator, registry: *workspace.Registry, repo: []const u8, query: []const u8, current_only: bool) !Log {
        const r = try gpa.dupe(u8, repo);
        errdefer gpa.free(r);
        return .{
            .gpa = gpa,
            .registry = registry,
            .repo = r,
            .query = try gpa.dupe(u8, query),
            .current_only = current_only,
            .lanes = graph.Graph.init(gpa),
        };
    }

    pub fn deinit(self: *Log) void {
        self.gpa.free(self.repo);
        self.gpa.free(self.query);
        self.lanes.deinit();
    }

    /// The next `count` commits, one line each:
    /// sha \t parents \t author \t email \t time \t refs \t subject \t column \t color \t top \t bottom
    /// (segments "from,to,color" separated by spaces; column -1 without a
    /// graph). Empty when the log ended. Caller frees.
    pub fn next(self: *Log, count: usize) ![]u8 {
        var r = try self.run(count);
        defer r.deinit(self.gpa);
        if (!r.ok()) {
            // A repository without commits yet: an empty log, not an error.
            if (std.mem.indexOf(u8, r.stderr, "does not have any commits") != null or
                std.mem.indexOf(u8, r.stderr, "unknown revision") != null) return self.gpa.alloc(u8, 0);
            return error.GitFailed;
        }
        var arena = std.heap.ArenaAllocator.init(self.gpa);
        defer arena.deinit();
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(self.gpa);
        var records = std.mem.splitScalar(u8, r.stdout, 0x1e);
        var matched: usize = 0;
        var written: usize = 0;
        while (records.next()) |record| {
            const c = parse(record) orelse continue;
            if (self.query.len > 0) {
                if (!matches(c, self.query)) continue;
                matched += 1;
                if (matched <= self.skip) continue;
                if (written == count) break;
                try line(&out, self.gpa, c, null);
            } else {
                var parents: std.ArrayList([]const u8) = .empty;
                var it = std.mem.tokenizeScalar(u8, c.parents, ' ');
                while (it.next()) |p| try parents.append(arena.allocator(), p);
                const row = try self.lanes.add(arena.allocator(), c.sha, parents.items);
                try line(&out, self.gpa, c, row);
            }
            written += 1;
        }
        self.skip += written;
        return out.toOwnedSlice(self.gpa);
    }

    fn run(self: *Log, count: usize) !sc.git.Result {
        var args: std.ArrayList([]const u8) = .empty;
        defer args.deinit(self.gpa);
        // Children before parents, newest first; the stash is not history.
        try args.appendSlice(self.gpa, &.{ "log", "--date-order", "--no-color", format });
        if (self.current_only) try args.append(self.gpa, "HEAD") else try args.appendSlice(self.gpa, &.{ "--branches", "--tags", "--remotes", "HEAD" });
        var skip_buf: [32]u8 = undefined;
        var count_buf: [32]u8 = undefined;
        if (self.query.len == 0) {
            try args.append(self.gpa, try std.fmt.bufPrint(&skip_buf, "--skip={d}", .{self.skip}));
            try args.append(self.gpa, try std.fmt.bufPrint(&count_buf, "-n{d}", .{count}));
        }
        try args.append(self.gpa, "--");
        // The search reads the whole log: about 200 bytes a commit.
        const max: usize = if (self.query.len > 0) 128 * 1024 * 1024 else 16 * 1024 * 1024;
        return sc.git.run(self.gpa, self.registry, self.repo, args.items, .{ .max_output = max });
    }
};

/// Subject, author or the start of the sha, ignoring case (ASCII only:
/// "OLÁ" does not find "olá").
pub fn matches(c: Commit, query: []const u8) bool {
    return std.ascii.indexOfIgnoreCase(c.subject, query) != null or
        std.ascii.indexOfIgnoreCase(c.author, query) != null or
        std.ascii.startsWithIgnoreCase(c.sha, query);
}

fn line(out: *std.ArrayList(u8), gpa: std.mem.Allocator, c: Commit, row: ?graph.Row) !void {
    try out.print(gpa, "{s}\t{s}\t{s}\t{s}\t{s}\t{s}\t", .{ c.sha, c.parents, clean(c.author), clean(c.email), c.time, c.refs });
    try out.appendSlice(gpa, clean(c.subject));
    const r = row orelse return out.appendSlice(gpa, "\t-1\t0\t\t\n");
    try out.print(gpa, "\t{d}\t{d}\t", .{ r.column, r.color });
    try segments(out, gpa, r.top);
    try out.append(gpa, '\t');
    try segments(out, gpa, r.bottom);
    try out.append(gpa, '\n');
}

fn segments(out: *std.ArrayList(u8), gpa: std.mem.Allocator, list: []const graph.Segment) !void {
    for (list, 0..) |s, i| {
        if (i > 0) try out.append(gpa, ' ');
        try out.print(gpa, "{d},{d},{d}", .{ s.from, s.to, s.color });
    }
}

/// A tab in a name or subject would shift the fields; git keeps them rare.
fn clean(text: []const u8) []const u8 {
    return if (std.mem.indexOfScalar(u8, text, '\t')) |i| text[0..i] else text;
}

test "a record splits into its fields" {
    const c = parse("\nabc\x1fp1 p2\x1fAna\x1fa@x\x1f1700000000\x1fHEAD -> main, tag: v1\x1folá 🎉").?;
    try std.testing.expectEqualStrings("abc", c.sha);
    try std.testing.expectEqualStrings("p1 p2", c.parents);
    try std.testing.expectEqualStrings("HEAD -> main, tag: v1", c.refs);
    try std.testing.expectEqualStrings("olá 🎉", c.subject);
    try std.testing.expect(matches(c, "OL") and matches(c, "ANA"));
    try std.testing.expect(matches(c, "AB") and !matches(c, "bc"));
    try std.testing.expect(parse("\n") == null);
}
