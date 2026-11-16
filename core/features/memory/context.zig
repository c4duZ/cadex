//! What the memory hands back to the session besides the startup briefing,
//! as upstream's own hook client does (crates/ai-memory-cli/src/commands/
//! hook.rs at fa0ec25, plan 22 phase D, 2026-11-16):
//! - after a compaction (SessionStart `source: "compact"`), the session's
//!   anchor from `GET /recap?mode=anchor` instead of the briefing: a
//!   compaction is not a new session, and fetching `/handoff` would claim a
//!   baton mid-session. Not in a subagent (`agent_id` set): the anchor quotes
//!   the session's own prompts.
//! - a prompt that opens with "reload context": the recap of the window the
//!   last compaction dropped (`GET /recap`), next to the prompt.
//! - SubagentStart: the project brief from `GET /brief`, which the engine
//!   gives only when the repository's `.ai-memory.toml` asks for it
//!   (`[briefing] inject_on_subagent_start`).

const std = @import("std");

/// The first line of a real anchor (`ANCHOR_HEADER_PREFIX` in upstream's
/// compaction_recap.rs). An unknown session gets a notice that does not
/// start with it, and that is not injected.
pub const anchor_header = "> \u{1F9ED} ai-memory: post-compaction anchor for this session";

/// The anchor's size (upstream's `ANCHOR_BUDGET`): a compaction already left
/// the context tight.
pub const anchor_budget = 2000;

const reload_phrase = "reload context";

/// Whether the prompt opens with "reload context" as whole words, ASCII case
/// ignored, after leading whitespace (upstream's `is_reload_request`).
pub fn isReloadRequest(prompt: []const u8) bool {
    const rest = std.mem.trimStart(u8, prompt, " \t\r\n");
    if (rest.len < reload_phrase.len) return false;
    if (!std.ascii.eqlIgnoreCase(rest[0..reload_phrase.len], reload_phrase)) return false;
    const after = rest[reload_phrase.len..];
    if (after.len == 0) return true;
    // A letter, digit or `_` continues the word; so does any non-ASCII byte
    // (upstream asks `char::is_alphanumeric`, and "contexté" must not fire).
    const next = after[0];
    return !(std.ascii.isAlphanumeric(next) or next == '_' or next >= 0x80);
}

/// The JSON Claude Code adds to the context for `event`.
pub fn envelope(gpa: std.mem.Allocator, event: []const u8, text: []const u8) ![]u8 {
    return std.fmt.allocPrint(gpa, "{{\"hookSpecificOutput\":{{\"hookEventName\":\"{s}\",\"additionalContext\":{f}}}}}\n", .{
        event, std.json.fmt(text, .{}),
    });
}

const testing = std.testing;

test "reload context fires only as the prompt's opening words" {
    const cases = [_]struct { []const u8, bool }{
        .{ "reload context", true },
        .{ "reload context after last compaction, then continue", true },
        .{ "  Reload Context: then fix the build", true },
        .{ "RELOAD CONTEXT\nand go", true },
        .{ "reload context.", true },
        .{ "reload contexts", false },
        .{ "reload context_x", false },
        .{ "reload contexté", false },
        .{ "please reload context", false },
        .{ "can you reload context later?", false },
        .{ "reload", false },
        .{ "", false },
    };
    for (cases) |case| try testing.expectEqual(case[1], isReloadRequest(case[0]));
}

test "the envelope names the event and escapes the text" {
    const out = try envelope(testing.allocator, "SubagentStart", "a \"b\"\n");
    defer testing.allocator.free(out);
    try testing.expectEqualStrings("{\"hookSpecificOutput\":{\"hookEventName\":\"SubagentStart\",\"additionalContext\":\"a \\\"b\\\"\\n\"}}\n", out);
}
