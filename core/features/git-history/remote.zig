//! The commit's page on the remote (docs/spec/git-history.md), from the
//! `origin` URL in SSH or HTTPS form. GitHub, Gitea and others use
//! /commit/<sha>; GitLab /-/commit/<sha>; Bitbucket /commits/<sha>.

const std = @import("std");
const sc = @import("../source-control/source_control.zig");
const workspace = @import("../workspace/workspace.zig");

/// Host and path ("github.com", "owner/repo") of a remote URL, or null for
/// a local path or something unknown.
pub const Place = struct {
    host: []const u8,
    path: []const u8,
};

pub fn place(url: []const u8) ?Place {
    var rest = std.mem.trim(u8, url, " \n\r\t");
    var with_scheme = false;
    for ([_][]const u8{ "https://", "http://", "ssh://", "git://", "git+ssh://" }) |scheme| {
        if (std.mem.startsWith(u8, rest, scheme)) {
            rest = rest[scheme.len..];
            with_scheme = true;
            break;
        }
    }
    // user@ (git@, or a login in an HTTPS URL)
    const slash = std.mem.indexOfScalar(u8, rest, '/') orelse rest.len;
    if (std.mem.lastIndexOfScalar(u8, rest[0..slash], '@')) |at| rest = rest[at + 1 ..];
    var host_end: usize = undefined;
    var path_start: usize = undefined;
    if (with_scheme) {
        host_end = std.mem.indexOfScalar(u8, rest, '/') orelse return null;
        path_start = host_end + 1;
        // ssh://host:2222/owner/repo: the port is not part of the web address.
        if (std.mem.indexOfScalar(u8, rest[0..host_end], ':')) |colon| {
            const path = rest[path_start..];
            return finish(rest[0..colon], path);
        }
    } else {
        // scp-like: host:owner/repo
        host_end = std.mem.indexOfScalar(u8, rest, ':') orelse return null;
        path_start = host_end + 1;
    }
    return finish(rest[0..host_end], rest[path_start..]);
}

fn finish(host: []const u8, raw_path: []const u8) ?Place {
    var path = std.mem.trim(u8, raw_path, "/");
    if (std.mem.endsWith(u8, path, ".git")) path = path[0 .. path.len - 4];
    if (host.len == 0 or std.mem.indexOfScalar(u8, path, '/') == null) return null;
    return .{ .host = host, .path = path };
}

/// The web address of `sha` for the remote `url`. Caller frees.
pub fn commitUrl(gpa: std.mem.Allocator, url: []const u8, sha: []const u8) !?[]u8 {
    const p = place(url) orelse return null;
    const route = if (std.mem.indexOf(u8, p.host, "gitlab") != null)
        "-/commit"
    else if (std.mem.indexOf(u8, p.host, "bitbucket") != null)
        "commits"
    else
        "commit";
    return try std.fmt.allocPrint(gpa, "https://{s}/{s}/{s}/{s}", .{ p.host, p.path, route, sha });
}

/// The commit's address on `origin`, or null without a known remote.
pub fn originCommitUrl(gpa: std.mem.Allocator, registry: *workspace.Registry, repo: []const u8, sha: []const u8) !?[]u8 {
    var r = try sc.git.run(gpa, registry, repo, &.{ "remote", "get-url", "origin" }, .{});
    defer r.deinit(gpa);
    if (!r.ok()) return null;
    return commitUrl(gpa, r.stdout, sha);
}

fn expectUrl(remote: []const u8, expected: ?[]const u8) !void {
    const got = try commitUrl(std.testing.allocator, remote, "abc123");
    defer if (got) |g| std.testing.allocator.free(g);
    if (expected) |e| try std.testing.expectEqualStrings(e, got orelse return error.NoUrl) else try std.testing.expect(got == null);
}

test "commit address from SSH and HTTPS remotes" {
    try expectUrl("git@github.com:dono/repo.git\n", "https://github.com/dono/repo/commit/abc123");
    try expectUrl("https://github.com/dono/repo", "https://github.com/dono/repo/commit/abc123");
    try expectUrl("ssh://git@github.com/dono/repo.git", "https://github.com/dono/repo/commit/abc123");
    try expectUrl("git@gitlab.com:grupo/sub/repo.git", "https://gitlab.com/grupo/sub/repo/-/commit/abc123");
    try expectUrl("https://gitlab.com/grupo/repo.git", "https://gitlab.com/grupo/repo/-/commit/abc123");
    try expectUrl("https://ana@bitbucket.org/time/repo.git", "https://bitbucket.org/time/repo/commits/abc123");
    try expectUrl("git@bitbucket.org:time/repo.git", "https://bitbucket.org/time/repo/commits/abc123");
    try expectUrl("ssh://git@gitea.local:2222/ana/repo.git", "https://gitea.local/ana/repo/commit/abc123");
    try expectUrl("/Users/ana/repo.git", null);
    try expectUrl("../outro", null);
}
