//! A language's highlight query, compiled once, with the text predicates
//! tree-sitter leaves to the caller: #eq?, #match?, #lua-match?, #any-of?
//! (and their #not- forms). Others (#is-not? local, #set!) count as true.

const std = @import("std");
const sync = @import("../../shared/sync.zig");
const ts = @import("ts.zig").c;
const highlight = @import("highlight.zig");
const languages = @import("languages.zig");
const Regex = @import("../../shared/regex.zig").Regex;

/// Gives the UTF-8 text between two offsets of the document being queried.
pub const Text = struct {
    context: *anyopaque,
    get: *const fn (context: *anyopaque, start: u32, end: u32, buf: []u8) []const u8,
};

const Predicate = struct {
    capture: u32,
    negate: bool,
    check: union(enum) {
        eq_capture: u32,
        eq_text: []const u8,
        match: *Regex,
        any_of: []const []const u8,
    },
};

pub const Query = struct {
    query: *ts.TSQuery,
    /// Kind of each capture, by capture index.
    kinds: []highlight.Kind,
    /// Predicates of each pattern, by pattern index.
    predicates: [][]Predicate,

    /// Whether a match passes its pattern's predicates.
    pub fn accepts(self: *const Query, match: *const ts.TSQueryMatch, text: Text) bool {
        for (self.predicates[match.pattern_index]) |p| {
            if (evaluate(p, match, text) == p.negate) return false;
        }
        return true;
    }
};

fn evaluate(p: Predicate, match: *const ts.TSQueryMatch, text: Text) bool {
    var buf: [512]u8 = undefined;
    const subject = captureText(match, p.capture, text, &buf) orelse return true;
    return switch (p.check) {
        .eq_text => |value| std.mem.eql(u8, subject, value),
        .eq_capture => |other| blk: {
            var other_buf: [512]u8 = undefined;
            const b = captureText(match, other, text, &other_buf) orelse break :blk true;
            break :blk std.mem.eql(u8, subject, b);
        },
        .match => |regex| regex.matches(subject),
        .any_of => |values| for (values) |v| {
            if (std.mem.eql(u8, subject, v)) break true;
        } else false,
    };
}

fn captureText(match: *const ts.TSQueryMatch, capture: u32, text: Text, buf: []u8) ?[]const u8 {
    for (match.captures[0..match.capture_count]) |c| {
        if (c.index != capture) continue;
        return text.get(text.context, ts.ts_node_start_byte(c.node), ts.ts_node_end_byte(c.node), buf);
    }
    return null;
}

/// Compiled queries live for the whole process, one per language.
var cache: [languages.all.len]?*Query = @splat(null);
var cache_mutex: sync.Mutex = .{};

/// The language's query, compiled on first use; null if it does not
/// compile against the grammar (then the file shows without colors).
pub fn forLanguage(language: *const languages.Language) ?*Query {
    cache_mutex.lock();
    defer cache_mutex.unlock();
    const slot = &cache[@intFromEnum(language.id)];
    if (slot.* == null) slot.* = compile(std.heap.c_allocator, language) catch null;
    return slot.*;
}

pub fn compile(gpa: std.mem.Allocator, language: *const languages.Language) !*Query {
    var error_offset: u32 = 0;
    var error_type: ts.TSQueryError = ts.TSQueryErrorNone;
    const raw = ts.ts_query_new(language.grammar(), language.highlights.ptr, @intCast(language.highlights.len), &error_offset, &error_type) orelse {
        std.log.warn("highlight query of {s} fails at byte {d} (error {d})", .{ language.name, error_offset, error_type });
        return error.InvalidQuery;
    };
    errdefer ts.ts_query_delete(raw);
    const self = try gpa.create(Query);
    self.query = raw;
    const capture_count = ts.ts_query_capture_count(raw);
    self.kinds = try gpa.alloc(highlight.Kind, capture_count);
    for (self.kinds, 0..) |*kind, i| {
        var len: u32 = 0;
        const name = ts.ts_query_capture_name_for_id(raw, @intCast(i), &len);
        kind.* = highlight.kindOf(name[0..len]);
    }
    const pattern_count = ts.ts_query_pattern_count(raw);
    self.predicates = try gpa.alloc([]Predicate, pattern_count);
    for (self.predicates, 0..) |*list, i| list.* = try parsePredicates(gpa, raw, @intCast(i));
    return self;
}

/// Frees a query made by compile (tests; cached ones stay).
pub fn destroy(gpa: std.mem.Allocator, self: *Query) void {
    for (self.predicates) |list| {
        for (list) |p| switch (p.check) {
            .match => |r| r.deinit(gpa),
            .any_of => |values| gpa.free(values),
            else => {},
        };
        gpa.free(list);
    }
    gpa.free(self.predicates);
    gpa.free(self.kinds);
    ts.ts_query_delete(self.query);
    gpa.destroy(self);
}

fn parsePredicates(gpa: std.mem.Allocator, raw: *ts.TSQuery, pattern: u32) ![]Predicate {
    var count: u32 = 0;
    const steps = ts.ts_query_predicates_for_pattern(raw, pattern, &count);
    var list: std.ArrayList(Predicate) = .empty;
    var i: usize = 0;
    while (i < count) {
        var end = i;
        while (end < count and steps[end].type != ts.TSQueryPredicateStepTypeDone) end += 1;
        if (try parseOne(gpa, raw, steps[i..end])) |p| try list.append(gpa, p);
        i = end + 1;
    }
    return list.toOwnedSlice(gpa);
}

fn parseOne(gpa: std.mem.Allocator, raw: *ts.TSQuery, steps: []const ts.TSQueryPredicateStep) !?Predicate {
    if (steps.len < 3 or steps[0].type != ts.TSQueryPredicateStepTypeString) return null;
    if (steps[1].type != ts.TSQueryPredicateStepTypeCapture) return null;
    const name = stringValue(raw, steps[0].value_id);
    const negate = std.mem.startsWith(u8, name, "not-");
    const op = if (negate) name[4..] else name;
    const capture = steps[1].value_id;
    const arg = steps[2];
    if (std.mem.eql(u8, op, "eq?")) {
        return .{ .capture = capture, .negate = negate, .check = if (arg.type == ts.TSQueryPredicateStepTypeCapture)
            .{ .eq_capture = arg.value_id }
        else
            .{ .eq_text = stringValue(raw, arg.value_id) } };
    }
    if (std.mem.eql(u8, op, "match?") or std.mem.eql(u8, op, "lua-match?")) {
        const pattern = stringValue(raw, arg.value_id);
        var buf: [512]u8 = undefined;
        const translated = toPosix(pattern, std.mem.eql(u8, op, "lua-match?"), &buf) orelse return null;
        const regex = Regex.compile(gpa, translated, true) catch return null;
        return .{ .capture = capture, .negate = negate, .check = .{ .match = regex } };
    }
    if (std.mem.eql(u8, op, "any-of?")) {
        const values = try gpa.alloc([]const u8, steps.len - 2);
        for (steps[2..], values) |s, *v| v.* = stringValue(raw, s.value_id);
        return .{ .capture = capture, .negate = negate, .check = .{ .any_of = values } };
    }
    return null;
}

fn stringValue(raw: *ts.TSQuery, id: u32) []const u8 {
    var len: u32 = 0;
    const ptr = ts.ts_query_string_value_for_id(raw, id, &len);
    return ptr[0..len];
}

/// Rewrites the classes the system's regex lacks inside brackets (\d, \w,
/// \s) and Lua's %d %a %u %l %w %s %x %p into POSIX. Null if too long.
fn toPosix(pattern: []const u8, lua: bool, out: []u8) ?[]const u8 {
    var w: std.Io.Writer = .fixed(out);
    var i: usize = 0;
    while (i < pattern.len) : (i += 1) {
        const ch = pattern[i];
        const escape: u8 = if (lua) '%' else '\\';
        if (ch == escape and i + 1 < pattern.len) {
            const class: ?[]const u8 = switch (pattern[i + 1]) {
                'd' => "[:digit:]",
                'w' => "[:alnum:]_",
                's' => "[:space:]",
                'a' => if (lua) "[:alpha:]" else null,
                'u' => if (lua) "[:upper:]" else null,
                'l' => if (lua) "[:lower:]" else null,
                'x' => if (lua) "[:xdigit:]" else null,
                'p' => if (lua) "[:punct:]" else null,
                else => null,
            };
            if (class) |cls| {
                const inside = insideBrackets(pattern[0..i]);
                if (inside) w.writeAll(cls) catch return null else w.print("[{s}]", .{cls}) catch return null;
                i += 1;
                continue;
            }
            if (lua) {
                w.writeByte('\\') catch return null;
                w.writeByte(pattern[i + 1]) catch return null;
                i += 1;
                continue;
            }
        }
        w.writeByte(ch) catch return null;
    }
    return w.buffered();
}

/// Whether the text so far leaves an unclosed `[`.
fn insideBrackets(before: []const u8) bool {
    var open = false;
    var i: usize = 0;
    while (i < before.len) : (i += 1) {
        switch (before[i]) {
            '\\', '%' => i += 1,
            '[' => open = true,
            ']' => open = false,
            else => {},
        }
    }
    return open;
}

test "Perl and Lua classes become POSIX" {
    var buf: [128]u8 = undefined;
    try std.testing.expectEqualStrings("^[A-Z][A-Z[:digit:]_]*$", toPosix("^[A-Z][A-Z\\d_]*$", false, &buf).?);
    try std.testing.expectEqualStrings("^[[:upper:]][[:alnum:]__]*", toPosix("^%u[%w_]*", true, &buf).?);
    try std.testing.expectEqualStrings("a\\.b", toPosix("a%.b", true, &buf).?);
}

test "every language's query compiles against its grammar" {
    for (&languages.all) |*language| {
        const q = compile(std.testing.allocator, language) catch |err| {
            std.debug.print("query of {s}: {s}\n", .{ language.name, @errorName(err) });
            return err;
        };
        destroy(std.testing.allocator, q);
    }
}
