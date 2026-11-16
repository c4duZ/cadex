//! `cadex claude --cadex-prompt-file <file>` (plan 24, docs/adr/0033-cadex-launches-agents.md):
//! the prompt of a session Cadex opens with one (a race's contender, a
//! dispatch, an automation) never goes through a shell. The app writes it
//! to a file of its own and types only the file's path; this takes the
//! option out of the words, reads the file, removes it, and the prompt
//! becomes one word of the `claude` exec, after every other.
//!
//! Only a file in the prompts folder (`…/Cadex/orchestration/prompts`, or
//! CADEX_PROMPTS_DIR for a test), a regular file of this user and not a
//! link: `cadex claude --cadex-prompt-file ~/notes.md` typed by hand must
//! not read or delete the owner's file.

const std = @import("std");

pub const option = "--cadex-prompt-file";
/// The system's argument limit is far above; a prompt bigger than this is
/// refused by the app before it opens a tab (docs/spec/orchestration.md).
pub const max_bytes = 100 * 1024;

extern "c" fn unlink(path: [*:0]const u8) c_int;
extern "c" fn getuid() u32;

pub const Taken = struct {
    /// The words without the option and its value.
    words: []const [:0]const u8,
    /// The path given, if any (read or not).
    path: ?[:0]const u8 = null,
};

/// Splits the option out of `words`; the first one counts, a repeat is
/// left for `claude` to refuse.
pub fn take(arena: std.mem.Allocator, words: []const [:0]const u8) !Taken {
    for (words, 0..) |word, i| {
        if (std.mem.eql(u8, word, option) and i + 1 < words.len) {
            var rest: std.ArrayList([:0]const u8) = .empty;
            try rest.appendSlice(arena, words[0..i]);
            try rest.appendSlice(arena, words[i + 2 ..]);
            return .{ .words = try rest.toOwnedSlice(arena), .path = words[i + 1] };
        }
        if (std.mem.startsWith(u8, word, option ++ "=")) {
            var rest: std.ArrayList([:0]const u8) = .empty;
            try rest.appendSlice(arena, words[0..i]);
            try rest.appendSlice(arena, words[i + 1 ..]);
            return .{ .words = try rest.toOwnedSlice(arena), .path = try arena.dupeZ(u8, word[option.len + 1 ..]) };
        }
    }
    return .{ .words = words };
}

/// The prompts folder: CADEX_PROMPTS_DIR, else the one in the app's folder.
pub fn folder(arena: std.mem.Allocator) ?[]const u8 {
    if (std.c.getenv("CADEX_PROMPTS_DIR")) |dir| return std.mem.span(dir);
    const home = std.mem.span(std.c.getenv("HOME") orelse return null);
    return std.fmt.allocPrint(arena, "{s}/Library/Application Support/Cadex/orchestration/prompts", .{home}) catch null;
}

/// Reads and removes the prompt at `path` when it may: inside `dir`, a
/// plain name (no "/" or ".." after the folder), a regular file of this
/// user, not a link, at most `max_bytes`. Null otherwise (nothing removed).
/// A prompt starting with "-" gets a space first, so `claude` never takes
/// it for an option.
pub fn read(arena: std.mem.Allocator, dir: []const u8, path: []const u8) ?[:0]const u8 {
    const prefix = std.fmt.allocPrint(arena, "{s}/", .{std.mem.trimEnd(u8, dir, "/")}) catch return null;
    if (!std.mem.startsWith(u8, path, prefix)) return null;
    const name = path[prefix.len..];
    if (name.len == 0 or std.mem.indexOfScalar(u8, name, '/') != null or std.mem.startsWith(u8, name, ".")) return null;
    const z = arena.dupeZ(u8, path) catch return null;
    // O_NOFOLLOW refuses a link; fstat on what was opened (no race with a
    // swap between a check and the open).
    const fd = std.c.open(z.ptr, .{ .ACCMODE = .RDONLY, .NOFOLLOW = true });
    if (fd < 0) return null;
    defer _ = std.c.close(fd);
    var st: std.c.Stat = undefined;
    if (std.c.fstat(fd, &st) != 0) return null;
    if (!std.c.S.ISREG(st.mode) or st.uid != getuid() or st.size > max_bytes) return null;
    const text = arena.alloc(u8, @intCast(st.size)) catch return null;
    var got: usize = 0;
    while (got < text.len) {
        const n = std.c.read(fd, text[got..].ptr, text.len - got);
        if (n <= 0) break;
        got += @intCast(n);
    }
    if (got != text.len) return null;
    _ = unlink(z.ptr);
    const body = if (std.mem.startsWith(u8, text, "-"))
        std.fmt.allocPrintSentinel(arena, " {s}", .{text}, 0) catch return null
    else
        arena.dupeZ(u8, text) catch return null;
    // A NUL would cut the argument short: refuse rather than send half.
    if (std.mem.indexOfScalar(u8, body, 0) != null) return null;
    return body;
}

const testing = std.testing;

test "the option comes out of the words, in both spellings; without it nothing changes" {
    var arena_state: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const a = try take(arena, &.{ "--settings", "/k.json", option, "/p/x.md", "--model", "haiku" });
    try testing.expectEqualStrings("/p/x.md", a.path.?);
    try testing.expectEqual(@as(usize, 4), a.words.len);
    try testing.expectEqualStrings("haiku", a.words[3]);
    const b = try take(arena, &.{ option ++ "=/p/y.md", "-c" });
    try testing.expectEqualStrings("/p/y.md", b.path.?);
    try testing.expectEqual(@as(usize, 1), b.words.len);
    const c = try take(arena, &.{ "--model", "haiku" });
    try testing.expect(c.path == null and c.words.len == 2);
}

extern "c" fn symlink(target: [*:0]const u8, link: [*:0]const u8) c_int;
const TestDir = @import("../../shared/test_dir.zig").TestDir;

test "read: the prompt intact and the file gone; outside the folder, a link or a dot name refused and kept" {
    var arena_state: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var tmp = try TestDir.init();
    defer tmp.deinit();
    try tmp.makeDir("prompts");
    const text = "say \"hi\" $(rm -rf ~) `id`; a && b | c\nline 2 $HOME";
    try tmp.writeFile("prompts/d1.md", text);
    try tmp.writeFile("outside.md", "x");
    try tmp.writeFile("prompts/.hidden", "x");
    try tmp.writeFile("prompts/dash.md", "-p leak");
    try testing.expectEqual(@as(c_int, 0), symlink("../outside.md", try tmp.join("prompts/link.md")));
    const root = tmp.path();
    const dir = try std.fmt.allocPrint(arena, "{s}/prompts", .{root});
    const path = try std.fmt.allocPrint(arena, "{s}/d1.md", .{dir});
    try testing.expectEqualStrings(text, read(arena, dir, path).?);
    try testing.expect(!tmp.exists("prompts/d1.md"));
    try testing.expect(read(arena, dir, path) == null);
    try testing.expectEqualStrings(" -p leak", read(arena, dir, try std.fmt.allocPrint(arena, "{s}/dash.md", .{dir})).?);
    try testing.expect(read(arena, dir, try std.fmt.allocPrint(arena, "{s}/outside.md", .{root})) == null);
    try testing.expect(read(arena, dir, try std.fmt.allocPrint(arena, "{s}/../outside.md", .{dir})) == null);
    try testing.expect(read(arena, dir, try std.fmt.allocPrint(arena, "{s}/.hidden", .{dir})) == null);
    try testing.expect(read(arena, dir, try std.fmt.allocPrint(arena, "{s}/link.md", .{dir})) == null);
    try testing.expect(tmp.exists("outside.md") and tmp.exists("prompts/.hidden"));
}
