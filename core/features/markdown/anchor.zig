//! Heading anchors as GitHub makes them (docs/spec/markdown.md): lowercase,
//! accents kept, spaces become `-`, punctuation goes (except `-` and `_`);
//! repeated headings get `-1`, `-2`. "Decisão Final" -> "decisão-final".

const std = @import("std");

/// The anchor of a heading's text, written to `out`.
pub fn slug(text: []const u8, out: *std.ArrayList(u8), gpa: std.mem.Allocator) !void {
    const view = std.unicode.Utf8View.init(text) catch return slugBytes(text, out, gpa);
    var it = view.iterator();
    while (it.nextCodepoint()) |cp| {
        if (cp < 0x80) {
            const ch: u8 = @intCast(cp);
            if (std.ascii.isAlphanumeric(ch) or ch == '-' or ch == '_') {
                try out.append(gpa, std.ascii.toLower(ch));
            } else if (ch == ' ') {
                try out.append(gpa, '-');
            }
            continue;
        }
        if (!isWordCodepoint(cp)) continue;
        var buf: [4]u8 = undefined;
        const n = std.unicode.utf8Encode(lower(cp), &buf) catch continue;
        try out.appendSlice(gpa, buf[0..n]);
    }
}

fn slugBytes(text: []const u8, out: *std.ArrayList(u8), gpa: std.mem.Allocator) !void {
    for (text) |ch| {
        if (std.ascii.isAlphanumeric(ch) or ch == '-' or ch == '_') try out.append(gpa, std.ascii.toLower(ch)) else if (ch == ' ') try out.append(gpa, '-');
    }
}

/// Letters and marks beyond ASCII stay; punctuation, symbols and emoji go.
fn isWordCodepoint(cp: u21) bool {
    if (cp >= 0xA0 and cp <= 0xBF) return false; // Latin-1 punctuation
    if (cp == 0xD7 or cp == 0xF7) return false; // × ÷
    if (cp >= 0x2000 and cp <= 0x2BFF) return false; // punctuation, arrows, symbols
    if (cp >= 0x3000 and cp <= 0x303F) return false; // CJK punctuation
    if (cp >= 0x1F000) return false; // emoji
    return true;
}

/// Lowercase for Latin-1, Latin Extended-A and Greek/Cyrillic capitals:
/// enough for Portuguese and the languages next to it.
fn lower(cp: u21) u21 {
    if (cp >= 0xC0 and cp <= 0xDE and cp != 0xD7) return cp + 0x20;
    if (cp >= 0x100 and cp <= 0x17F and cp % 2 == 0) return cp + 1;
    if (cp >= 0x391 and cp <= 0x3A9) return cp + 0x20;
    if (cp >= 0x410 and cp <= 0x42F) return cp + 0x20;
    return cp;
}

/// Anchors of headings in order, numbering repeats like GitHub.
pub const Counter = struct {
    seen: std.StringHashMapUnmanaged(u32) = .empty,

    pub fn deinit(self: *Counter, gpa: std.mem.Allocator) void {
        var it = self.seen.keyIterator();
        while (it.next()) |k| gpa.free(k.*);
        self.seen.deinit(gpa);
    }

    /// The anchor for the next heading with this text; caller frees.
    pub fn next(self: *Counter, gpa: std.mem.Allocator, text: []const u8) ![]u8 {
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(gpa);
        try slug(text, &out, gpa);
        const base = try out.toOwnedSlice(gpa);
        const entry = try self.seen.getOrPut(gpa, base);
        if (!entry.found_existing) {
            entry.key_ptr.* = try gpa.dupe(u8, base);
            entry.value_ptr.* = 0;
            return base;
        }
        entry.value_ptr.* += 1;
        defer gpa.free(base);
        return std.fmt.allocPrint(gpa, "{s}-{d}", .{ base, entry.value_ptr.* });
    }
};

const testing = std.testing;

fn expectSlug(want: []const u8, text: []const u8) !void {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(testing.allocator);
    try slug(text, &out, testing.allocator);
    try testing.expectEqualStrings(want, out.items);
}

test "GitHub anchors" {
    try expectSlug("decisão-final", "Decisão Final");
    try expectSlug("o-que-eu-quero", "O que eu quero");
    try expectSlug("api-c-cadex_free", "API C: `cadex_free`!");
    try expectSlug("ção", "ÇÃO");
    try expectSlug("plano-4--arquivos", "Plano 4 — Arquivos");
    try expectSlug("emoji-", "Emoji 🎉");
}

test "repeated headings are numbered" {
    var counter: Counter = .{};
    defer counter.deinit(testing.allocator);
    const a = try counter.next(testing.allocator, "Notas");
    defer testing.allocator.free(a);
    const b = try counter.next(testing.allocator, "Notas");
    defer testing.allocator.free(b);
    const c = try counter.next(testing.allocator, "Notas");
    defer testing.allocator.free(c);
    try testing.expectEqualStrings("notas", a);
    try testing.expectEqualStrings("notas-1", b);
    try testing.expectEqualStrings("notas-2", c);
}
