//! The repository's state from `git status --porcelain=v2 -z --branch`
//! (docs/spec/source-control.md): branch, upstream, ahead/behind, and each
//! changed path with its index and work-tree letters. NUL-separated, so
//! names with spaces, accents, quotes or newlines arrive intact.

const std = @import("std");
const workspace = @import("../workspace/workspace.zig");
const git = @import("git.zig");

pub const Kind = enum(u8) { changed = 0, renamed = 1, conflict = 2, untracked = 3 };

pub const Entry = struct {
    kind: Kind,
    /// Letters of the index (staged) and work tree: M A D R C T U, or '.'.
    index: u8,
    worktree: u8,
    path: []const u8,
    /// Renames and copies: the old name.
    orig: []const u8 = "",
};

pub const Status = struct {
    arena: std.heap.ArenaAllocator,
    /// Empty when detached.
    branch: []const u8 = "",
    /// The commit HEAD points at; "(initial)" before the first commit.
    oid: []const u8 = "",
    upstream: []const u8 = "",
    ahead: u32 = 0,
    behind: u32 = 0,
    entries: []Entry = &.{},

    pub fn deinit(self: *Status) void {
        self.arena.deinit();
    }
};

pub fn read(gpa: std.mem.Allocator, registry: *workspace.Registry, repo: []const u8) !Status {
    var r = try git.run(gpa, registry, repo, &.{ "status", "--porcelain=v2", "-z", "--branch", "--untracked-files=normal" }, .{});
    defer r.deinit(gpa);
    if (!r.ok()) return error.GitFailed;
    return parse(gpa, r.stdout);
}

pub fn parse(gpa: std.mem.Allocator, text: []const u8) !Status {
    var self: Status = .{ .arena = .init(gpa) };
    errdefer self.arena.deinit();
    const a = self.arena.allocator();
    var entries: std.ArrayList(Entry) = .empty;
    var records = std.mem.splitScalar(u8, text, 0);
    while (records.next()) |rec| {
        if (rec.len < 2) continue;
        switch (rec[0]) {
            '#' => header(&self, a, rec),
            '1' => {
                // 1 XY sub mH mI mW hH hI path
                const f = fields(rec, 8) orelse continue;
                try entries.append(a, .{ .kind = .changed, .index = f.xy[0], .worktree = f.xy[1], .path = try a.dupe(u8, f.rest) });
            },
            '2' => {
                // 2 XY sub mH mI mW hH hI Xscore path NUL origPath
                const f = fields(rec, 9) orelse continue;
                const orig = records.next() orelse "";
                try entries.append(a, .{ .kind = .renamed, .index = f.xy[0], .worktree = f.xy[1], .path = try a.dupe(u8, f.rest), .orig = try a.dupe(u8, orig) });
            },
            'u' => {
                // u XY sub m1 m2 m3 mW h1 h2 h3 path
                const f = fields(rec, 10) orelse continue;
                try entries.append(a, .{ .kind = .conflict, .index = f.xy[0], .worktree = f.xy[1], .path = try a.dupe(u8, f.rest) });
            },
            '?' => try entries.append(a, .{ .kind = .untracked, .index = '?', .worktree = '?', .path = try a.dupe(u8, rec[2..]) }),
            else => {},
        }
    }
    self.entries = entries.items;
    return self;
}

/// The XY letters and what is left after `count` space-separated fields
/// (the path, which may itself have spaces).
fn fields(rec: []const u8, count: usize) ?struct { xy: []const u8, rest: []const u8 } {
    var at: usize = 0;
    var xy: []const u8 = "";
    for (0..count) |i| {
        const space = std.mem.indexOfScalarPos(u8, rec, at, ' ') orelse return null;
        if (i == 1) xy = rec[at..space];
        at = space + 1;
    }
    if (xy.len != 2) return null;
    return .{ .xy = xy, .rest = rec[at..] };
}

fn header(self: *Status, a: std.mem.Allocator, rec: []const u8) void {
    const dup = struct {
        fn f(alloc: std.mem.Allocator, s: []const u8) []const u8 {
            return alloc.dupe(u8, s) catch "";
        }
    }.f;
    if (std.mem.startsWith(u8, rec, "# branch.oid ")) self.oid = dup(a, rec[13..]);
    if (std.mem.startsWith(u8, rec, "# branch.head ")) {
        const head = rec[14..];
        self.branch = if (std.mem.eql(u8, head, "(detached)")) "" else dup(a, head);
    }
    if (std.mem.startsWith(u8, rec, "# branch.upstream ")) self.upstream = dup(a, rec[18..]);
    if (std.mem.startsWith(u8, rec, "# branch.ab ")) {
        var it = std.mem.tokenizeScalar(u8, rec[12..], ' ');
        if (it.next()) |plus| self.ahead = std.fmt.parseInt(u32, std.mem.trimStart(u8, plus, "+"), 10) catch 0;
        if (it.next()) |minus| self.behind = std.fmt.parseInt(u32, std.mem.trimStart(u8, minus, "-"), 10) catch 0;
    }
}

const testing = std.testing;

test "porcelain v2 with renames, spaces, accents and conflicts" {
    const text = "# branch.oid 1234abcd\x00# branch.head main\x00# branch.upstream origin/main\x00# branch.ab +2 -1\x00" ++
        "1 .M N... 100644 100644 100644 aaa bbb src/nome com espaço.zig\x00" ++
        "1 A. N... 000000 100644 100644 000 ccc ação.md\x00" ++
        "2 R. N... 100644 100644 100644 ddd eee R100 novo nome.txt\x00velho nome.txt\x00" ++
        "u UU N... 100644 100644 100644 100644 f1 f2 f3 conflito.c\x00" ++
        "? \"aspas\".txt\x00";
    var s = try parse(testing.allocator, text);
    defer s.deinit();
    try testing.expectEqualStrings("main", s.branch);
    try testing.expectEqualStrings("origin/main", s.upstream);
    try testing.expectEqual(@as(u32, 2), s.ahead);
    try testing.expectEqual(@as(u32, 1), s.behind);
    try testing.expectEqual(@as(usize, 5), s.entries.len);
    try testing.expectEqualStrings("src/nome com espaço.zig", s.entries[0].path);
    try testing.expectEqual(@as(u8, 'M'), s.entries[0].worktree);
    try testing.expectEqual(@as(u8, 'A'), s.entries[1].index);
    try testing.expectEqualStrings("ação.md", s.entries[1].path);
    try testing.expectEqual(Kind.renamed, s.entries[2].kind);
    try testing.expectEqualStrings("novo nome.txt", s.entries[2].path);
    try testing.expectEqualStrings("velho nome.txt", s.entries[2].orig);
    try testing.expectEqual(Kind.conflict, s.entries[3].kind);
    try testing.expectEqual(Kind.untracked, s.entries[4].kind);
    try testing.expectEqualStrings("\"aspas\".txt", s.entries[4].path);
}

test "detached HEAD and a fresh repository" {
    var s = try parse(testing.allocator, "# branch.oid (initial)\x00# branch.head (detached)\x00");
    defer s.deinit();
    try testing.expectEqualStrings("", s.branch);
    try testing.expectEqualStrings("(initial)", s.oid);
}
