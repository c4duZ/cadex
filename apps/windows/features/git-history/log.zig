//! The history's model, read from the core's text (the Mac's HistoryLog.swift):
//! a commit with its row of the graph (cadex_history_next), and a commit's
//! message and files (cadex_history_details). Pure: no git, no drawing.

const std = @import("std");

pub const Segment = struct { from: u16, to: u16, color: u16 };

/// One row of the graph: the commit's lane and color, the lines from the
/// row's top to its middle and from the middle to its bottom.
pub const Graph = struct {
    column: u16,
    color: u16,
    top: []const Segment,
    bottom: []const Segment,

    /// How many lanes the row touches.
    pub fn width(self: Graph) usize {
        var widest: usize = self.column;
        for (self.top) |s| widest = @max(widest, @max(s.from, s.to));
        for (self.bottom) |s| widest = @max(widest, @max(s.from, s.to));
        return widest + 1;
    }
};

pub const Commit = struct {
    sha: []const u8,
    /// Space-separated shas.
    parents: []const u8,
    author: []const u8,
    email: []const u8,
    time: i64,
    /// "HEAD -> main, origin/main, tag: v1".
    refs: []const u8,
    subject: []const u8,
    graph: ?Graph,

    pub fn shortSha(self: Commit) []const u8 {
        return self.sha[0..@min(self.sha.len, 7)];
    }

    pub fn isMerge(self: Commit) bool {
        return std.mem.indexOfScalar(u8, std.mem.trim(u8, self.parents, " "), ' ') != null;
    }

    pub fn isHead(self: Commit) bool {
        var it = refs(self.refs);
        while (it.next()) |r| if (std.mem.eql(u8, r, "HEAD") or std.mem.startsWith(u8, r, "HEAD -> ")) return true;
        return false;
    }

    /// The loaded-commits filter: subject or author (any case) or the sha's start.
    pub fn matches(self: Commit, filter: []const u8) bool {
        if (filter.len == 0) return true;
        if (std.ascii.indexOfIgnoreCase(self.subject, filter) != null) return true;
        if (std.ascii.indexOfIgnoreCase(self.author, filter) != null) return true;
        return filter.len <= self.sha.len and std.ascii.eqlIgnoreCase(self.sha[0..filter.len], filter);
    }
};

/// The refs of a commit, one by one.
pub fn refs(text: []const u8) std.mem.SplitIterator(u8, .sequence) {
    return std.mem.splitSequence(u8, if (text.len == 0) "" else text, ", ");
}

/// A page of the log; every slice points into `text` or `arena`.
pub fn parsePage(arena: std.mem.Allocator, text: []const u8) ![]Commit {
    var out: std.ArrayList(Commit) = .empty;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (try parseCommit(arena, line)) |c| try out.append(arena, c);
    }
    return out.toOwnedSlice(arena);
}

pub fn parseCommit(arena: std.mem.Allocator, line: []const u8) !?Commit {
    var f: [11][]const u8 = undefined;
    var it = std.mem.splitScalar(u8, line, '\t');
    var n: usize = 0;
    while (it.next()) |part| : (n += 1) {
        if (n == f.len) break;
        f[n] = part;
    }
    if (n < 11 or f[0].len == 0) return null;
    const column = std.fmt.parseInt(i32, f[7], 10) catch -1;
    const graph: ?Graph = if (column < 0) null else .{
        .column = @intCast(column),
        .color = std.fmt.parseInt(u16, f[8], 10) catch 0,
        .top = try segments(arena, f[9]),
        .bottom = try segments(arena, f[10]),
    };
    return .{
        .sha = f[0],
        .parents = f[1],
        .author = f[2],
        .email = f[3],
        .time = std.fmt.parseInt(i64, f[4], 10) catch 0,
        .refs = f[5],
        .subject = f[6],
        .graph = graph,
    };
}

/// "from,to,color" separated by spaces.
fn segments(arena: std.mem.Allocator, text: []const u8) ![]const Segment {
    var out: std.ArrayList(Segment) = .empty;
    var parts = std.mem.tokenizeScalar(u8, text, ' ');
    while (parts.next()) |part| {
        var nums: [3]u16 = undefined;
        var k: usize = 0;
        var it = std.mem.splitScalar(u8, part, ',');
        while (it.next()) |num| : (k += 1) {
            if (k == 3) break;
            nums[k] = std.fmt.parseInt(u16, num, 10) catch break;
        }
        if (k == 3) try out.append(arena, .{ .from = nums[0], .to = nums[1], .color = nums[2] });
    }
    return out.toOwnedSlice(arena);
}

pub const File = struct {
    letter: u8,
    /// null for a binary file.
    added: ?u32,
    removed: ?u32,
    path: []const u8,
    orig: []const u8,
};

pub const Details = struct {
    parents: []const u8,
    message: []const u8,
    files: []File,
};

/// "parents \x1e message \x1e" then per file "letter \t added \t removed \t path \t old path".
pub fn parseDetails(gpa: std.mem.Allocator, text: []const u8) !Details {
    var parts = std.mem.splitScalar(u8, text, 0x1e);
    const parents = parts.next() orelse "";
    const message = std.mem.trim(u8, parts.next() orelse "", "\r\n");
    const rest = parts.rest();
    var files: std.ArrayList(File) = .empty;
    errdefer files.deinit(gpa);
    var lines = std.mem.splitScalar(u8, rest, '\n');
    while (lines.next()) |line| {
        var f: [5][]const u8 = undefined;
        var it = std.mem.splitScalar(u8, line, '\t');
        var n: usize = 0;
        while (it.next()) |part| : (n += 1) {
            if (n == f.len) break;
            f[n] = part;
        }
        if (n < 5 or f[0].len == 0) continue;
        try files.append(gpa, .{
            .letter = f[0][0],
            .added = std.fmt.parseInt(u32, f[1], 10) catch null,
            .removed = std.fmt.parseInt(u32, f[2], 10) catch null,
            .path = f[3],
            .orig = f[4],
        });
    }
    return .{ .parents = parents, .message = message, .files = try files.toOwnedSlice(gpa) };
}

const testing = std.testing;

test "a log line reads with its graph row" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const text = "abc1234567\tp1 p2\tAna\tana@x.com\t1700000000\tHEAD -> main, tag: v1\tMerge ação\t1\t2\t0,1,2 1,1,2\t1,0,2\n" ++
        "def\t\tBia\tb@x\t1600000000\t\tRoot\t-1\t0\t\t\n";
    const commits = try parsePage(arena.allocator(), text);
    try testing.expectEqual(@as(usize, 2), commits.len);
    const m = commits[0];
    try testing.expectEqualStrings("abc1234", m.shortSha());
    try testing.expect(m.isMerge() and m.isHead());
    try testing.expectEqualStrings("Merge ação", m.subject);
    try testing.expectEqual(@as(usize, 2), m.graph.?.top.len);
    try testing.expectEqual(@as(u16, 1), m.graph.?.bottom[0].from);
    try testing.expectEqual(@as(usize, 2), m.graph.?.width());
    try testing.expect(commits[1].graph == null and !commits[1].isMerge());
    try testing.expect(m.matches("MERGE") and m.matches("ana"));
    try testing.expect(m.matches("ABC1"));
    try testing.expect(!m.matches("zzz"));
}

test "details give the message and the files with +/-" {
    const text = "p1 p2\x1eTítulo\n\ncorpo\n\x1eM\t3\t1\tsrc/a.zig\t\nR\t0\t0\tnovo.zig\tvelho.zig\nA\t-\t-\timg.png\t\n";
    const d = try parseDetails(testing.allocator, text);
    defer testing.allocator.free(d.files);
    try testing.expectEqualStrings("p1 p2", d.parents);
    try testing.expectEqualStrings("Título\n\ncorpo", d.message);
    try testing.expectEqual(@as(usize, 3), d.files.len);
    try testing.expectEqual(@as(?u32, 3), d.files[0].added);
    try testing.expectEqualStrings("velho.zig", d.files[1].orig);
    try testing.expectEqual(@as(?u32, null), d.files[2].added);
}

test {
    @import("win32").refAllDeep(@This());
}
