//! Regular expressions through TRE, compiled into the core
//! (docs/adr/0013-regex-tre.md): POSIX extended syntax plus \d \w \s \b
//! \< \>, the same on the Mac and on Windows. Used by the content search
//! and by the editor's highlight queries (#match?).

const std = @import("std");

// TRE's own regex.h types (lib/tre.h without TRE_USE_SYSTEM_REGEX_H). The
// functions carry the cadex_ prefix the build gives them (build_grammars.zig).
const regex_t = extern struct { re_nsub: usize, value: ?*anyopaque };
const regmatch_t = extern struct { rm_so: c_int, rm_eo: c_int };
extern "c" fn cadex_tre_regncomp(re: *regex_t, pattern: [*]const u8, len: usize, flags: c_int) c_int;
extern "c" fn cadex_tre_regnexec(re: *const regex_t, text: [*]const u8, len: usize, nmatch: usize, matches: [*]regmatch_t, flags: c_int) c_int;
extern "c" fn cadex_tre_regfree(re: *regex_t) void;
const REG_EXTENDED = 1;
const REG_ICASE = 2;
const REG_NEWLINE = 4;

pub const Found = struct { start: usize, end: usize };

pub const Regex = struct {
    re: regex_t,

    /// `^` and `$` match at line breaks.
    pub fn compile(gpa: std.mem.Allocator, pattern: []const u8, case_sensitive: bool) !*Regex {
        const self = try gpa.create(Regex);
        errdefer gpa.destroy(self);
        var flags: c_int = REG_EXTENDED | REG_NEWLINE;
        if (!case_sensitive) flags |= REG_ICASE;
        if (cadex_tre_regncomp(&self.re, pattern.ptr, pattern.len, flags) != 0) return error.InvalidPattern;
        return self;
    }

    pub fn deinit(self: *Regex, gpa: std.mem.Allocator) void {
        cadex_tre_regfree(&self.re);
        gpa.destroy(self);
    }

    /// The first match at or after `from`.
    pub fn find(self: *const Regex, bytes: []const u8, from: usize) ?Found {
        if (from >= bytes.len) return null;
        var m: [1]regmatch_t = undefined;
        if (cadex_tre_regnexec(&self.re, bytes[from..].ptr, bytes.len - from, 1, &m, 0) != 0) return null;
        return .{ .start = from + @as(usize, @intCast(m[0].rm_so)), .end = from + @as(usize, @intCast(m[0].rm_eo)) };
    }

    pub fn matches(self: *const Regex, text: []const u8) bool {
        var m: [1]regmatch_t = undefined;
        return cadex_tre_regnexec(&self.re, text.ptr, text.len, 1, &m, 0) == 0;
    }
};

const testing = std.testing;

test "extended syntax with the shorthand classes outside brackets" {
    const r = try Regex.compile(testing.allocator, "^[A-Z][A-Z0-9_]*$", true);
    defer r.deinit(testing.allocator);
    try testing.expect(r.matches("MAX_SIZE2"));
    try testing.expect(!r.matches("MaxSize"));
    // Inside brackets \d is not a class for POSIX regex: callers with
    // Perl-style patterns translate them first (editor/query.zig).
    const digits = try Regex.compile(testing.allocator, "^v\\d+$", true);
    defer digits.deinit(testing.allocator);
    try testing.expect(digits.matches("v42"));
}

test "the same answers on every system: words, case, lines, UTF-8" {
    const Case = struct { pattern: []const u8, case_sensitive: bool, text: []const u8, start: usize, end: usize };
    const cases = [_]Case{
        .{ .pattern = "\\bfoo\\b", .case_sensitive = true, .text = "a foo b", .start = 2, .end = 5 },
        .{ .pattern = "\\<bar", .case_sensitive = true, .text = "foobar bar", .start = 7, .end = 10 },
        .{ .pattern = "\\w+\\s\\d", .case_sensitive = true, .text = "-- item 7", .start = 3, .end = 9 },
        .{ .pattern = "todo", .case_sensitive = false, .text = "// TODO: x", .start = 3, .end = 7 },
        .{ .pattern = "^b", .case_sensitive = true, .text = "a\nb", .start = 2, .end = 3 },
        .{ .pattern = "(ab|cd){2}", .case_sensitive = true, .text = "xxcdab", .start = 2, .end = 6 },
        .{ .pattern = "olá", .case_sensitive = true, .text = "diga olá", .start = 5, .end = 9 },
    };
    for (cases) |case| {
        const r = try Regex.compile(testing.allocator, case.pattern, case.case_sensitive);
        defer r.deinit(testing.allocator);
        const found = r.find(case.text, 0) orelse return error.NoMatch;
        try testing.expectEqual(case.start, found.start);
        try testing.expectEqual(case.end, found.end);
    }
    try testing.expectError(error.InvalidPattern, Regex.compile(testing.allocator, "(unclosed", true));
}
