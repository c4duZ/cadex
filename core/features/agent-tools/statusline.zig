//! `cadex statusline`: the status line command of the session kit
//! (docs/adr/0021-cadex-managed-accounts.md). Claude Code hands it a JSON
//! with `rate_limits` (the account's 5 h and week windows, the numbers of
//! `/usage`), `context_window`, `cost` and `session_id` (tested with
//! 2.1.325, 2026-11-14). It keeps the account's `rate_limits` and the
//! session's context and cost in small files the app reads, then runs the
//! status line the owner already had in that account and prints its output.
//! No token is read anywhere: the usage comes from Claude Code itself.

const std = @import("std");
const fs = @import("../../shared/fs.zig");
const process = @import("../../shared/process.zig");

/// Where a call runs: the account's folder, where the usage files go, and
/// whether this call came from the owner's own command (then it does
/// nothing, so a status line that calls `cadex statusline` cannot loop).
pub const Env = struct {
    config_buf: fs.Buffer = undefined,
    config_len: usize = 0,
    usage_buf: fs.Buffer = undefined,
    usage_len: usize = 0,
    nested: bool = false,

    pub fn configDir(self: *const Env) []const u8 {
        return self.config_buf[0..self.config_len];
    }

    pub fn usageDir(self: *const Env) []const u8 {
        return self.usage_buf[0..self.usage_len];
    }

    /// CLAUDE_CONFIG_DIR, or ~/.claude for the default account (Claude
    /// Code's own rule); CADEX_USAGE_DIR, or Cadex's folder in Application
    /// Support. The app computes the same paths (AgentUsageFile.swift).
    pub fn fromProcess() Env {
        const home = getenv("HOME") orelse "/";
        var config_tmp: fs.Buffer = undefined;
        var usage_tmp: fs.Buffer = undefined;
        const config = getenv("CLAUDE_CONFIG_DIR") orelse
            (std.fmt.bufPrint(&config_tmp, "{s}/.claude", .{home}) catch "");
        const usage = getenv("CADEX_USAGE_DIR") orelse
            (std.fmt.bufPrint(&usage_tmp, "{s}/Library/Application Support/Cadex/usage", .{home}) catch "");
        return make(config, usage, getenv("CADEX_STATUSLINE") != null);
    }

    pub fn make(config: []const u8, usage: []const u8, nested: bool) Env {
        var env: Env = .{ .nested = nested };
        const c = std.mem.trimEnd(u8, config, "/");
        const u = std.mem.trimEnd(u8, usage, "/");
        if (c.len <= env.config_buf.len) {
            @memcpy(env.config_buf[0..c.len], c);
            env.config_len = c.len;
        }
        if (u.len <= env.usage_buf.len) {
            @memcpy(env.usage_buf[0..u.len], u);
            env.usage_len = u.len;
        }
        return env;
    }
};

fn getenv(name: [:0]const u8) ?[]const u8 {
    const value = std.c.getenv(name.ptr) orelse return null;
    const text = std.mem.span(value);
    return if (text.len == 0) null else text;
}

/// The file name of an account: its folder with every byte that is not an
/// ASCII letter or digit as "-" ("/Users/a/.claude-x" → "-Users-a--claude-x").
pub fn accountKey(out: []u8, dir: []const u8) []const u8 {
    const n = @min(out.len, dir.len);
    for (dir[0..n], out[0..n]) |byte, *slot| slot.* = if (std.ascii.isAlphanumeric(byte)) byte else '-';
    return out[0..n];
}

/// A session id safe as a file name; null for anything else.
fn safeId(id: []const u8) ?[]const u8 {
    if (id.len == 0 or id.len > 128) return null;
    for (id) |byte| if (!std.ascii.isAlphanumeric(byte) and byte != '-' and byte != '_') return null;
    return id;
}

/// What a call writes: the account's file (when the JSON has
/// `rate_limits`) and the session's (when it has a usable `session_id`).
pub const Files = struct {
    account: ?[]u8 = null,
    session: ?[]u8 = null,
    session_id: ?[]const u8 = null,

    pub fn deinit(self: Files, gpa: std.mem.Allocator) void {
        if (self.account) |a| gpa.free(a);
        if (self.session) |s| gpa.free(s);
    }
};

/// The two files' contents for one status line call; `input` must outlive
/// the result (session_id points into it through `parsed`).
pub fn files(gpa: std.mem.Allocator, parsed: std.json.Value, config_dir: []const u8, now: i64) !Files {
    var out: Files = .{};
    errdefer out.deinit(gpa);
    if (parsed != .object) return out;
    const root = parsed.object;
    if (root.get("rate_limits")) |limits| if (limits == .object) {
        out.account = try std.fmt.allocPrint(gpa, "{{\"at\":{d},\"config_dir\":{f},\"rate_limits\":{f}}}\n", .{
            now, std.json.fmt(config_dir, .{}), std.json.fmt(limits, .{}),
        });
    };
    const id = if (root.get("session_id")) |v| (if (v == .string) safeId(v.string) else null) else null;
    if (id) |sid| {
        const null_value: std.json.Value = .null;
        out.session = try std.fmt.allocPrint(gpa, "{{\"at\":{d},\"config_dir\":{f},\"context_window\":{f},\"cost\":{f}}}\n", .{
            now,
            std.json.fmt(config_dir, .{}),
            std.json.fmt(root.get("context_window") orelse null_value, .{}),
            std.json.fmt(root.get("cost") orelse null_value, .{}),
        });
        out.session_id = sid;
    }
    return out;
}

/// The owner's status line command in the account's settings.json
/// (`statusLine.command`), or null. The kit's `--settings` replaces it in
/// the session (tested 2026-11-14), so this program calls it.
pub fn ownerCommand(gpa: std.mem.Allocator, settings: []const u8) !?[]u8 {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, settings, .{}) catch return null;
    defer parsed.deinit();
    if (parsed.value != .object) return null;
    const line = parsed.value.object.get("statusLine") orelse return null;
    if (line != .object) return null;
    const command = line.object.get("command") orelse return null;
    if (command != .string or command.string.len == 0) return null;
    return try gpa.dupe(u8, command.string);
}

/// One call: write the usage first (so a broken or slow owner command
/// cannot lose it), then print what the owner's command prints. Errors are
/// swallowed: a status line must never disturb the session.
pub fn run(gpa: std.mem.Allocator, input: []const u8, env: Env) ![]u8 {
    if (env.nested) return gpa.alloc(u8, 0);
    if (std.json.parseFromSlice(std.json.Value, gpa, input, .{})) |parsed| {
        defer parsed.deinit();
        const now = unixSeconds();
        if (files(gpa, parsed.value, env.configDir(), now)) |out| {
            defer out.deinit(gpa);
            save(env, out);
        } else |_| {}
    } else |_| {}
    return owner(gpa, input, env);
}

extern "c" fn time(t: ?*c_long) c_long;

/// Seconds since 1970 from libc: Zig 0.16 moved its clock into std.Io.
fn unixSeconds() i64 {
    return time(null);
}

fn save(env: Env, out: Files) void {
    if (env.usage_len == 0) return;
    var key_buf: fs.Buffer = undefined;
    var path: fs.Buffer = undefined;
    var tmp: fs.Buffer = undefined;
    const pid = fs.processId();
    if (out.account) |data| {
        makeDirs(env.usageDir());
        const key = accountKey(&key_buf, env.configDir());
        const p = std.fmt.bufPrint(&path, "{s}/{s}.json", .{ env.usageDir(), key }) catch return;
        const t = std.fmt.bufPrint(&tmp, "{s}.{d}.tmp", .{ p, pid }) catch return;
        fs.writeThenRename(t, p, data, 0o644) catch {};
    }
    if (out.session) |data| {
        var dir: fs.Buffer = undefined;
        const d = std.fmt.bufPrint(&dir, "{s}/sessions", .{env.usageDir()}) catch return;
        makeDirs(d);
        const p = std.fmt.bufPrint(&path, "{s}/{s}.json", .{ d, out.session_id.? }) catch return;
        const t = std.fmt.bufPrint(&tmp, "{s}.{d}.tmp", .{ p, pid }) catch return;
        fs.writeThenRename(t, p, data, 0o644) catch {};
    }
}

/// mkdir -p.
fn makeDirs(path: []const u8) void {
    if (fs.isDirectory(path)) return;
    var i: usize = 1;
    while (i <= path.len) : (i += 1) {
        if (i == path.len or path[i] == '/') {
            const part = path[0..i];
            if (!fs.isDirectory(part)) fs.makeDirectory(part) catch {};
        }
    }
}

/// The owner's command through /bin/sh, with the same JSON on stdin and
/// CADEX_STATUSLINE set; 10 s at most, 64 KB of output kept.
fn owner(gpa: std.mem.Allocator, input: []const u8, env: Env) ![]u8 {
    var path: fs.Buffer = undefined;
    const settings_path = std.fmt.bufPrint(&path, "{s}/settings.json", .{env.configDir()}) catch return gpa.alloc(u8, 0);
    const file = fs.File.openRead(settings_path, .{}) catch return gpa.alloc(u8, 0);
    defer file.close();
    var settings: std.ArrayList(u8) = .empty;
    defer settings.deinit(gpa);
    try fs.appendUpTo(gpa, file, &settings, 1024 * 1024);
    const command = (try ownerCommand(gpa, settings.items)) orelse return gpa.alloc(u8, 0);
    defer gpa.free(command);
    var result = try process.run(gpa, &.{ "/bin/sh", "-c", command }, .{
        .stdin = input,
        .env = &.{"CADEX_STATUSLINE=1"},
        .timeout_ms = 10_000,
        .max_output = 64 * 1024,
    });
    gpa.free(result.stderr);
    result.stderr = &.{};
    return result.stdout;
}

const testing = std.testing;
const TestDir = @import("../../shared/test_dir.zig").TestDir;

const sample =
    \\{"session_id":"abc-123","transcript_path":"/x.jsonl",
    \\ "rate_limits":{"five_hour":{"used_percentage":42.5,"resets_at":1763100000},
    \\                "seven_day":{"used_percentage":10,"resets_at":1763500000}},
    \\ "context_window":{"total_input_tokens":1200},"cost":{"total_cost_usd":0.25}}
;

test "account key replaces every non-alphanumeric byte" {
    var buf: [64]u8 = undefined;
    try testing.expectEqualStrings("-Users-a--claude-x", accountKey(&buf, "/Users/a/.claude-x"));
    // Per byte: "é" is two bytes in UTF-8, so two dashes (the app does the same).
    try testing.expectEqualStrings("-Users-a-My-Acct---", accountKey(&buf, "/Users/a/My Acct_é"));
}

test "files keep rate_limits per account and context and cost per session" {
    var parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, sample, .{});
    defer parsed.deinit();
    const out = try files(testing.allocator, parsed.value, "/Users/a/.claude", 100);
    defer out.deinit(testing.allocator);
    try testing.expectEqualStrings(
        "{\"at\":100,\"config_dir\":\"/Users/a/.claude\",\"rate_limits\":{\"five_hour\":{\"used_percentage\":42.5,\"resets_at\":1763100000},\"seven_day\":{\"used_percentage\":10,\"resets_at\":1763500000}}}\n",
        out.account.?,
    );
    try testing.expectEqualStrings("abc-123", out.session_id.?);
    try testing.expect(std.mem.indexOf(u8, out.session.?, "\"total_cost_usd\":0.25") != null);
}

test "a JSON without rate_limits or with a strange id writes nothing for them" {
    var parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, "{\"session_id\":\"../etc\",\"cost\":{}}", .{});
    defer parsed.deinit();
    const out = try files(testing.allocator, parsed.value, "/a", 1);
    defer out.deinit(testing.allocator);
    try testing.expect(out.account == null and out.session == null);
}

test "owner command comes from statusLine.command" {
    const cmd = (try ownerCommand(testing.allocator, "{\"statusLine\":{\"type\":\"command\",\"command\":\"echo hi\"}}")).?;
    defer testing.allocator.free(cmd);
    try testing.expectEqualStrings("echo hi", cmd);
    try testing.expect((try ownerCommand(testing.allocator, "{\"statusLine\":3}")) == null);
    try testing.expect((try ownerCommand(testing.allocator, "not json")) == null);
}

test "run writes the usage files and prints the owner's status line" {
    var dir = try TestDir.init();
    defer dir.deinit();
    try dir.makeDir("account");
    var settings_path: fs.Buffer = undefined;
    const sp = try dir.joinInto(&settings_path, "account/settings.json");
    try fs.writeThenRename(try dir.join("s.tmp"), sp, "{\"statusLine\":{\"type\":\"command\",\"command\":\"head -c 14\"}}", 0o644);

    var config: fs.Buffer = undefined;
    var usage: fs.Buffer = undefined;
    const env = Env.make(try dir.joinInto(&config, "account"), try dir.joinInto(&usage, "usage/deep"), false);
    const printed = try run(testing.allocator, sample, env);
    defer testing.allocator.free(printed);
    try testing.expectEqualStrings("{\"session_id\":", printed);

    var key: fs.Buffer = undefined;
    var name: fs.Buffer = undefined;
    const file_name = try std.fmt.bufPrint(&name, "usage/deep/{s}.json", .{accountKey(&key, env.configDir())});
    try testing.expect(fs.exists(try dir.join(file_name)));
    try testing.expect(fs.exists(try dir.join("usage/deep/sessions/abc-123.json")));
}

test "a nested call does nothing" {
    const env = Env.make("/nowhere", "/nowhere/usage", true);
    const printed = try run(testing.allocator, sample, env);
    defer testing.allocator.free(printed);
    try testing.expectEqual(@as(usize, 0), printed.len);
}
