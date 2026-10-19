//! What .gitignore, .ignore and .git/info/exclude leave out of a workspace
//! (docs/spec/search.md). Each folder's files are read once per Matcher and
//! kept; deeper files override shallower ones, and inside a file the last
//! matching line wins, as in git. A path inside an ignored folder is ignored
//! even if a later `!` names it, also as in git. Used by the explorer (to
//! dim) and the search (to skip).

const std = @import("std");
const c = std.c;
const glob = @import("glob.zig");

/// Ignore files bigger than this are skipped (a generated file, not rules).
const max_rules_file = 1024 * 1024;

const Pattern = struct {
    glob: []const u8,
    negated: bool,
    dir_only: bool,
    /// Has a slash: matched against the path from the file's folder.
    /// Otherwise against the last component, at any depth.
    anchored: bool,
};

/// The rules of one folder (its .gitignore and .ignore, in that order).
const Rules = struct {
    patterns: []Pattern,
};

pub const Matcher = struct {
    arena: std.heap.ArenaAllocator,
    root: []const u8,
    /// Folder relative to the root ("" for the root) -> its rules.
    folders: std.StringHashMapUnmanaged(Rules) = .empty,

    /// `root` is a canonical folder; it is copied.
    pub fn init(gpa: std.mem.Allocator, root: []const u8) !Matcher {
        var self: Matcher = .{ .arena = .init(gpa), .root = undefined };
        self.root = try self.arena.allocator().dupe(u8, std.mem.trimEnd(u8, root, "/"));
        return self;
    }

    pub fn deinit(self: *Matcher) void {
        self.arena.deinit();
    }

    /// Whether `rel` (relative to the root) or one of its folders is
    /// ignored. For callers that did not walk down from the root.
    pub fn isIgnored(self: *Matcher, rel: []const u8, is_dir: bool) bool {
        var i: usize = 0;
        while (std.mem.indexOfScalarPos(u8, rel, i, '/')) |slash| : (i = slash + 1) {
            if (self.decide(rel[0..slash], true)) return true;
        }
        return self.decide(rel, is_dir);
    }

    /// Whether `rel` itself is ignored, its folders taken as not ignored:
    /// for a walk that already skipped ignored folders.
    pub fn decide(self: *Matcher, rel: []const u8, is_dir: bool) bool {
        // From the path's own folder up to the root: the deepest file with a
        // matching line decides.
        var folder: []const u8 = std.fs.path.dirname(rel) orelse "";
        while (true) {
            const below = if (folder.len == 0) rel else rel[folder.len + 1 ..];
            if (self.rulesOf(folder)) |rules| {
                if (lastMatch(rules, below, is_dir)) |negated| return !negated;
            }
            if (folder.len == 0) return false;
            folder = std.fs.path.dirname(folder) orelse "";
        }
    }

    fn rulesOf(self: *Matcher, folder: []const u8) ?Rules {
        if (self.folders.get(folder)) |rules| return rules;
        const rules = self.load(folder) catch Rules{ .patterns = &.{} };
        const a = self.arena.allocator();
        const key = a.dupe(u8, folder) catch return rules;
        self.folders.put(a, key, rules) catch {};
        return rules;
    }

    fn load(self: *Matcher, folder: []const u8) !Rules {
        const a = self.arena.allocator();
        var patterns: std.ArrayList(Pattern) = .empty;
        const names: []const []const u8 = if (folder.len == 0)
            &.{ ".git/info/exclude", ".gitignore", ".ignore" }
        else
            &.{ ".gitignore", ".ignore" };
        for (names) |name| {
            const text = readSmall(a, self.root, folder, name) orelse continue;
            try parse(a, text, &patterns);
        }
        return .{ .patterns = patterns.items };
    }
};

/// The last pattern matching `path` (relative to the rules' folder): its
/// negation flag, or null if none matches.
fn lastMatch(rules: Rules, path: []const u8, is_dir: bool) ?bool {
    var i = rules.patterns.len;
    while (i > 0) {
        i -= 1;
        const p = rules.patterns[i];
        if (p.dir_only and !is_dir) continue;
        const subject = if (p.anchored) path else std.fs.path.basename(path);
        if (glob.match(p.glob, subject)) return p.negated;
    }
    return null;
}

/// One rules file into patterns. Blank lines and comments are skipped.
fn parse(a: std.mem.Allocator, text: []const u8, out: *std.ArrayList(Pattern)) !void {
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw| {
        var line = std.mem.trimEnd(u8, raw, "\r");
        line = trimTrailingSpaces(line);
        if (line.len == 0 or line[0] == '#') continue;
        var negated = false;
        if (line[0] == '!') {
            negated = true;
            line = line[1..];
        } else if (std.mem.startsWith(u8, line, "\\!") or std.mem.startsWith(u8, line, "\\#")) {
            line = line[1..];
        }
        const dir_only = std.mem.endsWith(u8, line, "/");
        if (dir_only) line = std.mem.trimEnd(u8, line, "/");
        const anchored = std.mem.indexOfScalar(u8, line, '/') != null;
        line = std.mem.trimStart(u8, line, "/");
        if (line.len == 0) continue;
        try out.append(a, .{ .glob = line, .negated = negated, .dir_only = dir_only, .anchored = anchored });
    }
}

/// Trailing spaces are dropped unless escaped with a backslash.
fn trimTrailingSpaces(line: []const u8) []const u8 {
    var end = line.len;
    while (end > 0 and line[end - 1] == ' ') {
        if (end >= 2 and line[end - 2] == '\\') break;
        end -= 1;
    }
    return line[0..end];
}

/// root/folder/name, read whole if small; null when missing or too big.
fn readSmall(a: std.mem.Allocator, root: []const u8, folder: []const u8, name: []const u8) ?[]const u8 {
    var buf: [c.PATH_MAX]u8 = undefined;
    const path = (if (folder.len == 0)
        std.fmt.bufPrintZ(&buf, "{s}/{s}", .{ root, name })
    else
        std.fmt.bufPrintZ(&buf, "{s}/{s}/{s}", .{ root, folder, name })) catch return null;
    const fd = c.open(path.ptr, .{ .ACCMODE = .RDONLY, .CLOEXEC = true });
    if (fd < 0) return null;
    defer _ = c.close(fd);
    var st: c.Stat = undefined;
    if (c.fstat(fd, &st) != 0 or st.size > max_rules_file or st.mode & c.S.IFMT != c.S.IFREG) return null;
    const bytes = a.alloc(u8, @intCast(st.size)) catch return null;
    var at: usize = 0;
    while (at < bytes.len) {
        const n = c.read(fd, bytes[at..].ptr, bytes.len - at);
        if (n <= 0) break;
        at += @intCast(n);
    }
    return bytes[0..at];
}

const testing = std.testing;
const TestDir = @import("test_dir.zig").TestDir;

test "gitignore with negation, folders and nested files" {
    var dir = try TestDir.init();
    defer dir.deinit();
    try dir.writeFile(".gitignore",
        \\# build output
        \\*.log
        \\build/*
        \\!build/keep.txt
        \\/top-only.txt
        \\cache/
        \\
    );
    try dir.makeDir("src/nested");
    try dir.writeFile("src/nested/.gitignore", "!important.log\nlocal.txt\n");
    try dir.makeDir(".git/info");
    try dir.writeFile(".git/info/exclude", "secret.txt\n");
    try dir.writeFile(".ignore", "vendor\n");
    var m = try Matcher.init(testing.allocator, dir.path());
    defer m.deinit();

    try testing.expect(m.isIgnored("debug.log", false));
    try testing.expect(m.isIgnored("src/deep/debug.log", false));
    try testing.expect(!m.isIgnored("src/nested/important.log", false));
    try testing.expect(m.isIgnored("src/nested/other.log", false));
    try testing.expect(m.isIgnored("src/nested/local.txt", false));
    try testing.expect(!m.isIgnored("src/local.txt", false));
    try testing.expect(m.isIgnored("build/out.o", false));
    try testing.expect(!m.isIgnored("build/keep.txt", false));
    try testing.expect(m.isIgnored("top-only.txt", false));
    try testing.expect(!m.isIgnored("src/top-only.txt", false));
    try testing.expect(m.isIgnored("cache", true));
    try testing.expect(!m.isIgnored("cache", false));
    try testing.expect(m.isIgnored("cache/x/y.txt", false));
    try testing.expect(m.isIgnored("secret.txt", false));
    try testing.expect(m.isIgnored("vendor/lib.c", false));
    try testing.expect(!m.isIgnored("src/main.zig", false));
}

test "a file inside an ignored folder stays ignored, as in git" {
    var dir = try TestDir.init();
    defer dir.deinit();
    try dir.writeFile(".gitignore", "build/\n!build/keep.txt\n");
    var m = try Matcher.init(testing.allocator, dir.path());
    defer m.deinit();
    try testing.expect(m.isIgnored("build/keep.txt", false));
}
