//! Regular expressions from the system's libc (docs/adr/0009-regex-from-the-system.md):
//! POSIX extended syntax with Apple's \d \w \s \b. Used by the content search
//! and by the editor's highlight queries (#match?).

const std = @import("std");

// <regex.h> on macOS; Zig's libc bindings do not have it.
const regex_t = extern struct { re_magic: c_int, re_nsub: usize, re_endp: ?[*]const u8, re_g: ?*anyopaque };
const regmatch_t = extern struct { rm_so: i64, rm_eo: i64 };
extern "c" fn regncomp(re: *regex_t, pattern: [*]const u8, len: usize, flags: c_int) c_int;
extern "c" fn regnexec(re: *const regex_t, text: [*]const u8, len: usize, nmatch: usize, matches: [*]regmatch_t, flags: c_int) c_int;
extern "c" fn regfree(re: *regex_t) void;
const REG_EXTENDED = 0o1;
const REG_ICASE = 0o2;
const REG_NEWLINE = 0o10;
/// \d, \w, \s, \b and friends (Apple's extension).
const REG_ENHANCED = 0o400;

pub const Found = struct { start: usize, end: usize };

pub const Regex = struct {
    re: regex_t,

    /// `^` and `$` match at line breaks.
    pub fn compile(gpa: std.mem.Allocator, pattern: []const u8, case_sensitive: bool) !*Regex {
        const self = try gpa.create(Regex);
        errdefer gpa.destroy(self);
        var flags: c_int = REG_EXTENDED | REG_NEWLINE | REG_ENHANCED;
        if (!case_sensitive) flags |= REG_ICASE;
        if (regncomp(&self.re, pattern.ptr, pattern.len, flags) != 0) return error.InvalidPattern;
        return self;
    }

    pub fn deinit(self: *Regex, gpa: std.mem.Allocator) void {
        regfree(&self.re);
        gpa.destroy(self);
    }

    /// The first match at or after `from`.
    pub fn find(self: *const Regex, bytes: []const u8, from: usize) ?Found {
        if (from >= bytes.len) return null;
        var m: [1]regmatch_t = undefined;
        if (regnexec(&self.re, bytes[from..].ptr, bytes.len - from, 1, &m, 0) != 0) return null;
        return .{ .start = from + @as(usize, @intCast(m[0].rm_so)), .end = from + @as(usize, @intCast(m[0].rm_eo)) };
    }

    pub fn matches(self: *const Regex, text: []const u8) bool {
        var m: [1]regmatch_t = undefined;
        return regnexec(&self.re, text.ptr, text.len, 1, &m, 0) == 0;
    }
};

test "extended syntax with Apple's classes outside brackets" {
    const r = try Regex.compile(std.testing.allocator, "^[A-Z][A-Z0-9_]*$", true);
    defer r.deinit(std.testing.allocator);
    try std.testing.expect(r.matches("MAX_SIZE2"));
    try std.testing.expect(!r.matches("MaxSize"));
    // Inside brackets \d is not a class for the system's regex: callers
    // with Perl-style patterns translate them first (editor/query.zig).
    const digits = try Regex.compile(std.testing.allocator, "^v\\d+$", true);
    defer digits.deinit(std.testing.allocator);
    try std.testing.expect(digits.matches("v42"));
}
