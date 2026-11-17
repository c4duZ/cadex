//! `cadex statusline`: the status line command of the session kit
//! (docs/adr/0021-cadex-managed-accounts.md). Claude Code hands it a JSON
//! with `rate_limits` (the account's 5 h and week windows, the numbers of
//! `/usage`), `context_window`, `cost` and `session_id` (tested with
//! 2.1.325, 2026-11-14). It keeps the account's `rate_limits` and the
//! session's context, cost and model in small files the app reads, then
//! prints the pane's one line of the Pane mockup (plan 28 phase C): the model,
//! the context with its bar, the cost and the folder. The account's own status
//! line (the multi-line one the mockup's "today" shows) is no longer called in
//! the sessions Cadex opens. No token is read anywhere: the usage comes from
//! Claude Code itself.

const std = @import("std");
const fs = @import("../../shared/fs.zig");

/// Where a call runs: the account's folder and where the usage files go.
pub const Env = struct {
    config_buf: fs.Buffer = undefined,
    config_len: usize = 0,
    usage_buf: fs.Buffer = undefined,
    usage_len: usize = 0,

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
        return make(config, usage);
    }

    pub fn make(config: []const u8, usage: []const u8) Env {
        var env: Env = .{};
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
        // The model too: the pane's header says it ("Opus", plan 28 phase B).
        out.session = try std.fmt.allocPrint(gpa, "{{\"at\":{d},\"config_dir\":{f},\"context_window\":{f},\"cost\":{f},\"model\":{f}}}\n", .{
            now,
            std.json.fmt(config_dir, .{}),
            std.json.fmt(root.get("context_window") orelse null_value, .{}),
            std.json.fmt(root.get("cost") orelse null_value, .{}),
            std.json.fmt(root.get("model") orelse null_value, .{}),
        });
        out.session_id = sid;
    }
    return out;
}

/// One call: write the usage, then the line. Errors are swallowed: a status
/// line must never disturb the session.
pub fn run(gpa: std.mem.Allocator, input: []const u8, env: Env) ![]u8 {
    const parsed = std.json.parseFromSlice(std.json.Value, gpa, input, .{}) catch return gpa.alloc(u8, 0);
    defer parsed.deinit();
    if (files(gpa, parsed.value, env.configDir(), unixSeconds())) |out| {
        defer out.deinit(gpa);
        save(env, out);
    } else |_| {}
    return line(gpa, parsed.value);
}

/// "Opus  context ━━━──────── 5%  US$ 0.31  orchestration-e": the Pane
/// mockup's line, in the ANSI colors the Cadex theme gives (37 the words, 97
/// the bar's part used, 90 the rest), two spaces apart. What Claude Code
/// leaves out is left out.
pub fn line(gpa: std.mem.Allocator, root: std.json.Value) ![]u8 {
    if (root != .object) return gpa.alloc(u8, 0);
    const o = root.object;
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    if (field(o, "model", "display_name")) |model| if (model == .string) try part(gpa, &out, model.string);
    if (contextPercent(o)) |pct| {
        const clamped = @min(@max(pct, 0), 100);
        const used: usize = @intFromFloat(clamped / 100 * bar_cells + 0.5);
        var cells: [bar_cells * 3]u8 = undefined;
        var n: usize = 0;
        for (0..bar_cells) |i| {
            const glyph = if (i < used) used_cell else free_cell;
            @memcpy(cells[n .. n + glyph.len], glyph);
            n += glyph.len;
        }
        const split = used * used_cell.len;
        var text: [160]u8 = undefined;
        try part(gpa, &out, std.fmt.bufPrint(&text, "context \x1b[97m{s}\x1b[90m{s}\x1b[37m {d:.0}%", .{ cells[0..split], cells[split..n], clamped }) catch "");
    }
    if (field(o, "cost", "total_cost_usd")) |cost| if (number(cost)) |usd| {
        var text: [32]u8 = undefined;
        try part(gpa, &out, std.fmt.bufPrint(&text, "US$ {d:.2}", .{usd}) catch "");
    };
    const dir = field(o, "workspace", "current_dir") orelse o.get("cwd");
    if (dir) |d| if (d == .string and d.string.len > 0) try part(gpa, &out, std.fs.path.basename(d.string));
    if (out.items.len > 0) try out.appendSlice(gpa, "\x1b[0m");
    return out.toOwnedSlice(gpa);
}

const bar_cells = 10;
const used_cell = "\u{2501}";
const free_cell = "\u{2500}";

/// One word or group of the line, two spaces after the one before, in 37.
fn part(gpa: std.mem.Allocator, out: *std.ArrayList(u8), text: []const u8) !void {
    if (text.len == 0) return;
    try out.appendSlice(gpa, if (out.items.len == 0) "\x1b[37m" else "  ");
    try out.appendSlice(gpa, text);
}

fn field(o: std.json.ObjectMap, object: []const u8, key: []const u8) ?std.json.Value {
    const inner = o.get(object) orelse return null;
    if (inner != .object) return null;
    return inner.object.get(key);
}

fn number(v: std.json.Value) ?f64 {
    return switch (v) {
        .integer => |i| @floatFromInt(i),
        .float => |f| f,
        else => null,
    };
}

/// The context used: Claude Code's percentage, else its tokens over the window's size.
fn contextPercent(o: std.json.ObjectMap) ?f64 {
    if (field(o, "context_window", "used_percentage")) |v| if (number(v)) |pct| return pct;
    const tokens = number(field(o, "context_window", "total_input_tokens") orelse return null) orelse return null;
    const size = number(field(o, "context_window", "context_window_size") orelse return null) orelse return null;
    return if (size > 0) tokens / size * 100 else null;
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
            const prefix = path[0..i];
            if (!fs.isDirectory(prefix)) fs.makeDirectory(prefix) catch {};
        }
    }
}

/// The owner's command through /bin/sh, with the same JSON on stdin and
/// CADEX_STATUSLINE set; 10 s at most, 64 KB of output kept.
const testing = std.testing;
const TestDir = @import("../../shared/test_dir.zig").TestDir;

const sample =
    \\{"session_id":"abc-123","transcript_path":"/x.jsonl",
    \\ "rate_limits":{"five_hour":{"used_percentage":42.5,"resets_at":1763100000},
    \\                "seven_day":{"used_percentage":10,"resets_at":1763500000}},
    \\ "context_window":{"total_input_tokens":1200},"cost":{"total_cost_usd":0.25},
    \\ "model":{"id":"claude-opus-5-5","display_name":"Opus"}}
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
    try testing.expect(std.mem.indexOf(u8, out.session.?, "\"display_name\":\"Opus\"") != null);
}

test "a JSON without rate_limits or with a strange id writes nothing for them" {
    var parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, "{\"session_id\":\"../etc\",\"cost\":{}}", .{});
    defer parsed.deinit();
    const out = try files(testing.allocator, parsed.value, "/a", 1);
    defer out.deinit(testing.allocator);
    try testing.expect(out.account == null and out.session == null);
}

test "run writes the usage files and prints the pane's line" {
    var dir = try TestDir.init();
    defer dir.deinit();
    try dir.makeDir("account");
    var config: fs.Buffer = undefined;
    var usage: fs.Buffer = undefined;
    const env = Env.make(try dir.joinInto(&config, "account"), try dir.joinInto(&usage, "usage/deep"));
    const printed = try run(testing.allocator, sample, env);
    defer testing.allocator.free(printed);
    try testing.expect(std.mem.startsWith(u8, printed, "\x1b[37mOpus  "));
    try testing.expect(std.mem.indexOf(u8, printed, "US$ 0.25") != null);

    var key: fs.Buffer = undefined;
    var name: fs.Buffer = undefined;
    const file_name = try std.fmt.bufPrint(&name, "usage/deep/{s}.json", .{accountKey(&key, env.configDir())});
    try testing.expect(fs.exists(try dir.join(file_name)));
    try testing.expect(fs.exists(try dir.join("usage/deep/sessions/abc-123.json")));
}

test "the line: model, context bar, cost and folder; what is missing is left out" {
    const json =
        \\{"model":{"display_name":"Opus"},"context_window":{"used_percentage":50},
        \\ "cost":{"total_cost_usd":0.312},"workspace":{"current_dir":"/r/cadex.worktrees/orchestration-e"}}
    ;
    var parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, json, .{});
    defer parsed.deinit();
    const text = try line(testing.allocator, parsed.value);
    defer testing.allocator.free(text);
    try testing.expectEqualStrings("\x1b[37mOpus  context \x1b[97m" ++ used_cell ** 5 ++ "\x1b[90m" ++ free_cell ** 5 ++
        "\x1b[37m 50%  US$ 0.31  orchestration-e\x1b[0m", text);
    var empty = try std.json.parseFromSlice(std.json.Value, testing.allocator, "{}", .{});
    defer empty.deinit();
    const none = try line(testing.allocator, empty.value);
    defer testing.allocator.free(none);
    try testing.expectEqual(@as(usize, 0), none.len);
}
