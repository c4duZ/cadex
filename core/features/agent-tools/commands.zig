//! The agent's subcommands of `cadex` (docs/spec/agent-tools.md, plan 20
//! phase B): `run`, `commands`, the shortcuts (`open`, `diff`, `preview`,
//! `notify`, `worktree status|comment`) and `skills`. Each shortcut is a
//! command id with its arguments; the app checks the token and the agent's
//! list and runs it (docs/adr/0024-agent-tools.md).

const std = @import("std");
const request = @import("request.zig");
const skills = @import("skills.zig");

pub const Planned = struct {
    /// Null for the list of commands.
    id: ?[]const u8,
    args: std.ArrayList(request.Arg) = .empty,

    pub fn deinit(self: *Planned, gpa: std.mem.Allocator) void {
        self.args.deinit(gpa);
    }
};

/// What a subcommand asks the app, from its words (after the subcommand);
/// error.Usage when they do not fit.
pub fn plan(gpa: std.mem.Allocator, sub: []const u8, words: []const []const u8) !Planned {
    var p: Planned = .{ .id = null };
    errdefer p.deinit(gpa);
    if (std.mem.eql(u8, sub, "commands")) return p;
    if (std.mem.eql(u8, sub, "run")) {
        if (words.len == 0) return error.Usage;
        p.id = words[0];
        for (words[1..]) |word| {
            const eq = std.mem.indexOfScalar(u8, word, '=') orelse return error.Usage;
            try p.args.append(gpa, .{ .key = word[0..eq], .value = word[eq + 1 ..] });
        }
    } else if (std.mem.eql(u8, sub, "open")) {
        if (words.len != 1) return error.Usage;
        p.id = "agent-tools.open-file";
        const target = words[0];
        // "src/a.ts:42" opens at the line; a colon not followed by a number is part of the name.
        if (std.mem.lastIndexOfScalar(u8, target, ':')) |colon| {
            if (colon + 1 < target.len and std.fmt.parseInt(u32, target[colon + 1 ..], 10) catch null != null) {
                try p.args.append(gpa, .{ .key = "path", .value = target[0..colon] });
                try p.args.append(gpa, .{ .key = "line", .value = target[colon + 1 ..] });
                return p;
            }
        }
        try p.args.append(gpa, .{ .key = "path", .value = target });
    } else if (std.mem.eql(u8, sub, "diff")) {
        if (words.len > 1) return error.Usage;
        p.id = "agent-tools.open-diff";
        if (words.len == 1) try p.args.append(gpa, .{ .key = "path", .value = words[0] });
    } else if (std.mem.eql(u8, sub, "preview")) {
        if (words.len != 1) return error.Usage;
        p.id = "preview.open";
        try p.args.append(gpa, .{ .key = "url", .value = words[0] });
    } else if (std.mem.eql(u8, sub, "notify")) {
        if (words.len == 0) return error.Usage;
        p.id = "agent-tools.notify";
        try p.args.append(gpa, .{ .key = "text", .value = try std.mem.join(gpa, " ", words) });
    } else if (std.mem.eql(u8, sub, "worktree")) {
        if (words.len < 2) return error.Usage;
        if (std.mem.eql(u8, words[0], "status")) {
            if (words.len != 2) return error.Usage;
            p.id = "worktrees.set-status";
            try p.args.append(gpa, .{ .key = "status", .value = words[1] });
        } else if (std.mem.eql(u8, words[0], "comment")) {
            p.id = "worktrees.set-comment";
            try p.args.append(gpa, .{ .key = "comment", .value = try std.mem.join(gpa, " ", words[1..]) });
        } else return error.Usage;
    } else return error.Unknown;
    return p;
}

/// The values plan() joined (notify, comment) are the planner's to free.
pub fn freeJoined(gpa: std.mem.Allocator, sub: []const u8, p: *Planned) void {
    const joined = std.mem.eql(u8, sub, "notify") or (std.mem.eql(u8, sub, "worktree") and p.args.items.len > 0 and
        std.mem.eql(u8, p.args.items[0].key, "comment"));
    if (joined) for (p.args.items) |a| gpa.free(a.value);
}

pub const usage =
    \\       cadex open <file>[:line]          (opens it in Cadex, beside this terminal)
    \\       cadex diff [file]                 (the diff of a file, or of the whole task)
    \\       cadex preview <url>               (opens the page in Cadex's preview)
    \\       cadex notify <text>               (a notification to the owner)
    \\       cadex worktree status <todo|doing|review|done> | comment <text>
    \\       cadex commands | run <id> [key=value ...]   (add --json for the raw answer)
    \\       cadex skills list | get <topic>
    \\
;

const testing = std.testing;

test "the shortcuts become command ids with their arguments" {
    const gpa = testing.allocator;
    var open = try plan(gpa, "open", &.{"src/app.ts:42"});
    defer open.deinit(gpa);
    try testing.expectEqualStrings("agent-tools.open-file", open.id.?);
    try testing.expectEqualStrings("src/app.ts", open.args.items[0].value);
    try testing.expectEqualStrings("42", open.args.items[1].value);
    var odd = try plan(gpa, "open", &.{"C:weird"});
    defer odd.deinit(gpa);
    try testing.expectEqualStrings("C:weird", odd.args.items[0].value);
    var status = try plan(gpa, "worktree", &.{ "status", "review" });
    defer status.deinit(gpa);
    try testing.expectEqualStrings("worktrees.set-status", status.id.?);
    var note = try plan(gpa, "notify", &.{ "tests", "pass" });
    defer {
        freeJoined(gpa, "notify", &note);
        note.deinit(gpa);
    }
    try testing.expectEqualStrings("tests pass", note.args.items[0].value);
    var run = try plan(gpa, "run", &.{ "preview.open", "url=http://localhost:5173" });
    defer run.deinit(gpa);
    try testing.expectEqualStrings("url", run.args.items[0].key);
    try testing.expectError(error.Usage, plan(gpa, "run", &.{ "x", "novalue" }));
    try testing.expectError(error.Usage, plan(gpa, "worktree", &.{ "status", "a", "b" }));
    try testing.expectError(error.Unknown, plan(gpa, "dance", &.{}));
    var list = try plan(gpa, "commands", &.{});
    defer list.deinit(gpa);
    try testing.expect(list.id == null);
}

test "skills come from the binary" {
    try testing.expect(skills.find("cadex") != null);
}
