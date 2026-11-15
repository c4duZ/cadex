//! The repository's `.worktreeinclude` (docs/spec/worktrees.md): the files
//! outside git (`.env` and the like) that a new task's worktree gets a copy
//! of. Same lines as a `.gitignore`: a leading "/" anchors at the root, a
//! trailing "/" means a folder, "!" takes a match back, the last matching
//! line wins, "#" is a comment.

const std = @import("std");
const workspace = @import("../workspace/workspace.zig");
const sc = @import("../source-control/source_control.zig");
const fs = @import("../../shared/fs.zig");
const glob = @import("../../shared/glob.zig");

pub const Rule = struct {
    pattern: []const u8,
    negated: bool,
    dir_only: bool,
    anchored: bool,
    /// The line as written, for "matched nothing".
    line: []const u8,
};

/// The rules of a `.worktreeinclude`'s text; strings point into `text`.
pub fn parse(arena: std.mem.Allocator, text: []const u8) ![]Rule {
    var out: std.ArrayList(Rule) = .empty;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;
        var p = line;
        const negated = p[0] == '!';
        if (negated) p = p[1..];
        const dir_only = p.len > 0 and p[p.len - 1] == '/';
        if (dir_only) p = p[0 .. p.len - 1];
        const leading = p.len > 0 and p[0] == '/';
        if (leading) p = p[1..];
        if (p.len == 0) continue;
        try out.append(arena, .{ .pattern = p, .negated = negated, .dir_only = dir_only,
            .anchored = leading or std.mem.indexOfScalar(u8, p, '/') != null, .line = line });
    }
    return out.toOwnedSlice(arena);
}

/// Whether `rel` (a path from the root, no trailing "/") is included.
pub fn includes(rules: []const Rule, rel: []const u8, is_dir: bool) bool {
    var result = false;
    for (rules) |rule| {
        if (matches(rule, rel, is_dir)) result = !rule.negated;
    }
    return result;
}

fn matches(rule: Rule, rel: []const u8, is_dir: bool) bool {
    if (rule.dir_only and !is_dir) return false;
    if (rule.anchored) return glob.match(rule.pattern, rel);
    const base = if (std.mem.lastIndexOfScalar(u8, rel, '/')) |slash| rel[slash + 1 ..] else rel;
    return glob.match(rule.pattern, base);
}

pub const Report = struct {
    copied: usize = 0,
    /// The lines that matched nothing, one per line ("pula e conta no fim").
    unmatched: []const u8 = "",
};

/// Copies into `worktree` what the repository's `.worktreeinclude` names
/// among the files git does not track (`git ls-files --others --directory`:
/// an untracked folder comes whole). No `.worktreeinclude`: nothing.
/// Strings of the report live in `arena`.
pub fn copy(arena: std.mem.Allocator, registry: *workspace.Registry, repo: []const u8, worktree: []const u8) !Report {
    var path_buf: fs.Buffer = undefined;
    const rules_path = std.fmt.bufPrint(&path_buf, "{s}/.worktreeinclude", .{repo}) catch return .{};
    const file = fs.File.openRead(rules_path, .{}) catch return .{};
    defer file.close();
    var text: std.ArrayList(u8) = .empty;
    try fs.appendUpTo(arena, file, &text, 256 * 1024);
    const rules = try parse(arena, text.items);
    if (rules.len == 0) return .{};

    var r = try sc.git.run(arena, registry, repo, &.{ "ls-files", "--others", "--directory", "-z" }, .{});
    defer r.deinit(arena);
    if (!r.ok()) return error.GitFailed;
    const used = try arena.alloc(bool, rules.len);
    @memset(used, false);
    var report: Report = .{};
    var entries = std.mem.splitScalar(u8, r.stdout, 0);
    while (entries.next()) |entry| {
        if (entry.len == 0) continue;
        const is_dir = entry[entry.len - 1] == '/';
        const rel = if (is_dir) entry[0 .. entry.len - 1] else entry;
        if (!includes(rules, rel, is_dir)) continue;
        for (rules, 0..) |rule, i| if (matches(rule, rel, is_dir)) {
            used[i] = true;
        };
        var from_buf: fs.Buffer = undefined;
        var to_buf: fs.Buffer = undefined;
        const from = std.fmt.bufPrint(&from_buf, "{s}/{s}", .{ repo, rel }) catch continue;
        const to = std.fmt.bufPrint(&to_buf, "{s}/{s}", .{ worktree, rel }) catch continue;
        if (fs.exists(to)) continue;
        if (std.fs.path.dirname(to)) |parent| makeDirs(parent);
        fs.copyTree(from, to) catch continue;
        report.copied += 1;
    }
    var unmatched: std.ArrayList(u8) = .empty;
    for (rules, used) |rule, was| if (!was and !rule.negated) {
        try unmatched.appendSlice(arena, rule.line);
        try unmatched.append(arena, '\n');
    };
    report.unmatched = unmatched.items;
    return report;
}

fn makeDirs(path: []const u8) void {
    if (fs.isDirectory(path)) return;
    if (std.fs.path.dirname(path)) |parent| makeDirs(parent);
    fs.makeDirectory(path) catch {};
}

const testing = std.testing;

test "the lines of a .worktreeinclude, as in a .gitignore" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const rules = try parse(arena.allocator(), "# secrets\n.env\n.env.*\n!.env.example\n/config/local.json\ncerts/\n");
    try testing.expect(includes(rules, ".env", false));
    try testing.expect(includes(rules, "apps/web/.env", false));
    try testing.expect(includes(rules, ".env.local", false));
    try testing.expect(!includes(rules, ".env.example", false));
    try testing.expect(includes(rules, "config/local.json", false));
    try testing.expect(!includes(rules, "x/config/local.json", false));
    try testing.expect(includes(rules, "certs", true) and !includes(rules, "certs", false));
    try testing.expect(!includes(rules, "README.md", false));
}
