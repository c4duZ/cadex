//! The agent's side of `cadex` (docs/spec/agent-tools.md, plan 20): the
//! subcommands that ask the app (commands.zig, request.zig), `skills`
//! (from the binary) and `mcp` (the server loop). Exit 0 when done, 1 when
//! the app refused or is not there (with the reason on stderr), 2 on usage.

const std = @import("std");
const commands = @import("commands.zig");
const request = @import("request.zig");
const skills = @import("skills.zig");
const mcp = @import("mcp.zig");
const memory = @import("../memory/memory.zig");

/// The memory's side of the MCP server, set up once in `serve`.
var memory_proxy: memory.mcp.Proxy = undefined;

fn memoryList(gpa: std.mem.Allocator) anyerror!?[]u8 {
    return memory_proxy.listTools(gpa);
}

fn memoryCall(gpa: std.mem.Allocator, message: []const u8) anyerror!?[]u8 {
    return memory_proxy.call(gpa, message);
}

pub fn main(sub: []const u8, all_words: []const []const u8, usage_text: []const u8) u8 {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();
    if (std.mem.eql(u8, sub, "mcp")) return serve(gpa);
    if (std.mem.eql(u8, sub, "skills")) return runSkills(gpa, all_words, usage_text);
    // --json anywhere prints the app's answer as it came.
    var words_buf: [64][]const u8 = undefined;
    var n: usize = 0;
    var json = false;
    for (all_words) |word| {
        if (std.mem.eql(u8, word, "--json")) {
            json = true;
        } else {
            words_buf[n] = word;
            n += 1;
        }
    }
    var p = commands.plan(gpa, sub, words_buf[0..n]) catch |err| return switch (err) {
        error.SpecFile => say(1, "cadex: spec-file= must be a readable file of at most 100 KB, without NUL\n"),
        else => say(2, usage_text),
    };
    defer {
        commands.freeJoined(gpa, sub, &p);
        p.deinit(gpa);
    }
    const reply = request.send(gpa, p.id, p.args.items) catch |err| return say(1, switch (err) {
        error.NoToken => "cadex: not a session opened by Cadex\n",
        error.NotRunning => "cadex: Cadex is not running\n",
        else => "cadex: the request failed\n",
    });
    defer reply.deinit(gpa);
    const text = if (json) reply.raw else reply.text;
    writeAll(if (reply.ok or json) 1 else 2, text);
    if (text.len > 0 and text[text.len - 1] != '\n') writeAll(if (reply.ok or json) 1 else 2, "\n");
    return if (reply.ok) 0 else 1;
}

fn runSkills(gpa: std.mem.Allocator, words: []const []const u8, usage_text: []const u8) u8 {
    if (words.len == 1 and std.mem.eql(u8, words[0], "list")) {
        const text = skills.list(gpa) catch return 1;
        defer gpa.free(text);
        writeAll(1, text);
        return 0;
    }
    if (words.len == 2 and std.mem.eql(u8, words[0], "get")) {
        const topic = skills.find(words[1]) orelse return say(1, "cadex: no such topic (cadex skills list)\n");
        writeAll(1, topic.text);
        return 0;
    }
    return say(2, usage_text);
}

/// The MCP loop: a message per line in, its answer per line out, until
/// stdin closes.
fn serve(gpa: std.mem.Allocator) u8 {
    // The engine this process may start is its child: children reap
    // themselves, nothing here waits for one (plan 22 phase D).
    const mem: ?mcp.Memory = if (memory_proxy.init()) blk: {
        const ignore: std.c.Sigaction = .{ .handler = .{ .handler = std.c.SIG.IGN }, .mask = std.mem.zeroes(std.c.sigset_t), .flags = 0 };
        _ = std.c.sigaction(std.c.SIG.CHLD, &ignore, null);
        break :blk .{ .list = memoryList, .call = memoryCall };
    } else null;
    var pending: std.ArrayList(u8) = .empty;
    defer pending.deinit(gpa);
    var buf: [64 * 1024]u8 = undefined;
    while (true) {
        const n = std.c.read(0, &buf, buf.len);
        if (n < 0 and std.c.errno(n) == .INTR) continue;
        if (n <= 0) return 0;
        pending.appendSlice(gpa, buf[0..@intCast(n)]) catch return 1;
        while (std.mem.indexOfScalar(u8, pending.items, '\n')) |end| {
            const message = std.mem.trim(u8, pending.items[0..end], " \r\t");
            if (message.len > 0) {
                if (mcp.handleWith(gpa, message, request.sendCommand, mem) catch null) |answer| {
                    defer gpa.free(answer);
                    writeAll(1, answer);
                }
            }
            const left = pending.items.len - end - 1;
            std.mem.copyForwards(u8, pending.items[0..left], pending.items[end + 1 ..]);
            pending.shrinkRetainingCapacity(left);
        }
    }
}

fn say(code: u8, text: []const u8) u8 {
    writeAll(2, text);
    return code;
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

test {
    _ = commands;
    _ = request;
    _ = skills;
    _ = mcp;
}
