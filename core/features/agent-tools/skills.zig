//! `cadex skills list` and `cadex skills get <topic>`: the full guides, built
//! into this binary so they always match the app it came with
//! (docs/adr/0024-agent-tools.md). The session kit's skills are short and
//! send the agent here.

const std = @import("std");

pub const Topic = struct { name: []const u8, summary: []const u8, text: []const u8 };

pub const topics = [_]Topic{
    .{ .name = "cadex", .summary = "what the cadex command does and when to use it", .text = @embedFile("guides/cadex.md") },
    .{ .name = "tasks", .summary = "your task's status and comment, and asking for review", .text = @embedFile("guides/tasks.md") },
    .{ .name = "preview", .summary = "opening pages in Cadex's preview, and picked elements", .text = @embedFile("guides/preview.md") },
};

pub fn find(name: []const u8) ?Topic {
    for (topics) |t| if (std.mem.eql(u8, t.name, name)) return t;
    return null;
}

/// "name — summary" per line.
pub fn list(gpa: std.mem.Allocator) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    for (topics) |t| try out.print(gpa, "{s} — {s}\n", .{ t.name, t.summary });
    return out.toOwnedSlice(gpa);
}

test "every topic has its guide, and an unknown one is none" {
    for (topics) |t| try std.testing.expect(std.mem.startsWith(u8, t.text, "# "));
    try std.testing.expect(find("tasks") != null and find("nope") == null);
    const text = try list(std.testing.allocator);
    defer std.testing.allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "preview — ") != null);
}
