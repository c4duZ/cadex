//! Running the user's `git` (docs/spec/source-control.md): only inside an
//! authorized folder, with a time limit, never waiting for a password on a
//! terminal that does not exist, and in the C locale so messages and
//! formats do not change with the user's language.

const std = @import("std");
const workspace = @import("../workspace/workspace.zig");
const process = @import("../../shared/process.zig");

pub const Result = process.Result;

/// Fetch, pull and push talk to a server: more time.
pub const network_timeout_ms = 120_000;
pub const local_timeout_ms = 30_000;

const env = [_][]const u8{
    // A credential prompt would hang until the time limit.
    "GIT_TERMINAL_PROMPT=0",
    // Status must not take the index lock the user's own git may need.
    "GIT_OPTIONAL_LOCKS=0",
    "LC_ALL=C",
    // Never open an editor or a pager.
    "GIT_EDITOR=true",
    "GIT_PAGER=cat",
};

pub const Error = workspace.Error || error{ GitMissing, SpawnFailed };

/// Runs `git <args>` in `repo` (a folder inside the workspace).
pub fn run(gpa: std.mem.Allocator, registry: *workspace.Registry, repo: []const u8, args: []const []const u8, options: struct {
    timeout_ms: u32 = local_timeout_ms,
    stdin: []const u8 = "",
    /// The history search reads the whole log (git-history).
    max_output: usize = 16 * 1024 * 1024,
}) !Result {
    var buf: workspace.paths.Buffer = undefined;
    const real = try registry.resolve(repo, &buf);
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(gpa);
    try argv.append(gpa, "git");
    try argv.appendSlice(gpa, args);
    const result = try process.run(gpa, argv.items, .{
        .cwd = real,
        .timeout_ms = options.timeout_ms,
        .env = &env,
        .stdin = options.stdin,
        .max_output = options.max_output,
    });
    if (result.code == -1) {
        var r = result;
        r.deinit(gpa);
        return error.GitMissing;
    }
    return result;
}

/// Whether a working `git` is on the PATH.
pub fn available(gpa: std.mem.Allocator) bool {
    var r = process.run(gpa, &.{ "git", "--version" }, .{ .timeout_ms = 10_000 }) catch return false;
    defer r.deinit(gpa);
    return r.ok() and std.mem.startsWith(u8, r.stdout, "git version");
}

/// The top folder of the repository holding `folder`, or null when it is
/// not in one. Caller frees.
pub fn root(gpa: std.mem.Allocator, registry: *workspace.Registry, folder: []const u8) !?[]u8 {
    var r = try run(gpa, registry, folder, &.{ "rev-parse", "--show-toplevel" }, .{});
    defer r.deinit(gpa);
    if (!r.ok()) return null;
    const top = std.mem.trimEnd(u8, r.stdout, "\n");
    var buf: workspace.paths.Buffer = undefined;
    const real = workspace.paths.canonicalize(top, &buf) catch return null;
    return try gpa.dupe(u8, real);
}

/// The first line of git's error output, for a short message.
pub fn message(r: Result) []const u8 {
    const text = if (r.stderr.len > 0) r.stderr else r.stdout;
    var lines = std.mem.splitScalar(u8, std.mem.trim(u8, text, "\n "), '\n');
    while (lines.next()) |line| {
        const l = std.mem.trim(u8, line, " ");
        if (l.len > 0 and !std.mem.startsWith(u8, l, "hint:")) return l;
    }
    return if (r.timed_out) "git demorou demais" else "git falhou";
}
