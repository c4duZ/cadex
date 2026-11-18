//! `cadex continue [run options] [agent] [args…]`: an agent in the
//! project's workstream (plan 22 phase E), the launcher `cadex-memory run`
//! (upstream ai-memory's `ai-memory run`, same options and agents) with this
//! tab's session kit. What the "Continue in…" command types in a Cadex tab;
//! the owner may type it too. The words go to the launcher untouched: it
//! parses the options and picks the agent (or the newest session's when none
//! is named), so nothing here has to know them.
//!
//! Like `cadex claude`, it asks the app for the kit over app.sock (the app
//! checks that this process is under one of its terminals' shells). The
//! kit's settings file holds the session token and the memory's
//! environment; those go into this process's environment, which
//! `cadex-memory run` reads, and:
//! the launcher gets two sets of kit words and appends the one of the agent
//! it runs (`--claude-kit-arg`, `--codex-kit-arg`):
//! - Claude: the kit's words (`--settings`, `--plugin-dir`, `--mcp-config`);
//! - Codex: only the memory's MCP server by `-c mcp_servers.cadex…`, with
//!   the token in its env (Codex 0.149.1 takes `-c` and adds it to the
//!   owner's servers, measured 2026-11-15). Codex hooks need a CODEX_HOME of
//!   Cadex's with their trust recorded; until then a Codex run is captured
//!   by the launcher's transcript import at its end;
//! - the other agents: none (Cadex writes nothing into their configuration;
//!   the launcher imports their conversation at the end).

const std = @import("std");
const claude_wrap = @import("claude_wrap.zig");

extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
extern "c" fn unsetenv(name: [*:0]const u8) c_int;
extern "c" fn execve(path: [*:0]const u8, argv: [*:null]const ?[*:0]const u8, envp: [*:null]const ?[*:0]const u8) c_int;
extern "c" fn _NSGetExecutablePath(buf: [*]u8, size: *u32) c_int;
extern "c" var environ: [*:null]?[*:0]u8;

/// The environment the memory's tools and launcher read, as the kit wrote
/// it in the session's settings (`env`); the MCP server of a Codex run gets
/// the same.
const memory_env = [_][]const u8{
    "CADEX_SESSION_TOKEN", "CADEX_MEMORY_BIN",  "CADEX_MEMORY_DIR",       "CADEX_MEMORY_SOCKET",
    "CADEX_SESSIONS_DIR",  "CADEX_APP_SOCKET",  "CADEX_MEMORY_WORKSPACE",
};

/// The value after `--settings` in the kit's words.
pub fn settingsPath(args: []const []const u8) ?[]const u8 {
    for (args, 0..) |arg, i| if (std.mem.eql(u8, arg, "--settings") and i + 1 < args.len) return args[i + 1];
    return null;
}

/// The `env` of the kit's settings JSON, only the names in `memory_env`.
pub fn memoryEnv(arena: std.mem.Allocator, settings_json: []const u8) ![]const [2][]const u8 {
    const parsed = try std.json.parseFromSliceLeaky(std.json.Value, arena, settings_json, .{});
    const env = if (parsed == .object) parsed.object.get("env") else null;
    var out: std.ArrayList([2][]const u8) = .empty;
    const object = if (env) |e| (if (e == .object) e.object else return out.items) else return out.items;
    for (memory_env) |name| if (object.get(name)) |v| if (v == .string) try out.append(arena, .{ name, v.string });
    return out.items;
}

/// Codex's `-c` words for the memory's MCP server: `cadex mcp` with the
/// session's memory environment, as TOML values (JSON string escapes are
/// valid TOML basic-string escapes).
pub fn codexArgs(arena: std.mem.Allocator, cadex: []const u8, env: []const [2][]const u8) ![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    try out.append(arena, "-c");
    try out.append(arena, try std.fmt.allocPrint(arena, "mcp_servers.cadex.command={f}", .{std.json.fmt(cadex, .{})}));
    try out.append(arena, "-c");
    try out.append(arena, "mcp_servers.cadex.args=[\"mcp\"]");
    var table: std.ArrayList(u8) = .empty;
    try table.appendSlice(arena, "mcp_servers.cadex.env={");
    for (env, 0..) |pair, i| {
        if (i > 0) try table.append(arena, ',');
        try table.print(arena, "{s}={f}", .{ pair[0], std.json.fmt(pair[1], .{}) });
    }
    try table.append(arena, '}');
    try out.append(arena, "-c");
    try out.append(arena, table.items);
    return out.items;
}

/// The whole command. Returns only when the launcher could not be run.
pub fn run(words: []const [:0]const u8) u8 {
    var arena_state: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const asked = toSlices(arena, words) catch return 127;
    const kit = claude_wrap.kitFor(arena, null, asked) orelse return say("cadex continue: run it in a Cadex terminal with the app open\n");
    for (kit.unset) |name| _ = unsetenv((arena.dupeZ(u8, name) catch continue).ptr);
    // The project's or the active account when the tab has none (plan 33 F), as `cadex claude`.
    if (kit.config_dir) |dir| {
        if (std.c.getenv("CLAUDE_CONFIG_DIR") == null) _ = setenv((arena.dupeZ(u8, "CLAUDE_CONFIG_DIR") catch return 127).ptr, (arena.dupeZ(u8, dir) catch return 127).ptr, 1);
    }
    const settings = settingsPath(kit.args) orelse return say("cadex continue: the app sent no session settings\n");
    const text = readFile(arena, settings) orelse return say("cadex continue: the session settings do not read\n");
    const env = memoryEnv(arena, text) catch return say("cadex continue: the session settings do not read\n");
    var bin: ?[]const u8 = null;
    for (env) |pair| {
        _ = setenv((arena.dupeZ(u8, pair[0]) catch return 127).ptr, (arena.dupeZ(u8, pair[1]) catch return 127).ptr, 1);
        if (std.mem.eql(u8, pair[0], "CADEX_MEMORY_BIN")) bin = pair[1];
    }
    const engine = bin orelse return say("cadex continue: the project memory is off (Settings > Memory)\n");
    const codex = codexArgs(arena, selfPath(arena) orelse return 127, env) catch return 127;
    const head = launcherArgs(arena, kit.args, codex) catch return 127;
    var argv: std.ArrayList(?[*:0]const u8) = .empty;
    const engine_z = arena.dupeZ(u8, engine) catch return 127;
    argv.append(arena, engine_z.ptr) catch return 127;
    for (head) |w| argv.append(arena, (arena.dupeZ(u8, w) catch return 127).ptr) catch return 127;
    for (words) |w| argv.append(arena, w.ptr) catch return 127;
    const list = argv.toOwnedSliceSentinel(arena, null) catch return 127;
    _ = execve(engine_z.ptr, list.ptr, @ptrCast(environ));
    return say("cadex continue: cadex-memory did not start\n");
}

/// `run`, then each kit word after the flag of its agent's set.
pub fn launcherArgs(arena: std.mem.Allocator, claude: []const []const u8, codex: []const []const u8) ![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    try out.append(arena, "run");
    for (claude) |w| try out.appendSlice(arena, &.{ "--claude-kit-arg", w });
    for (codex) |w| try out.appendSlice(arena, &.{ "--codex-kit-arg", w });
    return out.items;
}

fn selfPath(arena: std.mem.Allocator) ?[]const u8 {
    var raw: [1024]u8 = undefined;
    var size: u32 = raw.len;
    if (_NSGetExecutablePath(&raw, &size) != 0) return null;
    return arena.dupe(u8, std.mem.sliceTo(&raw, 0)) catch null;
}

fn readFile(arena: std.mem.Allocator, path: []const u8) ?[]const u8 {
    const z = arena.dupeZ(u8, path) catch return null;
    const fd = std.c.open(z.ptr, .{ .ACCMODE = .RDONLY });
    if (fd < 0) return null;
    defer _ = std.c.close(fd);
    var out: std.ArrayList(u8) = .empty;
    var buf: [16 * 1024]u8 = undefined;
    while (out.items.len < 1024 * 1024) {
        const n = std.c.read(fd, &buf, buf.len);
        if (n <= 0) break;
        out.appendSlice(arena, buf[0..@intCast(n)]) catch return null;
    }
    return out.items;
}

fn toSlices(arena: std.mem.Allocator, words: []const [:0]const u8) ![]const []const u8 {
    const out = try arena.alloc([]const u8, words.len);
    for (words, out) |w, *o| o.* = w;
    return out;
}

fn say(text: []const u8) u8 {
    _ = std.c.write(2, text.ptr, text.len);
    return 127;
}

const testing = std.testing;

test "the kit's settings give the memory's environment, and Codex gets the MCP server by -c" {
    var arena_state: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    try testing.expectEqualStrings("/k/s.json", settingsPath(&.{ "--plugin-dir", "/p", "--settings", "/k/s.json" }).?);
    try testing.expect(settingsPath(&.{"--settings"}) == null);
    const env = try memoryEnv(arena, "{\"env\":{\"CADEX_SESSION_TOKEN\":\"t\",\"CADEX_MEMORY_BIN\":\"/b/cadex-memory\",\"OTHER\":\"x\"},\"hooks\":{}}");
    try testing.expectEqual(@as(usize, 2), env.len);
    try testing.expectEqualStrings("CADEX_SESSION_TOKEN", env[0][0]);
    const args = try codexArgs(arena, "/A B/cadex", env);
    try testing.expectEqualStrings("mcp_servers.cadex.command=\"/A B/cadex\"", args[1]);
    try testing.expectEqualStrings("mcp_servers.cadex.args=[\"mcp\"]", args[3]);
    try testing.expectEqualStrings("mcp_servers.cadex.env={CADEX_SESSION_TOKEN=\"t\",CADEX_MEMORY_BIN=\"/b/cadex-memory\"}", args[5]);
    const head = try launcherArgs(arena, &.{ "--settings", "/k/s.json" }, args[0..2]);
    try testing.expectEqualStrings("run", head[0]);
    try testing.expectEqualStrings("--claude-kit-arg", head[1]);
    try testing.expectEqualStrings("/k/s.json", head[4]);
    try testing.expectEqualStrings("--codex-kit-arg", head[5]);
    try testing.expectEqual(@as(usize, 9), head.len);
}
