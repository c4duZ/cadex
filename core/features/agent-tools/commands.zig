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
    /// A `spec-file=` read into `spec=` (orchestration.spawn), owned here.
    owned: ?[]u8 = null,

    pub fn deinit(self: *Planned, gpa: std.mem.Allocator) void {
        if (self.owned) |text| gpa.free(text);
        self.args.deinit(gpa);
    }
};

/// The biggest spec a `spec-file=` may hold: the same as a prompt
/// (docs/spec/orchestration.md, "Prompt enorme").
pub const max_spec_bytes = 100 * 1024;

/// `spec-file=<path>` (orchestration.spawn, plan 24 D2): the text goes to the
/// app as the value of `spec=`, read here, so the sub-task's prompt is a
/// file's text and never a command (docs/adr/0033-cadex-launches-agents.md).
/// A regular file, at most `max_spec_bytes`, no NUL.
pub fn readSpec(gpa: std.mem.Allocator, path: []const u8) ![]u8 {
    const z = try gpa.dupeZ(u8, path);
    defer gpa.free(z);
    const fd = std.c.open(z.ptr, .{ .ACCMODE = .RDONLY });
    if (fd < 0) return error.SpecFile;
    defer _ = std.c.close(fd);
    var st: std.c.Stat = undefined;
    if (std.c.fstat(fd, &st) != 0 or !std.c.S.ISREG(st.mode) or st.size > max_spec_bytes) return error.SpecFile;
    const text = try gpa.alloc(u8, @intCast(st.size));
    errdefer gpa.free(text);
    var got: usize = 0;
    while (got < text.len) {
        const n = std.c.read(fd, text[got..].ptr, text.len - got);
        if (n <= 0) break;
        got += @intCast(n);
    }
    if (got != text.len or std.mem.indexOfScalar(u8, text, 0) != null) return error.SpecFile;
    return text;
}

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
            if (std.mem.eql(u8, word[0..eq], "spec-file")) {
                if (p.owned != null) return error.Usage;
                p.owned = try readSpec(gpa, word[eq + 1 ..]);
                try p.args.append(gpa, .{ .key = "spec", .value = p.owned.? });
                continue;
            }
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
    } else if (std.mem.eql(u8, sub, "browser")) {
        try planBrowser(gpa, &p, words);
    } else if (std.mem.eql(u8, sub, "computer")) {
        try planComputer(gpa, &p, words);
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

/// `cadex browser <action> …`: the agent's browser in the preview
/// (docs/spec/preview.md), one command `preview.agent` with `action=`.
fn planBrowser(gpa: std.mem.Allocator, p: *Planned, words: []const []const u8) !void {
    if (words.len == 0) return error.Usage;
    const action = words[0];
    const rest = words[1..];
    p.id = "preview.agent";
    try p.args.append(gpa, .{ .key = "action", .value = action });
    const Want = struct { key: []const u8, joined: bool = false };
    const shape: []const Want = if (std.mem.eql(u8, action, "goto")) &.{.{ .key = "url" }}
        else if (std.mem.eql(u8, action, "click")) &.{.{ .key = "ref" }}
        else if (std.mem.eql(u8, action, "fill")) &.{ .{ .key = "ref" }, .{ .key = "text", .joined = true } }
        else if (std.mem.eql(u8, action, "press")) &.{.{ .key = "key" }}
        else if (std.mem.eql(u8, action, "scroll")) &.{.{ .key = "target" }}
        else if (std.mem.eql(u8, action, "wait")) &.{ .{ .key = "selector" }, .{ .key = "timeout" } }
        else if (std.mem.eql(u8, action, "snapshot") or std.mem.eql(u8, action, "screenshot") or
            std.mem.eql(u8, action, "console") or std.mem.eql(u8, action, "notes")) &.{}
        else return error.Usage;
    const optional = std.mem.eql(u8, action, "wait") or std.mem.eql(u8, action, "scroll");
    if (!optional and rest.len < shape.len) return error.Usage;
    for (shape, 0..) |want, i| {
        if (i >= rest.len) break;
        const value = if (want.joined) try std.mem.join(gpa, " ", rest[i..]) else rest[i];
        try p.args.append(gpa, .{ .key = want.key, .value = value });
        if (want.joined) break;
    }
    if (!(shape.len > 0 and shape[shape.len - 1].joined) and rest.len > shape.len) return error.Usage;
}

/// `cadex computer <action> …`: another app by accessibility
/// (docs/spec/computer-use.md), one command `computer-use.agent`.
fn planComputer(gpa: std.mem.Allocator, p: *Planned, words: []const []const u8) !void {
    if (words.len == 0) return error.Usage;
    const verb = words[0];
    const rest = words[1..];
    p.id = "computer-use.agent";
    const action: []const u8 = if (std.mem.eql(u8, verb, "apps")) "list_apps"
        else if (std.mem.eql(u8, verb, "state")) "get_state"
        else if (std.mem.eql(u8, verb, "click")) "click"
        else if (std.mem.eql(u8, verb, "type")) "type"
        else if (std.mem.eql(u8, verb, "set")) "set_value"
        else if (std.mem.eql(u8, verb, "scroll")) "scroll"
        else if (std.mem.eql(u8, verb, "screenshot")) "screenshot"
        else return error.Usage;
    try p.args.append(gpa, .{ .key = "action", .value = action });
    if (std.mem.eql(u8, action, "list_apps")) return if (rest.len == 0) {} else error.Usage;
    if (rest.len == 0) return error.Usage;
    try p.args.append(gpa, .{ .key = "app", .value = rest[0] });
    if (std.mem.eql(u8, action, "get_state") or std.mem.eql(u8, action, "screenshot")) return if (rest.len == 1) {} else error.Usage;
    if (rest.len < 2) return error.Usage;
    try p.args.append(gpa, .{ .key = "index", .value = rest[1] });
    if (std.mem.eql(u8, action, "click")) return if (rest.len == 2) {} else error.Usage;
    if (std.mem.eql(u8, action, "scroll")) {
        if (rest.len > 3) return error.Usage;
        if (rest.len == 3) try p.args.append(gpa, .{ .key = "direction", .value = rest[2] });
        return;
    }
    if (rest.len < 3) return error.Usage;
    const key: []const u8 = if (std.mem.eql(u8, action, "type")) "text" else "value";
    try p.args.append(gpa, .{ .key = key, .value = try std.mem.join(gpa, " ", rest[2..]) });
}

/// The values plan() joined (notify, comment, a fill's text) are the
/// planner's to free.
pub fn freeJoined(gpa: std.mem.Allocator, sub: []const u8, p: *Planned) void {
    const joined_key: ?[]const u8 = if (std.mem.eql(u8, sub, "notify")) "text"
        else if (std.mem.eql(u8, sub, "worktree")) "comment"
        else if (std.mem.eql(u8, sub, "browser")) "text"
        else null;
    if (std.mem.eql(u8, sub, "computer")) {
        for (p.args.items) |a| if (std.mem.eql(u8, a.key, "text") or std.mem.eql(u8, a.key, "value")) gpa.free(a.value);
        return;
    }
    const key = joined_key orelse return;
    for (p.args.items) |a| if (std.mem.eql(u8, a.key, key)) gpa.free(a.value);
}

pub const usage =
    \\       cadex open <file>[:line]          (opens it in Cadex, beside this terminal)
    \\       cadex diff [file]                 (the diff of a file, or of the whole task)
    \\       cadex preview <url>               (opens the page in Cadex's preview)
    \\       cadex notify <text>               (a notification to the owner)
    \\       cadex worktree status <todo|doing|review|done> | comment <text>
    \\       cadex browser goto <url> | snapshot | click <ref> | fill <ref> <text> | press <key>
    \\                     | scroll [up|down|ref] | wait [selector] [seconds] | screenshot | console | notes
    \\       cadex computer apps | state <app> | click <app> <n> | type <app> <n> <text>
    \\                      | set <app> <n> <value> | scroll <app> <n> [up|down] | screenshot <app>
    \\       cadex commands | run <id> [key=value ...]   (add --json for the raw answer;
    \\                      spec-file=<file> sends the file's text as spec=)
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
    var fill = try plan(gpa, "browser", &.{ "fill", "@e4", "ana", "maria" });
    defer {
        freeJoined(gpa, "browser", &fill);
        fill.deinit(gpa);
    }
    try testing.expectEqualStrings("preview.agent", fill.id.?);
    try testing.expectEqualStrings("@e4", fill.args.items[1].value);
    try testing.expectEqualStrings("ana maria", fill.args.items[2].value);
    var snap = try plan(gpa, "browser", &.{"snapshot"});
    defer snap.deinit(gpa);
    try testing.expectEqual(@as(usize, 1), snap.args.items.len);
    try testing.expectError(error.Usage, plan(gpa, "browser", &.{"click"}));
    try testing.expectError(error.Usage, plan(gpa, "browser", &.{ "snapshot", "extra" }));
    var typed = try plan(gpa, "computer", &.{ "type", "TextEdit", "3", "hello", "there" });
    defer {
        freeJoined(gpa, "computer", &typed);
        typed.deinit(gpa);
    }
    try testing.expectEqualStrings("computer-use.agent", typed.id.?);
    try testing.expectEqualStrings("type", typed.args.items[0].value);
    try testing.expectEqualStrings("hello there", typed.args.items[3].value);
    var apps = try plan(gpa, "computer", &.{"apps"});
    defer apps.deinit(gpa);
    try testing.expectEqualStrings("list_apps", apps.args.items[0].value);
    try testing.expectError(error.Usage, plan(gpa, "computer", &.{ "click", "TextEdit" }));
    var list = try plan(gpa, "commands", &.{});
    defer list.deinit(gpa);
    try testing.expect(list.id == null);
}

test "spec-file= sends the file's text as spec=, read here; a folder or a missing file is refused" {
    const gpa = testing.allocator;
    var dir = try @import("../../shared/test_dir.zig").TestDir.init();
    defer dir.deinit();
    try dir.writeFile("spec.md", "fix it \"now\" $(rm -rf x)\nline 2");
    const path = try dir.join("spec.md");
    const arg = try std.fmt.allocPrint(gpa, "spec-file={s}", .{path});
    defer gpa.free(arg);
    var spawn = try plan(gpa, "run", &.{ "orchestration.spawn", "title=t", arg });
    defer spawn.deinit(gpa);
    try testing.expectEqualStrings("spec", spawn.args.items[1].key);
    try testing.expectEqualStrings("fix it \"now\" $(rm -rf x)\nline 2", spawn.args.items[1].value);
    const folder_arg = try std.fmt.allocPrint(gpa, "spec-file={s}", .{dir.path()});
    defer gpa.free(folder_arg);
    try testing.expectError(error.SpecFile, plan(gpa, "run", &.{ "orchestration.spawn", folder_arg }));
    try testing.expectError(error.SpecFile, plan(gpa, "run", &.{ "orchestration.spawn", "spec-file=/nope/none.md" }));
}

test "skills come from the binary" {
    try testing.expect(skills.find("cadex") != null);
}
