//! `cadex memory-agent <status|pause|resume|dream|bootstrap> [--cwd DIR] [--dry-run]`:
//! the app's way to the memory agent (plan 22 phase G, ADR 0029), since
//! only this feature talks to memory.sock (the app runs this command and
//! reads its JSON). The token is CADEX_SESSION_TOKEN, which the app gives
//! from its own token file in the tokens folder; the socket and the engine
//! come from the same variables as the hook (hook_client.Env).
//!
//! `status` never starts the engine (down: `{"running":false}`); the others
//! start it, since a queued job keeps it up (the engine's own rule).

const std = @import("std");
const clock = @import("../../shared/clock.zig");
const hook = @import("hook_client.zig");
const http = @import("http.zig");
const launch = @import("launch.zig");
const events = @import("events.zig");

pub const Action = enum { status, pause, @"resume", dream, bootstrap };

/// The request each action makes: method and target.
pub fn target(gpa: std.mem.Allocator, action: Action, cwd: ?[]const u8, dry_run: bool) !struct { method: []const u8, path: []u8 } {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    const method: []const u8 = switch (action) {
        .status => blk: {
            try out.appendSlice(gpa, "/cadex/agent/status");
            break :blk "GET";
        },
        .pause, .@"resume" => blk: {
            try out.print(gpa, "/cadex/agent/pause?on={s}", .{if (action == .pause) "1" else "0"});
            break :blk "POST";
        },
        .dream, .bootstrap => blk: {
            try out.print(gpa, "/cadex/agent/{s}?cwd=", .{if (action == .dream) "run-dream" else "bootstrap"});
            try events.appendEncoded(gpa, &out, cwd orelse "");
            if (action == .bootstrap and dry_run) try out.appendSlice(gpa, "&dry_run=1");
            break :blk "POST";
        },
    };
    return .{ .method = method, .path = try out.toOwnedSlice(gpa) };
}

/// The command's output (JSON, one line) and exit code.
pub const Result = struct { out: []u8, code: u8 };

pub fn run(gpa: std.mem.Allocator, words: []const []const u8) !Result {
    if (words.len == 0) return usage(gpa);
    const action = std.meta.stringToEnum(Action, words[0]) orelse return usage(gpa);
    var cwd: ?[]const u8 = null;
    var dry_run = false;
    var i: usize = 1;
    while (i < words.len) : (i += 1) {
        if (std.mem.eql(u8, words[i], "--dry-run")) {
            dry_run = true;
        } else if (std.mem.eql(u8, words[i], "--cwd") and i + 1 < words.len) {
            i += 1;
            cwd = words[i];
        } else return usage(gpa);
    }
    if ((action == .dream or action == .bootstrap) and cwd == null) return usage(gpa);
    var socket_buf: [256]u8 = undefined;
    var dir_buf: [1024]u8 = undefined;
    const env = hook.Env.from(hook.Env.processEnv, &socket_buf, &dir_buf) orelse
        return .{ .out = try gpa.dupe(u8, "{\"error\":\"no CADEX_SESSION_TOKEN\"}\n"), .code = 1 };
    const deadline = clock.monotonicMs() + 5000;
    if (action == .status) {
        if (http.connect(env.socket)) |fd| _ = std.c.close(fd) else return .{ .out = try gpa.dupe(u8, "{\"running\":false}\n"), .code = 0 };
    } else if (env.bin) |bin| {
        _ = launch.ensure(.{ .bin = bin, .socket = env.socket, .data_dir = env.data_dir, .tokens_dir = env.tokens_dir }, deadline);
    }
    const t = try target(gpa, action, cwd, dry_run);
    defer gpa.free(t.path);
    const answer = (try http.send(gpa, env.socket, t.method, t.path, env.token, "", deadline)) orelse
        return .{ .out = try gpa.dupe(u8, "{\"error\":\"the memory engine did not answer\"}\n"), .code = 1 };
    defer answer.deinit(gpa);
    const body = std.mem.trimEnd(u8, answer.body, " \r\n");
    return .{ .out = try std.fmt.allocPrint(gpa, "{s}\n", .{body}), .code = if (answer.ok()) 0 else 1 };
}

fn usage(gpa: std.mem.Allocator) !Result {
    return .{ .out = try gpa.dupe(u8, "usage: cadex memory-agent <status|pause|resume|dream|bootstrap> [--cwd DIR] [--dry-run]\n"), .code = 2 };
}

const testing = std.testing;

test "each action's request" {
    const status = try target(testing.allocator, .status, null, false);
    defer testing.allocator.free(status.path);
    try testing.expectEqualStrings("GET", status.method);
    try testing.expectEqualStrings("/cadex/agent/status", status.path);
    const pause = try target(testing.allocator, .pause, null, false);
    defer testing.allocator.free(pause.path);
    try testing.expectEqualStrings("/cadex/agent/pause?on=1", pause.path);
    const dry = try target(testing.allocator, .bootstrap, "/a b", true);
    defer testing.allocator.free(dry.path);
    try testing.expectEqualStrings("/cadex/agent/bootstrap?cwd=%2Fa%20b&dry_run=1", dry.path);
    const dream = try target(testing.allocator, .dream, "/r", false);
    defer testing.allocator.free(dream.path);
    try testing.expectEqualStrings("/cadex/agent/run-dream?cwd=%2Fr", dream.path);
    const bad = try run(testing.allocator, &.{"explode"});
    defer testing.allocator.free(bad.out);
    try testing.expectEqual(@as(u8, 2), bad.code);
    const no_cwd = try run(testing.allocator, &.{"dream"});
    defer testing.allocator.free(no_cwd.out);
    try testing.expectEqual(@as(u8, 2), no_cwd.code);
}
