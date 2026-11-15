//! What `cadex hook PostToolUse` sends the app (docs/adr/0027-local-authorship.md):
//! the session, the folder, the tool, the file and the ranges of lines the
//! agent wrote, worked out here from the edit's `structuredPatch` (each hunk's
//! `newStart` and its `+` lines). Never the file nor the text of a line: the
//! `tool_response` also carries `originalFile`, the whole file before the edit,
//! and `tool_input` the strings (checked with Claude Code, 2026-11-15). A Write
//! that creates a file has no patch: the whole file is the agent's. Anything
//! else without a patch gets no ranges, never wrong ones.

const std = @import("std");

/// The trimmed payload as one JSON object. Caller frees.
pub fn trimmed(gpa: std.mem.Allocator, payload: std.json.Value) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    const root = if (payload == .object) payload.object else return gpa.dupe(u8, "null");
    const input = field(root, "tool_input");
    const response = field(root, "tool_response");
    const tool = string(root.get("tool_name")) orelse "";
    const file = string(fieldOf(input, "file_path")) orelse string(fieldOf(input, "notebook_path")) orelse string(fieldOf(response, "filePath")) orelse "";
    const patch = fieldOf(response, "structuredPatch");
    const created = std.mem.eql(u8, string(fieldOf(response, "type")) orelse "", "create");
    try out.print(gpa, "{{\"session_id\":{f},\"cwd\":{f},\"tool_name\":{f},\"file\":{f},\"whole\":{},\"lines\":[", .{
        std.json.fmt(string(root.get("session_id")) orelse "", .{}), std.json.fmt(string(root.get("cwd")) orelse "", .{}),
        std.json.fmt(tool, .{}), std.json.fmt(file, .{}), created and std.mem.eql(u8, tool, "Write"),
    });
    if (patch) |p| try ranges(gpa, &out, p);
    try out.appendSlice(gpa, "]}");
    return out.toOwnedSlice(gpa);
}

/// The new-side lines of the `+` lines, joined into [start,end] ranges.
fn ranges(gpa: std.mem.Allocator, out: *std.ArrayList(u8), patch: std.json.Value) !void {
    if (patch != .array) return;
    var first = true;
    var open: ?[2]i64 = null;
    for (patch.array.items) |hunk| {
        if (hunk != .object) continue;
        var line: i64 = switch (hunk.object.get("newStart") orelse continue) {
            .integer => |n| n,
            else => continue,
        };
        const lines = hunk.object.get("lines") orelse continue;
        if (lines != .array) continue;
        for (lines.array.items) |item| {
            const text = if (item == .string) item.string else continue;
            if (text.len == 0) continue;
            switch (text[0]) {
                '+' => {
                    if (open) |*r| {
                        if (r[1] + 1 == line) r[1] = line else {
                            try emit(gpa, out, r.*, &first);
                            open = .{ line, line };
                        }
                    } else open = .{ line, line };
                    line += 1;
                },
                ' ' => line += 1,
                else => {}, // '-' takes no new line; '\' is "No newline at end of file"
            }
        }
    }
    if (open) |r| try emit(gpa, out, r, &first);
}

fn emit(gpa: std.mem.Allocator, out: *std.ArrayList(u8), r: [2]i64, first: *bool) !void {
    if (!first.*) try out.append(gpa, ',');
    first.* = false;
    try out.print(gpa, "[{d},{d}]", .{ r[0], r[1] });
}

fn field(object: std.json.ObjectMap, name: []const u8) ?std.json.Value {
    const value = object.get(name) orelse return null;
    return if (value == .object) value else null;
}

fn fieldOf(parent: ?std.json.Value, name: []const u8) ?std.json.Value {
    const p = parent orelse return null;
    return if (p == .object) p.object.get(name) else null;
}

fn string(value: ?std.json.Value) ?[]const u8 {
    const v = value orelse return null;
    return if (v == .string) v.string else null;
}

const testing = std.testing;

test "an Edit's ranges from its patch, a created file whole, and never the file's text" {
    const gpa = testing.allocator;
    const edit =
        \\{"session_id":"s1","cwd":"/w","tool_name":"Edit","tool_input":{"file_path":"/w/a.txt","old_string":"two","new_string":"TWO"},
        \\"tool_response":{"filePath":"/w/a.txt","originalFile":"one\ntwo\nSECRET\n","structuredPatch":[
        \\{"oldStart":1,"oldLines":4,"newStart":1,"newLines":5,"lines":[" one","-two","+TWO","+2b"," three","\\ No newline at end of file"]},
        \\{"oldStart":20,"oldLines":1,"newStart":21,"newLines":2,"lines":[" x","+y"]}]}}
    ;
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, edit, .{});
    defer parsed.deinit();
    const out = try trimmed(gpa, parsed.value);
    defer gpa.free(out);
    try testing.expectEqualStrings("{\"session_id\":\"s1\",\"cwd\":\"/w\",\"tool_name\":\"Edit\",\"file\":\"/w/a.txt\",\"whole\":false,\"lines\":[[2,3],[22,22]]}", out);
    try testing.expect(std.mem.indexOf(u8, out, "SECRET") == null and std.mem.indexOf(u8, out, "TWO") == null);
    const write =
        \\{"session_id":"s1","cwd":"/w","tool_name":"Write","tool_input":{"file_path":"/w/n.txt","content":"all of it"},
        \\"tool_response":{"type":"create","filePath":"/w/n.txt","content":"all of it","structuredPatch":[]}}
    ;
    var parsed2 = try std.json.parseFromSlice(std.json.Value, gpa, write, .{});
    defer parsed2.deinit();
    const created = try trimmed(gpa, parsed2.value);
    defer gpa.free(created);
    try testing.expectEqualStrings("{\"session_id\":\"s1\",\"cwd\":\"/w\",\"tool_name\":\"Write\",\"file\":\"/w/n.txt\",\"whole\":true,\"lines\":[]}", created);
}
