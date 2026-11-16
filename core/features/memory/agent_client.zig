//! `cadex memory-agent <action> [--cwd DIR] [--workspace W] [--path P] [--id ID] [--dry-run]`:
//! the app's way to the memory engine, since only this feature talks to
//! memory.sock (the app runs this command and reads what it prints). The
//! token is CADEX_SESSION_TOKEN, which the app gives from its own token file
//! in the tokens folder; the socket and the engine come from the same
//! variables as the hook (hook_client.Env), the workspace from --workspace
//! or CADEX_MEMORY_WORKSPACE (the account's, memory.shareAcrossAccounts off).
//!
//! The memory agent (plan 22 phase G): status, pause, resume, dream,
//! bootstrap (`/cadex/agent/*`). The Memory page (phase H, 2026-11-16;
//! `/cadex/memory/*`, server/src/page/): overview, briefing, write-page (the
//! Markdown on stdin), delete-page, reindex, proposals, approve, reject.
//!
//! `status` and `overview` never start the engine (down: `{"running":false}`);
//! the others start it. One JSON line out, except `briefing`: the text the
//! next SessionStart would get, as the hook prints it (an empty line when
//! there is none). An engine refusal exits 1 with `{"error":"…"}`; a bad
//! command line exits 2.

const std = @import("std");
const clock = @import("../../shared/clock.zig");
const hook = @import("hook_client.zig");
const http = @import("http.zig");
const launch = @import("launch.zig");
const events = @import("events.zig");

pub const Action = enum { status, pause, @"resume", dream, bootstrap, overview, briefing, @"write-page", @"delete-page", reindex, proposals, approve, reject };

pub const Options = struct {
    cwd: ?[]const u8 = null,
    workspace: ?[]const u8 = null,
    path: ?[]const u8 = null,
    id: ?[]const u8 = null,
    dry_run: bool = false,
};

fn needsCwd(action: Action) bool {
    return switch (action) {
        .status, .pause, .@"resume", .approve, .reject => false,
        else => true,
    };
}

fn needsPath(action: Action) bool {
    return action == .@"write-page" or action == .@"delete-page";
}

fn needsId(action: Action) bool {
    return action == .approve or action == .reject;
}

/// How long the whole exchange may take: a page write embeds it (the model
/// may load first, ~1 s), a reindex reads every page of the project.
fn budgetMs(action: Action) i64 {
    return switch (action) {
        .reindex => 120_000,
        .@"write-page", .@"delete-page", .approve, .briefing => 30_000,
        else => 5_000,
    };
}

fn appendPair(gpa: std.mem.Allocator, out: *std.ArrayList(u8), key: []const u8, value: []const u8) !void {
    try out.append(gpa, if (std.mem.indexOfScalar(u8, out.items, '?') == null) '?' else '&');
    try out.appendSlice(gpa, key);
    try out.append(gpa, '=');
    try events.appendEncoded(gpa, out, value);
}

/// The request each action makes: method and target.
pub fn target(gpa: std.mem.Allocator, action: Action, o: Options) !struct { method: []const u8, path: []u8 } {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    const method: []const u8 = switch (action) {
        .status, .overview, .briefing, .proposals => "GET",
        else => "POST",
    };
    switch (action) {
        .status => try out.appendSlice(gpa, "/cadex/agent/status"),
        .pause, .@"resume" => try out.print(gpa, "/cadex/agent/pause?on={s}", .{if (action == .pause) "1" else "0"}),
        .dream => try out.appendSlice(gpa, "/cadex/agent/run-dream"),
        .bootstrap => try out.appendSlice(gpa, "/cadex/agent/bootstrap"),
        else => try out.print(gpa, "/cadex/memory/{s}", .{@tagName(action)}),
    }
    if (needsCwd(action)) {
        try appendPair(gpa, &out, "cwd", o.cwd orelse "");
        if (o.workspace) |ws| try appendPair(gpa, &out, "workspace", ws);
    }
    if (needsPath(action)) try appendPair(gpa, &out, "path", o.path orelse "");
    if (needsId(action)) try appendPair(gpa, &out, "id", o.id orelse "");
    if (action == .bootstrap and o.dry_run) try out.appendSlice(gpa, "&dry_run=1");
    return .{ .method = method, .path = try out.toOwnedSlice(gpa) };
}

/// The command's output and exit code.
pub const Result = struct { out: []u8, code: u8 };

const Parsed = struct { action: Action, options: Options };

/// The command line, or null when it is not one this command takes.
fn parse(words: []const []const u8) ?Parsed {
    if (words.len == 0) return null;
    const action = std.meta.stringToEnum(Action, words[0]) orelse return null;
    var o: Options = .{};
    var i: usize = 1;
    while (i < words.len) : (i += 1) {
        const word = words[i];
        if (std.mem.eql(u8, word, "--dry-run")) {
            o.dry_run = true;
            continue;
        }
        if (i + 1 >= words.len) return null;
        const value = words[i + 1];
        if (std.mem.eql(u8, word, "--cwd")) o.cwd = value else if (std.mem.eql(u8, word, "--workspace")) o.workspace = value else if (std.mem.eql(u8, word, "--path")) o.path = value else if (std.mem.eql(u8, word, "--id")) o.id = value else return null;
        i += 1;
    }
    if (needsCwd(action) and o.cwd == null) return null;
    if (needsPath(action) and o.path == null) return null;
    if (needsId(action) and o.id == null) return null;
    return .{ .action = action, .options = o };
}

pub fn run(gpa: std.mem.Allocator, words: []const []const u8) !Result {
    const parsed = parse(words) orelse return usage(gpa);
    var socket_buf: [256]u8 = undefined;
    var dir_buf: [1024]u8 = undefined;
    const env = hook.Env.from(hook.Env.processEnv, &socket_buf, &dir_buf) orelse
        return .{ .out = try gpa.dupe(u8, "{\"error\":\"no CADEX_SESSION_TOKEN\"}\n"), .code = 1 };
    const input = if (parsed.action == .@"write-page") try readStdin(gpa) else try gpa.dupe(u8, "");
    defer gpa.free(input);
    return runWith(gpa, env, parsed, input);
}

/// `run` with the environment given and stdin read (tests).
fn runWith(gpa: std.mem.Allocator, env: hook.Env, parsed: Parsed, input: []const u8) !Result {
    const action = parsed.action;
    var o = parsed.options;
    if (o.workspace == null) o.workspace = env.workspace;
    const deadline = clock.monotonicMs() + budgetMs(action);
    if (action == .status or action == .overview) {
        if (http.connect(env.socket)) |fd| _ = std.c.close(fd) else return .{ .out = try gpa.dupe(u8, "{\"running\":false}\n"), .code = 0 };
    } else if (env.bin) |bin| {
        _ = launch.ensure(.{ .bin = bin, .socket = env.socket, .data_dir = env.data_dir, .tokens_dir = env.tokens_dir }, deadline);
    }
    const t = try target(gpa, action, o);
    defer gpa.free(t.path);
    const answer = try http.send(gpa, env.socket, t.method, t.path, env.token, input, deadline);
    defer if (answer) |a| a.deinit(gpa);
    return render(gpa, action, answer);
}

/// What to print for the engine's answer.
fn render(gpa: std.mem.Allocator, action: Action, answer: ?http.Response) !Result {
    const a = answer orelse return .{ .out = try gpa.dupe(u8, "{\"error\":\"the memory engine did not answer\"}\n"), .code = 1 };
    const body = std.mem.trim(u8, a.body, " \r\n");
    if (!a.ok()) {
        // The page's routes answer `{"error":…}`; the token check and axum's
        // own refusals answer plain text.
        if (std.mem.startsWith(u8, body, "{")) return .{ .out = try std.fmt.allocPrint(gpa, "{s}\n", .{body}), .code = 1 };
        const text = try std.fmt.allocPrint(gpa, "HTTP {d}: {s}", .{ a.status, body });
        defer gpa.free(text);
        return .{ .out = try std.fmt.allocPrint(gpa, "{{\"error\":{f}}}\n", .{std.json.fmt(text, .{})}), .code = 1 };
    }
    if (action == .briefing) {
        const text = try hook.briefingText(gpa, a.body);
        defer gpa.free(text);
        return .{ .out = try std.fmt.allocPrint(gpa, "{s}\n", .{text}), .code = 0 };
    }
    return .{ .out = try std.fmt.allocPrint(gpa, "{s}\n", .{body}), .code = 0 };
}

/// The page body on stdin, up to the engine's body limit (10 MB, engine.rs).
fn readStdin(gpa: std.mem.Allocator) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    var buf: [16 * 1024]u8 = undefined;
    while (out.items.len < 10 * 1024 * 1024) {
        const n = std.c.read(0, &buf, buf.len);
        if (n < 0) {
            if (std.c.errno(n) == .INTR) continue;
            return error.ReadFailed;
        }
        if (n == 0) break;
        try out.appendSlice(gpa, buf[0..@intCast(n)]);
    }
    return out.toOwnedSlice(gpa);
}

fn usage(gpa: std.mem.Allocator) !Result {
    return .{ .out = try gpa.dupe(u8, "usage: cadex memory-agent <status|pause|resume|dream|bootstrap|overview|briefing|write-page|" ++
        "delete-page|reindex|proposals|approve|reject> [--cwd DIR] [--workspace W] [--path P] [--id ID] [--dry-run]\n"), .code = 2 };
}

const testing = std.testing;

fn expectTarget(action: Action, o: Options, method: []const u8, path: []const u8) !void {
    const t = try target(testing.allocator, action, o);
    defer testing.allocator.free(t.path);
    try testing.expectEqualStrings(method, t.method);
    try testing.expectEqualStrings(path, t.path);
}

test "each action's request" {
    try expectTarget(.status, .{}, "GET", "/cadex/agent/status");
    try expectTarget(.pause, .{}, "POST", "/cadex/agent/pause?on=1");
    try expectTarget(.bootstrap, .{ .cwd = "/a b", .dry_run = true }, "POST", "/cadex/agent/bootstrap?cwd=%2Fa%20b&dry_run=1");
    try expectTarget(.dream, .{ .cwd = "/r" }, "POST", "/cadex/agent/run-dream?cwd=%2Fr");
    try expectTarget(.overview, .{ .cwd = "/r", .workspace = "acct" }, "GET", "/cadex/memory/overview?cwd=%2Fr&workspace=acct");
    try expectTarget(.briefing, .{ .cwd = "/r" }, "GET", "/cadex/memory/briefing?cwd=%2Fr");
    try expectTarget(.@"write-page", .{ .cwd = "/r", .path = "notes/a b.md" }, "POST", "/cadex/memory/write-page?cwd=%2Fr&path=notes%2Fa%20b.md");
    try expectTarget(.@"delete-page", .{ .cwd = "/r", .path = "x.md" }, "POST", "/cadex/memory/delete-page?cwd=%2Fr&path=x.md");
    try expectTarget(.reindex, .{ .cwd = "/r" }, "POST", "/cadex/memory/reindex?cwd=%2Fr");
    try expectTarget(.proposals, .{ .cwd = "/r" }, "GET", "/cadex/memory/proposals?cwd=%2Fr");
    try expectTarget(.approve, .{ .id = "0198-ab" }, "POST", "/cadex/memory/approve?id=0198-ab");
    try expectTarget(.reject, .{ .id = "x" }, "POST", "/cadex/memory/reject?id=x");
}

test "a command line missing what its action needs is a usage error" {
    for ([_][]const []const u8{
        &.{"explode"},                     &.{"dream"},                           &.{ "overview", "--cwd" },
        &.{ "write-page", "--cwd", "/r" }, &.{ "delete-page", "--path", "a.md" }, &.{"approve"},
        &.{ "reject", "--cwd", "/r" },     &.{ "status", "--bogus", "x" },
    }) |words| {
        const result = try run(testing.allocator, words);
        defer testing.allocator.free(result.out);
        try testing.expectEqual(@as(u8, 2), result.code);
    }
    const ok = parse(&.{ "write-page", "--cwd", "/r", "--path", "a.md", "--workspace", "w" }).?;
    try testing.expectEqualStrings("w", ok.options.workspace.?);
}

test "the overview of an engine that is not running starts nothing" {
    const env: hook.Env = .{ .token = "t", .socket = "/nonexistent/cadex/memory.sock", .data_dir = "/nonexistent", .bin = "/nonexistent/cadex-memory" };
    const result = try runWith(testing.allocator, env, parse(&.{ "overview", "--cwd", "/r" }).?, "");
    defer testing.allocator.free(result.out);
    try testing.expectEqual(@as(u8, 0), result.code);
    try testing.expectEqualStrings("{\"running\":false}\n", result.out);
}

test "what is printed: the briefing as the hook gives it, errors as JSON" {
    const raw = "\n# Briefing\n<!-- ai-memory:backfill session_id=x -->\nUse tabs.\n";
    const briefing = try render(testing.allocator, .briefing, .{ .status = 200, .body = @constCast(raw) });
    defer testing.allocator.free(briefing.out);
    try testing.expectEqualStrings("# Briefing\nUse tabs.\n", briefing.out);
    const empty = try render(testing.allocator, .briefing, .{ .status = 200, .body = @constCast("") });
    defer testing.allocator.free(empty.out);
    try testing.expectEqualStrings("\n", empty.out);
    const refused = try render(testing.allocator, .@"write-page", .{ .status = 400, .body = @constCast("{\"error\":\"bad path\"}") });
    defer testing.allocator.free(refused.out);
    try testing.expectEqual(@as(u8, 1), refused.code);
    try testing.expectEqualStrings("{\"error\":\"bad path\"}\n", refused.out);
    const plain = try render(testing.allocator, .overview, .{ .status = 401, .body = @constCast("no \"token\"") });
    defer testing.allocator.free(plain.out);
    try testing.expectEqualStrings("{\"error\":\"HTTP 401: no \\\"token\\\"\"}\n", plain.out);
    const gone = try render(testing.allocator, .reindex, null);
    defer testing.allocator.free(gone.out);
    try testing.expectEqual(@as(u8, 1), gone.code);
}
