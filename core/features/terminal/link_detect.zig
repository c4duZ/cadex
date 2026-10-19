//! Finds the URL or file path under a point in a line of terminal text.
//! Pure text work, no terminal types: links.zig builds the line from the
//! screen and resolves paths against the disk.

const std = @import("std");

pub const Kind = enum(u8) { none = 0, url = 1, path = 2 };

/// A link inside the line, as a byte range [start, end).
pub const Span = struct { start: usize, end: usize, kind: Kind };

/// Schemes opened in the browser or by the system. Others (javascript:,
/// data:) are never links: a program could print them to trick a click.
const url_schemes = [_][]const u8{ "http://", "https://", "ftp://", "file://", "ssh://", "git://", "mailto:" };

/// The link that contains byte `at`, or null.
pub fn findAt(text: []const u8, at: usize) ?Span {
    if (at >= text.len or isDelimiter(text[at])) return null;
    var start = at;
    while (start > 0 and !isDelimiter(text[start - 1])) start -= 1;
    var end = at + 1;
    while (end < text.len and !isDelimiter(text[end])) end += 1;

    // Opening brackets before the link, and closing punctuation after it,
    // usually belong to the sentence around it: "(see https://x.com)."
    while (start < end and std.mem.indexOfScalar(u8, "([{", text[start]) != null) start += 1;
    while (end > start and trailingJunk(text[start..end])) end -= 1;
    if (at < start or at >= end) return null;

    const token = text[start..end];
    const kind = classify(token);
    if (kind == .none) return null;
    return .{ .start = start, .end = end, .kind = kind };
}

fn isDelimiter(byte: u8) bool {
    return std.ascii.isWhitespace(byte) or std.mem.indexOfScalar(u8, "\"'`<>|", byte) != null;
}

/// Punctuation at the end that is not part of the link: a period or comma
/// ending the sentence, or a bracket that closes one opened before it.
fn trailingJunk(token: []const u8) bool {
    const last = token[token.len - 1];
    if (std.mem.indexOfScalar(u8, ".,;:!?", last) != null) return true;
    const pairs = [_][2]u8{ .{ '(', ')' }, .{ '[', ']' }, .{ '{', '}' } };
    for (pairs) |pair| {
        if (last != pair[1]) continue;
        // Wikipedia-style URLs keep balanced brackets: .../Rust_(language)
        return std.mem.count(u8, token, &.{pair[0]}) < std.mem.count(u8, token, &.{pair[1]});
    }
    return false;
}

fn classify(token: []const u8) Kind {
    for (url_schemes) |scheme| {
        if (token.len > scheme.len and std.ascii.startsWithIgnoreCase(token, scheme)) return .url;
    }
    if (std.ascii.startsWithIgnoreCase(token, "www.") and token.len > 4) return .url;
    // Something that names a file: absolute, from home, explicitly
    // relative, or with a directory in it (src/main.zig). Whether it exists
    // is links.zig's job.
    if (token[0] == '/' or std.mem.startsWith(u8, token, "~/")) return .path;
    if (std.mem.startsWith(u8, token, "./") or std.mem.startsWith(u8, token, "../")) return .path;
    if (std.mem.indexOfScalar(u8, token, '/') != null and std.mem.indexOf(u8, token, "://") == null) return .path;
    return .none;
}

/// "src/main.zig:12:3" → "src/main.zig": compilers and grep print a line
/// and column after the path.
pub fn withoutLineSuffix(path: []const u8) []const u8 {
    var end = path.len;
    var stripped: u8 = 0;
    while (stripped < 2) : (stripped += 1) {
        const colon = std.mem.lastIndexOfScalar(u8, path[0..end], ':') orelse break;
        const digits = path[colon + 1 .. end];
        if (digits.len == 0) break;
        for (digits) |d| if (!std.ascii.isDigit(d)) return path[0..end];
        end = colon;
    }
    return path[0..end];
}

const testing = std.testing;

fn expectLink(text: []const u8, at: usize, expected: ?[]const u8, kind: Kind) !void {
    const span = findAt(text, at);
    if (expected) |e| {
        const s = span orelse return error.NoLink;
        try testing.expectEqualStrings(e, text[s.start..s.end]);
        try testing.expectEqual(kind, s.kind);
    } else {
        try testing.expect(span == null);
    }
}

test "URLs in prose, with the punctuation around them left out" {
    const line = "veja (https://ghostty.org/docs). Depois";
    try expectLink(line, 10, "https://ghostty.org/docs", .url);
    try expectLink(line, 1, null, .none);
    try expectLink("https://en.wikipedia.org/wiki/Rust_(language), ok", 5, "https://en.wikipedia.org/wiki/Rust_(language)", .url);
    try expectLink("abra www.exemplo.com.br", 8, "www.exemplo.com.br", .url);
    try expectLink("javascript:alert(1)", 3, null, .none);
}

test "paths, absolute and relative, with line numbers" {
    try expectLink("error at /Users/cadu/a.zig:12:3: boom", 12, "/Users/cadu/a.zig:12:3", .path);
    try expectLink("ls ~/projeto", 5, "~/projeto", .path);
    try expectLink("modified:   core/build.zig", 15, "core/build.zig", .path);
    try expectLink("just words here", 3, null, .none);
    try expectLink("'/tmp/a b'", 2, "/tmp/a", .path);
}

test "line and column suffixes are dropped from paths" {
    try testing.expectEqualStrings("src/main.zig", withoutLineSuffix("src/main.zig:12:3"));
    try testing.expectEqualStrings("src/main.zig", withoutLineSuffix("src/main.zig:12"));
    try testing.expectEqualStrings("src/main.zig", withoutLineSuffix("src/main.zig"));
    try testing.expectEqualStrings("a:b", withoutLineSuffix("a:b"));
}
