//! Glob matching with gitignore's rules: `*` and `?` stop at `/`, `**`
//! crosses folders, `[a-z]` and `[!x]` are classes, `\` escapes. Paths are
//! short, so plain backtracking is enough.

const std = @import("std");

pub fn match(pattern: []const u8, text: []const u8) bool {
    var p: usize = 0;
    var t: usize = 0;
    while (p < pattern.len) {
        switch (pattern[p]) {
            '*' => return matchStars(pattern, p, text[t..]),
            '?' => {
                if (t >= text.len or text[t] == '/') return false;
                p += 1;
                t += 1;
            },
            '[' => {
                if (t >= text.len or text[t] == '/') return false;
                const end = classEnd(pattern, p) orelse {
                    // An unclosed `[` is a plain character.
                    if (text[t] != '[') return false;
                    p += 1;
                    t += 1;
                    continue;
                };
                if (!classMatches(pattern[p + 1 .. end], text[t])) return false;
                p = end + 1;
                t += 1;
            },
            '\\' => {
                const literal = if (p + 1 < pattern.len) pattern[p + 1] else '\\';
                if (t >= text.len or text[t] != literal) return false;
                p += 2;
                t += 1;
            },
            else => |ch| {
                if (t >= text.len or text[t] != ch) return false;
                p += 1;
                t += 1;
            },
        }
    }
    return t == text.len;
}

fn matchStars(pattern: []const u8, at: usize, text: []const u8) bool {
    var next = at;
    while (next < pattern.len and pattern[next] == '*') next += 1;
    const double = next - at >= 2;
    if (!double) {
        const rest = pattern[next..];
        var k: usize = 0;
        while (k <= text.len) : (k += 1) {
            if (match(rest, text[k..])) return true;
            if (k < text.len and text[k] == '/') return false;
        }
        return false;
    }
    // `**/`: zero or more whole folders.
    if (next < pattern.len and pattern[next] == '/') {
        const rest = pattern[next + 1 ..];
        if (match(rest, text)) return true;
        for (text, 0..) |ch, k| {
            if (ch == '/' and match(rest, text[k + 1 ..])) return true;
        }
        return false;
    }
    // `**` elsewhere: anything, slashes included.
    const rest = pattern[next..];
    var k: usize = 0;
    while (k <= text.len) : (k += 1) {
        if (match(rest, text[k..])) return true;
    }
    return false;
}

/// Index of the `]` closing the class at `open`; a `]` right after `[` or
/// `[!` belongs to the class.
fn classEnd(pattern: []const u8, open: usize) ?usize {
    var i = open + 1;
    if (i < pattern.len and (pattern[i] == '!' or pattern[i] == '^')) i += 1;
    if (i < pattern.len and pattern[i] == ']') i += 1;
    while (i < pattern.len) : (i += 1) {
        if (pattern[i] == ']') return i;
    }
    return null;
}

fn classMatches(class: []const u8, ch: u8) bool {
    var body = class;
    var negated = false;
    if (body.len > 0 and (body[0] == '!' or body[0] == '^')) {
        negated = true;
        body = body[1..];
    }
    var found = false;
    var i: usize = 0;
    while (i < body.len) : (i += 1) {
        if (i + 2 < body.len and body[i + 1] == '-') {
            if (ch >= body[i] and ch <= body[i + 2]) found = true;
            i += 2;
        } else if (body[i] == ch) {
            found = true;
        }
    }
    return found != negated;
}

const testing = std.testing;

test "stars stop at slashes, double stars cross them" {
    try testing.expect(match("*.log", "debug.log"));
    try testing.expect(!match("*.log", "logs/debug.log"));
    try testing.expect(match("**/*.log", "logs/deep/debug.log"));
    try testing.expect(match("**/*.log", "debug.log"));
    try testing.expect(match("build/**", "build/a/b"));
    try testing.expect(match("a/**/b", "a/b"));
    try testing.expect(match("a/**/b", "a/x/y/b"));
    try testing.expect(!match("a/**/b", "a/x/c"));
}

test "question marks, classes and escapes" {
    try testing.expect(match("file?.txt", "file1.txt"));
    try testing.expect(!match("file?.txt", "file/.txt"));
    try testing.expect(match("[a-c]x", "bx"));
    try testing.expect(!match("[!a-c]x", "bx"));
    try testing.expect(match("\\#notes", "#notes"));
    try testing.expect(match("[abc", "[abc"));
}
