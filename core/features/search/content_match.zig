//! Finding the next match in a file's bytes: literal text (with or without
//! case) by the core itself, regular expressions by the system's POSIX
//! regex (docs/adr/0009-regex-from-the-system.md).

const std = @import("std");

pub const Found = struct { start: usize, end: usize };

pub const Matcher = struct {
    gpa: std.mem.Allocator,
    needle: []u8,
    case_sensitive: bool,
    regex: ?*Regex = null,

    pub fn init(gpa: std.mem.Allocator, query: []const u8, case_sensitive: bool, regex: bool) !Matcher {
        if (query.len == 0) return error.InvalidPattern;
        var self: Matcher = .{ .gpa = gpa, .needle = try gpa.dupe(u8, query), .case_sensitive = case_sensitive };
        errdefer gpa.free(self.needle);
        if (regex) self.regex = try Regex.compile(gpa, query, case_sensitive);
        return self;
    }

    pub fn deinit(self: *Matcher) void {
        if (self.regex) |r| r.deinit(self.gpa);
        self.gpa.free(self.needle);
    }

    /// The first match at or after `from`, which is always a line start.
    pub fn find(self: *Matcher, bytes: []const u8, from: usize) ?Found {
        if (self.regex) |r| return r.find(bytes, from);
        const at = if (self.case_sensitive)
            std.mem.indexOfPos(u8, bytes, from, self.needle)
        else
            std.ascii.indexOfIgnoreCasePos(bytes, from, self.needle);
        const start = at orelse return null;
        return .{ .start = start, .end = start + self.needle.len };
    }
};

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

const Regex = struct {
    re: regex_t,

    fn compile(gpa: std.mem.Allocator, pattern: []const u8, case_sensitive: bool) !*Regex {
        const self = try gpa.create(Regex);
        errdefer gpa.destroy(self);
        var flags: c_int = REG_EXTENDED | REG_NEWLINE | REG_ENHANCED;
        if (!case_sensitive) flags |= REG_ICASE;
        if (regncomp(&self.re, pattern.ptr, pattern.len, flags) != 0) return error.InvalidPattern;
        return self;
    }

    fn deinit(self: *Regex, gpa: std.mem.Allocator) void {
        regfree(&self.re);
        gpa.destroy(self);
    }

    fn find(self: *Regex, bytes: []const u8, from: usize) ?Found {
        if (from >= bytes.len) return null;
        var m: [1]regmatch_t = undefined;
        if (regnexec(&self.re, bytes[from..].ptr, bytes.len - from, 1, &m, 0) != 0) return null;
        return .{ .start = from + @as(usize, @intCast(m[0].rm_so)), .end = from + @as(usize, @intCast(m[0].rm_eo)) };
    }
};

const testing = std.testing;

test "literal with and without case" {
    var m = try Matcher.init(testing.allocator, "Ghostty", false, false);
    defer m.deinit();
    try testing.expectEqual(Found{ .start = 7, .end = 14 }, m.find("lib libghostty", 0).?);
    var exact = try Matcher.init(testing.allocator, "Ghostty", true, false);
    defer exact.deinit();
    try testing.expect(exact.find("libghostty", 0) == null);
}

test "regex: extended syntax, Apple's \\d, lines and bad patterns" {
    var m = try Matcher.init(testing.allocator, "^fn [a-z]+\\(\\d\\)", true, true);
    defer m.deinit();
    const text = "const x = 1;\nfn open(2) {}\n";
    try testing.expectEqual(Found{ .start = 13, .end = 23 }, m.find(text, 0).?);
    try testing.expect(m.find(text, 23) == null);
    try testing.expectError(error.InvalidPattern, Matcher.init(testing.allocator, "(unclosed", false, true));
    try testing.expectError(error.InvalidPattern, Matcher.init(testing.allocator, "", false, false));
}
