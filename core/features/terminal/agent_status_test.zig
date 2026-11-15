//! The agent's state from OSC 7501, fed through the model as the shell's
//! output would be (sequences of Claude Code 2.1.325, test of 2026-11-14).

const std = @import("std");
const model_file = @import("model.zig");
const Model = model_file.Model;
const Notice = model_file.Notice;
const AgentState = model_file.AgentState;
const AgentKind = model_file.AgentKind;
const testing = std.testing;

test "answers the agent's OSC 7501 query and keeps its state, kind and text" {
    const model = try Model.create(testing.io, testing.allocator, .{ .cols = 20, .rows = 4 });
    defer model.destroy();
    const Capture = struct {
        var replies: [256]u8 = undefined;
        var replies_len: usize = 0;
        var agent_notices: usize = 0;
        fn reply(_: ?*anyopaque, bytes: []const u8) void {
            @memcpy(replies[replies_len..][0..bytes.len], bytes);
            replies_len += bytes.len;
        }
        fn notice(_: ?*anyopaque, n: Notice) void {
            if (n == .agent) agent_notices += 1;
        }
    };
    Capture.replies_len = 0;
    Capture.agent_notices = 0;
    model.setReply(&Capture.reply, null);
    model.setNotice(&Capture.notice);

    // Claude Code 2.1.325 asks this at start (test of 2026-11-14).
    model.feed("\x1b]7501;?\x07");
    try testing.expect(std.mem.startsWith(u8, Capture.replies[0..Capture.replies_len], "\x1b]7501;?"));

    model.feed("\x1b]7501;state=working:app=claude-code:msg=Q3JlYXRpbmcgZW1wdHkgZmlsZeKApg==\x07");
    try testing.expectEqual(AgentState.working, model.agent.state);
    try testing.expectEqualStrings("claude-code", model.agent.appName());
    try testing.expectEqualStrings("Creating empty file…", model.agent.message());

    model.feed("\x1b]7501;state=blocked:app=claude-code:kind=permission:msg=YXBwcm92ZSBCYXNoOiB0b3VjaCB4\x07");
    try testing.expectEqual(AgentState.blocked, model.agent.state);
    try testing.expectEqual(AgentKind.permission, model.agent.kind);
    try testing.expectEqualStrings("approve Bash: touch x", model.agent.message());

    // An unknown key is skipped; a report without msg has none.
    model.feed("\x1b]7501;state=done:app=claude-code:future=1\x07");
    try testing.expectEqual(AgentState.done, model.agent.state);
    try testing.expectEqual(AgentKind.none, model.agent.kind);
    try testing.expectEqual(@as(usize, 0), model.agent.message().len);

    // A record with an id is a child record, not the program: ignored.
    model.feed("\x1b]7501;state=blocked:id=sub:app=x\x07");
    try testing.expectEqual(AgentState.done, model.agent.state);
    model.feed("\x1b]7501;state=clear\x07");
    try testing.expectEqual(AgentState.none, model.agent.state);
    // working, blocked, done and clear; the child record gave none.
    try testing.expectEqual(@as(usize, 4), Capture.agent_notices);
}
