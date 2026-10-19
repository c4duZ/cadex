//! Finding the next match in a file's bytes: literal text (with or without
//! case) by the core itself, regular expressions by the system's POSIX
//! regex (shared/regex.zig).

const std = @import("std");
const Regex = @import("../../shared/regex.zig").Regex;

pub const Found = @import("../../shared/regex.zig").Found;

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
