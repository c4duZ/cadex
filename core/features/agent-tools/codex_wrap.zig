//! `cadex codex`: Codex with the owner's words as its first prompt, read from a file Cadex wrote
//! (`--cadex-prompt-file`, the same rules as `cadex claude`: only Cadex's prompts folder, only
//! this user's file, removed once read), so the words never go through a shell command
//! (docs/adr/0033-cadex-launches-agents.md; plan 29: Codex in the New Task sheet and in races).
//! No session kit: Codex has no hooks or status line Cadex reads. The process becomes `codex`.

const std = @import("std");
const prompt_file = @import("prompt_file.zig");
const claude_wrap = @import("claude_wrap.zig");

extern "c" fn execve(path: [*:0]const u8, argv: [*:null]const ?[*:0]const u8, envp: [*:null]const ?[*:0]const u8) c_int;
extern "c" var environ: [*:null]?[*:0]u8;

/// The whole command. Returns only when `codex` could not be run.
pub fn run(words: []const [:0]const u8) u8 {
    var arena_state: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var real_buf: [claude_wrap.path_max]u8 = undefined;
    const real = claude_wrap.findReal(arena, &real_buf, "codex", "CADEX_CODEX_BIN") orelse return say("cadex codex: codex is not on PATH\n");
    const taken = prompt_file.take(arena, words) catch return exec(arena, real, words, null);
    var prompt: ?[:0]const u8 = null;
    if (taken.path) |given| {
        const dir = prompt_file.folder(arena) orelse return say("cadex codex: the prompt file is not one Cadex wrote\n");
        prompt = prompt_file.read(arena, dir, given) orelse return say("cadex codex: the prompt file is not one Cadex wrote\n");
    }
    return exec(arena, real, taken.words, prompt);
}

fn exec(arena: std.mem.Allocator, real: [:0]const u8, words: []const [:0]const u8, prompt: ?[:0]const u8) u8 {
    const argv = argvFor(arena, words, prompt) catch return 127;
    _ = execve(real.ptr, argv.ptr, @ptrCast(environ));
    return say("cadex codex: codex did not start\n");
}

/// argv: "codex", the owner's words, then "--" and the prompt (one word), as `cadex claude` does.
fn argvFor(arena: std.mem.Allocator, words: []const [:0]const u8, prompt: ?[:0]const u8) ![:null]?[*:0]const u8 {
    var argv: std.ArrayList(?[*:0]const u8) = .empty;
    try argv.append(arena, "codex");
    var ended = false;
    for (words) |word| {
        if (std.mem.eql(u8, word, "--")) ended = true;
        try argv.append(arena, word.ptr);
    }
    if (prompt) |text| {
        if (!ended) try argv.append(arena, "--");
        try argv.append(arena, text.ptr);
    }
    return argv.toOwnedSliceSentinel(arena, null);
}

fn say(text: []const u8) u8 {
    _ = std.c.write(2, text.ptr, text.len);
    return 127;
}

const testing = std.testing;

test "codex gets the owner's words, then \"--\" and the prompt" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const words = [_][:0]const u8{ "-m", "gpt-5", "--dangerously-bypass-approvals-and-sandbox" };
    const argv = try argvFor(arena, &words, "fix the login");
    try testing.expectEqual(@as(usize, 6), argv.len);
    try testing.expectEqualStrings("--", std.mem.span(argv[4].?));
    try testing.expectEqualStrings("fix the login", std.mem.span(argv[5].?));
    const plain = try argvFor(arena, &words, null);
    try testing.expectEqual(@as(usize, 4), plain.len);
}
