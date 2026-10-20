//! The repository's status as the core lists it (cadex_git_status) and the
//! rows of the Git page: conflicts first, then staged, then the other
//! changes, at most 1000 files per list (docs/spec/source-control.md).
//! Pure: no git, no drawing.

const std = @import("std");
const gfx = @import("gfx");

pub const Kind = enum(u8) { changed = 0, renamed = 1, conflict = 2, untracked = 3 };

pub const Entry = struct {
    kind: Kind,
    /// The index and work-tree letters (M A D R C T U ? .).
    index: u8,
    worktree: u8,
    /// Relative to the repository, with forward slashes (as git writes it).
    path: []const u8,
    /// The old name of a rename, or "".
    orig: []const u8,

    pub fn isStaged(e: Entry) bool {
        return e.kind != .untracked and e.kind != .conflict and e.index != '.';
    }

    pub fn isUnstaged(e: Entry) bool {
        return e.kind == .untracked or (e.kind != .conflict and e.worktree != '.');
    }

    /// The letter shown for a side: ? for new files, U for conflicts.
    pub fn letter(e: Entry, staged: bool) u8 {
        if (e.kind == .untracked) return '?';
        if (e.kind == .conflict) return 'U';
        return if (staged) e.index else e.worktree;
    }
};

pub const Status = struct {
    /// The core's text: every slice below points into it.
    text: []u8,
    branch: []const u8 = "",
    oid: []const u8 = "",
    upstream: []const u8 = "",
    ahead: u32 = 0,
    behind: u32 = 0,
    entries: []Entry = &.{},

    pub fn deinit(self: *Status, gpa: std.mem.Allocator) void {
        gpa.free(self.entries);
        gpa.free(self.text);
    }

    pub fn detached(self: Status) bool {
        return self.branch.len == 0;
    }

    pub fn hasStaged(self: Status) bool {
        for (self.entries) |e| if (e.isStaged()) return true;
        return false;
    }
};

/// Reads the core's listing; takes `text` (gpa-owned) in every case.
pub fn parse(gpa: std.mem.Allocator, text: []u8) !Status {
    var status: Status = .{ .text = text };
    errdefer gpa.free(text);
    var entries: std.ArrayList(Entry) = .empty;
    errdefer entries.deinit(gpa);
    var lines = std.mem.splitScalar(u8, text, '\n');
    var first = true;
    while (lines.next()) |line| {
        var f: [5][]const u8 = undefined;
        const n = fields(line, &f);
        if (first) {
            first = false;
            if (n >= 5) {
                status.branch = f[0];
                status.oid = f[1];
                status.upstream = f[2];
                status.ahead = std.fmt.parseInt(u32, f[3], 10) catch 0;
                status.behind = std.fmt.parseInt(u32, f[4], 10) catch 0;
                continue;
            }
        }
        if (n < 5 or f[1].len == 0 or f[2].len == 0) continue;
        const k = std.fmt.parseInt(u8, f[0], 10) catch continue;
        if (k > 3) continue;
        try entries.append(gpa, .{ .kind = @enumFromInt(k), .index = f[1][0], .worktree = f[2][0], .path = f[3], .orig = f[4] });
    }
    status.entries = try entries.toOwnedSlice(gpa);
    return status;
}

/// Splits a line on tabs into at most `out.len` fields; how many.
fn fields(line: []const u8, out: [][]const u8) usize {
    var it = std.mem.splitScalar(u8, line, '\t');
    var n: usize = 0;
    while (it.next()) |part| {
        if (n == out.len) break;
        out[n] = part;
        n += 1;
    }
    return n;
}

/// A row of the Git page's lists.
pub const Row = union(enum) {
    header: Header,
    /// An index into Status.entries, and which list it is in.
    entry: struct { index: usize, staged: bool },
    /// "Mostrando 1000 de 1534: veja o resto com git status".
    overflow: struct { shown: usize, total: usize },
};

pub const List = enum { conflicts, staged, changes };

pub const Header = struct {
    title: []const u8,
    list: List,
    count: usize,
};

/// Each list shows at most this many files: thousands of rows made the
/// Mac's table slow (docs/spec/source-control.md); the rest is in the terminal.
pub const limit = 1000;

/// The rows for `status`, conflicts first, then staged, then changes.
pub fn rows(gpa: std.mem.Allocator, status: Status) ![]Row {
    var out: std.ArrayList(Row) = .empty;
    errdefer out.deinit(gpa);
    var conflicts: usize = 0;
    var staged: usize = 0;
    var changes: usize = 0;
    for (status.entries) |e| {
        if (e.kind == .conflict) conflicts += 1;
        if (e.isStaged()) staged += 1;
        if (e.isUnstaged()) changes += 1;
    }
    if (conflicts > 0) {
        try out.append(gpa, .{ .header = .{ .title = "Conflitos", .list = .conflicts, .count = conflicts } });
        try addList(gpa, &out, status, .conflicts, conflicts);
    }
    if (staged > 0) {
        try out.append(gpa, .{ .header = .{ .title = "Staged", .list = .staged, .count = staged } });
        try addList(gpa, &out, status, .staged, staged);
    }
    if (changes > 0 or staged == 0) {
        const title = if (changes == 0 and conflicts == 0) "Nenhuma mudança" else "Mudanças";
        try out.append(gpa, .{ .header = .{ .title = title, .list = .changes, .count = changes } });
        try addList(gpa, &out, status, .changes, changes);
    }
    return out.toOwnedSlice(gpa);
}

fn addList(gpa: std.mem.Allocator, out: *std.ArrayList(Row), status: Status, list: List, total: usize) !void {
    var shown: usize = 0;
    for (status.entries, 0..) |e, i| {
        const in = switch (list) {
            .conflicts => e.kind == .conflict,
            .staged => e.isStaged(),
            .changes => e.isUnstaged(),
        };
        if (!in) continue;
        if (shown == limit) break;
        try out.append(gpa, .{ .entry = .{ .index = i, .staged = list == .staged } });
        shown += 1;
    }
    if (total > limit) try out.append(gpa, .{ .overflow = .{ .shown = limit, .total = total } });
}

/// The color of a change's letter, the Mac's system colors in dark mode
/// (SourceControlRow.color); the history's files use the same.
pub fn letterColor(letter: u8) gfx.Color {
    return switch (letter) {
        'A', '?' => gfx.Color.rgb(0x30d158),
        'D', 'U' => gfx.Color.rgb(0xff453a),
        'R', 'C' => gfx.Color.rgb(0x0a84ff),
        else => gfx.Color.rgb(0xff9f0a),
    };
}

/// The file name and its folder ("a/b/c.zig" -> "c.zig", "a/b").
pub fn splitPath(path: []const u8) struct { name: []const u8, folder: []const u8 } {
    const slash = std.mem.lastIndexOfScalar(u8, path, '/') orelse return .{ .name = path, .folder = "" };
    return .{ .name = path[slash + 1 ..], .folder = path[0..slash] };
}

const testing = std.testing;

const sample =
    "main\tabc123\torigin/main\t2\t1\n" ++
    "0\tM\t.\tsrc/a.zig\t\n" ++
    "0\t.\tM\tsrc/b c.zig\t\n" ++
    "1\tR\t.\tnovo.zig\tvelho.zig\n" ++
    "2\tU\tU\tconflito.zig\t\n" ++
    "3\t?\t?\tação.txt\t\n";

test "the core's status reads with renames, spaces, accents and conflicts" {
    var s = try parse(testing.allocator, try testing.allocator.dupe(u8, sample));
    defer s.deinit(testing.allocator);
    try testing.expectEqualStrings("main", s.branch);
    try testing.expectEqualStrings("origin/main", s.upstream);
    try testing.expectEqual(@as(u32, 2), s.ahead);
    try testing.expectEqual(@as(u32, 1), s.behind);
    try testing.expectEqual(@as(usize, 5), s.entries.len);
    try testing.expectEqualStrings("src/b c.zig", s.entries[1].path);
    try testing.expectEqualStrings("velho.zig", s.entries[2].orig);
    try testing.expectEqual(Kind.conflict, s.entries[3].kind);
    try testing.expectEqualStrings("ação.txt", s.entries[4].path);
    try testing.expect(s.entries[0].isStaged() and !s.entries[0].isUnstaged());
    try testing.expect(!s.entries[3].isStaged() and !s.entries[3].isUnstaged());
    try testing.expectEqual(@as(u8, '?'), s.entries[4].letter(false));
    try testing.expect(s.hasStaged());
}

test "rows put conflicts first, then staged, then changes" {
    var s = try parse(testing.allocator, try testing.allocator.dupe(u8, sample));
    defer s.deinit(testing.allocator);
    const r = try rows(testing.allocator, s);
    defer testing.allocator.free(r);
    try testing.expectEqualStrings("Conflitos", r[0].header.title);
    try testing.expectEqual(@as(usize, 3), r[1].entry.index);
    try testing.expectEqualStrings("Staged", r[2].header.title);
    try testing.expectEqual(@as(usize, 2), r[2].header.count);
    try testing.expect(r[3].entry.staged);
    try testing.expectEqualStrings("Mudanças", r[5].header.title);
    try testing.expectEqual(@as(usize, 2), r[5].header.count);
    try testing.expectEqual(@as(usize, 8), r.len);
}

test "a clean repository says so, and a long list stops at the limit" {
    var clean = try parse(testing.allocator, try testing.allocator.dupe(u8, "main\tabc\t\t0\t0\n"));
    defer clean.deinit(testing.allocator);
    const r = try rows(testing.allocator, clean);
    defer testing.allocator.free(r);
    try testing.expectEqual(@as(usize, 1), r.len);
    try testing.expectEqualStrings("Nenhuma mudança", r[0].header.title);

    var text: std.ArrayList(u8) = .empty;
    try text.appendSlice(testing.allocator, "main\tabc\t\t0\t0\n");
    for (0..limit + 5) |i| try text.print(testing.allocator, "3\t?\t?\tf{d}\t\n", .{i});
    var big = try parse(testing.allocator, try text.toOwnedSlice(testing.allocator));
    defer big.deinit(testing.allocator);
    const many = try rows(testing.allocator, big);
    defer testing.allocator.free(many);
    try testing.expectEqual(@as(usize, limit + 2), many.len);
    try testing.expectEqual(@as(usize, limit + 5), many[many.len - 1].overflow.total);
}

test "a path splits into name and folder" {
    try testing.expectEqualStrings("c.zig", splitPath("a/b/c.zig").name);
    try testing.expectEqualStrings("a/b", splitPath("a/b/c.zig").folder);
    try testing.expectEqualStrings("", splitPath("c.zig").folder);
}

test {
    @import("win32").refAllDeep(@This());
}
