//! Fuzzy matching: does a query's letters appear in order in a text, and
//! how good is the match. Used by the command palette ("na" finds "Nova
//! aba") and, in plan 4, by file search. Case and Portuguese accents do not
//! matter: "divisao" finds "Divisão".

const std = @import("std");

/// Score of one matched character, plus the bonuses below. Values tuned by
/// hand on command titles (2026-10-19): what matters is the order they give.
const score_match: i32 = 16;
/// The match starts a word (start of text, or after a space or - _ . /).
const bonus_word_start: i32 = 10;
/// Extra for matching the very first character of the text.
const bonus_text_start: i32 = 6;
/// The match follows the previous matched character directly.
const bonus_consecutive: i32 = 8;
/// Per character skipped between two matches, and before the first one.
const penalty_gap: i32 = 1;
const penalty_leading: i32 = 1;
const max_leading_penalty: i32 = 6;

/// Longest text and query considered; longer ones do not match. Titles and
/// file names are far shorter, and the score table is query × text.
pub const max_text_chars = 512;
pub const max_query_chars = 64;

pub const Match = struct {
    score: i32,
    /// Byte offsets in the text of the matched characters, query order.
    positions: []u32,
};

/// The best match of `query` in `text`, or null when some query character
/// is missing or out of order. An empty query matches with score 0.
/// Positions are allocated with `gpa`; caller frees them.
pub fn match(gpa: std.mem.Allocator, query: []const u8, text: []const u8) !?Match {
    var q_buf: [max_query_chars]u21 = undefined;
    const q = foldInto(query, &q_buf, null) orelse return null;
    if (q.len == 0) return .{ .score = 0, .positions = &.{} };

    var t_buf: [max_text_chars]u21 = undefined;
    var offsets: [max_text_chars]u32 = undefined;
    const t = foldInto(text, &t_buf, &offsets) orelse return null;
    if (t.len < q.len) return null;

    // best[i][j]: best score with query[0..i] matched and query[i] at text j.
    // from[i][j]: where query[i-1] was, to recover the positions.
    const cells = q.len * t.len;
    const best = try gpa.alloc(i32, cells);
    defer gpa.free(best);
    const from = try gpa.alloc(u32, cells);
    defer gpa.free(from);
    const none = std.math.minInt(i32);
    @memset(best, none);

    for (0..t.len) |j| {
        if (t[j] != q[0]) continue;
        const leading = @min(@as(i32, @intCast(j)) * penalty_leading, max_leading_penalty);
        best[j] = score_match + bonusAt(t, j) - leading;
    }
    for (1..q.len) |i| {
        // Running best over previous positions k < j, gaps included.
        var running: i32 = none;
        var running_at: u32 = 0;
        for (1..t.len) |j| {
            const prev = best[(i - 1) * t.len + (j - 1)];
            if (prev != none and (running == none or prev > running - penalty_gap)) {
                running = prev;
                running_at = @intCast(j - 1);
            } else if (running != none) {
                running -= penalty_gap;
            }
            if (t[j] != q[i] or running == none) continue;
            var score = running + score_match + bonusAt(t, j);
            if (running_at == j - 1) score += bonus_consecutive;
            best[i * t.len + j] = score;
            from[i * t.len + j] = running_at;
        }
    }

    const last_row = best[(q.len - 1) * t.len ..][0..t.len];
    var end: usize = 0;
    var top: i32 = none;
    for (last_row, 0..) |score, j| {
        if (score > top) {
            top = score;
            end = j;
        }
    }
    if (top == none) return null;

    const positions = try gpa.alloc(u32, q.len);
    var j = end;
    var i = q.len;
    while (i > 0) {
        i -= 1;
        positions[i] = offsets[j];
        if (i > 0) j = from[i * t.len + j];
    }
    return .{ .score = top, .positions = positions };
}

fn bonusAt(t: []const u21, j: usize) i32 {
    if (j == 0) return bonus_word_start + bonus_text_start;
    const before = t[j - 1];
    if (before == ' ' or before == '-' or before == '_' or before == '.' or before == '/') return bonus_word_start;
    return 0;
}

/// Decodes UTF-8 into folded codepoints (lowercase, no accent), with each
/// one's byte offset when `offsets` is given. Null when too long or not
/// UTF-8.
fn foldInto(text: []const u8, out: []u21, offsets: ?*[max_text_chars]u32) ?[]const u21 {
    var view = std.unicode.Utf8View.init(text) catch return null;
    var it = view.iterator();
    var n: usize = 0;
    var at: usize = 0;
    while (it.nextCodepointSlice()) |slice| {
        if (n == out.len) return null;
        const cp = std.unicode.utf8Decode(slice) catch return null;
        out[n] = fold(cp);
        if (offsets) |o| o[n] = @intCast(at);
        at += slice.len;
        n += 1;
    }
    return out[0..n];
}

/// Lowercase and without the accents Portuguese uses, so "Ação" and "acao"
/// compare equal. Other scripts pass through.
fn fold(cp: u21) u21 {
    if (cp < 0x80) return std.ascii.toLower(@intCast(cp));
    return switch (cp) {
        0xC0...0xC5, 0xE0...0xE5 => 'a',
        0xC7, 0xE7 => 'c',
        0xC8...0xCB, 0xE8...0xEB => 'e',
        0xCC...0xCF, 0xEC...0xEF => 'i',
        0xD1, 0xF1 => 'n',
        0xD2...0xD6, 0xF2...0xF6 => 'o',
        0xD9...0xDC, 0xF9...0xFC => 'u',
        else => cp,
    };
}

const testing = std.testing;

fn scoreOf(query: []const u8, text: []const u8) !?i32 {
    const m = try match(testing.allocator, query, text) orelse return null;
    defer testing.allocator.free(m.positions);
    return m.score;
}

test "letters must appear in order" {
    try testing.expect(try scoreOf("na", "Nova aba") != null);
    try testing.expect(try scoreOf("an", "Nova") == null);
    try testing.expect(try scoreOf("xyz", "Nova aba") == null);
    try testing.expect((try scoreOf("", "qualquer")).? == 0);
}

test "word starts and the beginning rank higher" {
    const nova_aba = (try scoreOf("na", "Nova aba")).?;
    const abrir = (try scoreOf("na", "Abrir nova janela")).?;
    try testing.expect(nova_aba > abrir);
    try testing.expect((try scoreOf("dd", "Dividir para baixo")).? < (try scoreOf("dd", "Dividir à direita")).?);
}

test "case and accents do not matter" {
    try testing.expect(try scoreOf("divisao", "Divisão") != null);
    try testing.expect(try scoreOf("ACAO", "ação") != null);
    try testing.expect(try scoreOf("dir", "Dividir à direita") != null);
}

test "positions point at the matched bytes, accents included" {
    const m = (try match(testing.allocator, "aa", "Ação aberta")).?;
    defer testing.allocator.free(m.positions);
    // "Ação aberta": A at byte 0; "ç" and "ã" are two bytes each, so the
    // space is at byte 6 and the word "aberta" starts at byte 7.
    try testing.expectEqualSlices(u32, &.{ 0, 7 }, m.positions);
}
