//! The `cadex` command line: the subcommand picks the work. Kept to libc
//! reads and writes so each call stays small; Claude Code runs the status
//! line after every message.

const std = @import("std");
const statusline = @import("statusline.zig");
const hook = @import("hook.zig");
const agent = @import("agent.zig");
const claude_wrap = @import("claude_wrap.zig");
const continue_wrap = @import("continue_wrap.zig");
// The memory's hook (plan 22): the memory feature's entry, the only code
// that talks to the engine's socket.
const memory = @import("../memory/memory.zig");

const usage_text =
    \\usage: cadex statusline       (Claude Code's status line, from a session Cadex opened)
    \\       cadex hook <event>     (a Claude Code hook: tells the Cadex app, never waits)
    \\       cadex memory-hook <event> (a Claude Code hook: feeds the project memory)
    \\       cadex mcp              (the MCP server of the sessions Cadex opens)
    \\       cadex claude [args…]   (the `claude` typed in a Cadex zsh tab: the session kit)
    \\       cadex continue [options] [agent] [args…] (ai-memory run: the agent in the project's workstream, with the kit)
    \\
++ @import("commands.zig").usage;

pub fn main(init: std.process.Init.Minimal) u8 {
    var args = init.args.iterate();
    _ = args.next();
    const sub = args.next() orelse return fail(usage_text);
    if (std.mem.eql(u8, sub, "statusline")) return runStatusline();
    if (std.mem.eql(u8, sub, "hook")) return runHook(args.next() orelse return fail(usage_text), hook.run);
    if (std.mem.eql(u8, sub, "memory-hook")) return runHook(args.next() orelse return fail(usage_text), memory.hook.run);
    if (std.mem.eql(u8, sub, "claude")) return runClaude(&args);
    if (std.mem.eql(u8, sub, "continue")) return runContinue(&args);
    // The agent's subcommands (plan 20): every word after the subcommand.
    var words_buf: [64][]const u8 = undefined;
    var n: usize = 0;
    while (args.next()) |word| : (n += 1) {
        if (n == words_buf.len) return fail(usage_text);
        words_buf[n] = word;
    }
    return agent.main(sub, words_buf[0..n], usage_text);
}

/// Every word after `claude`, however many (a prompt may be long): the
/// process becomes `claude`, so nothing here is freed.
fn runClaude(args: anytype) u8 {
    var words: std.ArrayList([:0]const u8) = .empty;
    while (args.next()) |word| words.append(std.heap.page_allocator, word) catch return claude_wrap.run(&.{});
    return claude_wrap.run(words.items);
}

/// Every word after `continue`; the process becomes `cadex-memory run`.
fn runContinue(args: anytype) u8 {
    var words: std.ArrayList([:0]const u8) = .empty;
    while (args.next()) |word| words.append(std.heap.page_allocator, word) catch return continue_wrap.run(&.{});
    return continue_wrap.run(words.items);
}

const HookRun = *const fn (std.mem.Allocator, []const u8, []const u8) anyerror!?[]u8;

/// Both hooks: stdin in, what they print out, exit 0 whatever happens.
fn runHook(event: []const u8, run: HookRun) u8 {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();
    const input = readStdin(gpa) catch return 0;
    defer gpa.free(input);
    const out = (run(gpa, event, input) catch return 0) orelse return 0;
    defer gpa.free(out);
    writeAll(1, out);
    return 0;
}

fn runStatusline() u8 {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();
    const input = readStdin(gpa) catch return 0;
    defer gpa.free(input);
    const out = statusline.run(gpa, input, statusline.Env.fromProcess()) catch return 0;
    defer gpa.free(out);
    writeAll(1, out);
    return 0;
}

/// The JSON Claude Code sends; a few KB, capped at 1 MB so a runaway pipe
/// cannot grow the process.
fn readStdin(gpa: std.mem.Allocator) ![]u8 {
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(gpa);
    var buf: [16 * 1024]u8 = undefined;
    while (list.items.len < 1024 * 1024) {
        const n = std.c.read(0, &buf, buf.len);
        if (n < 0) {
            if (std.c.errno(n) == .INTR) continue;
            break;
        }
        if (n == 0) break;
        try list.appendSlice(gpa, buf[0..@intCast(n)]);
    }
    return list.toOwnedSlice(gpa);
}

fn writeAll(fd: std.c.fd_t, data: []const u8) void {
    var at: usize = 0;
    while (at < data.len) {
        const n = std.c.write(fd, data[at..].ptr, data.len - at);
        if (n < 0) {
            if (std.c.errno(n) == .INTR) continue;
            return;
        }
        at += @intCast(n);
    }
}

fn fail(text: []const u8) u8 {
    writeAll(2, text);
    return 2;
}

test "unknown subcommand prints usage" {
    try std.testing.expect(std.mem.startsWith(u8, usage_text, "usage: cadex statusline"));
}
