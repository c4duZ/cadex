//! How the terminal's text is set (plan 15, phase C), as the Mac's
//! Typesetting in TerminalFont.swift: line height as a multiple of the
//! font's (terminal.lineHeight), extra space between letters
//! (terminal.letterSpacing) and the OpenType features (terminal.fontFeatures:
//! "calt", "ss01", "-liga"). Pure: the cell math and the tags are tested
//! on the Mac too.

const std = @import("std");

pub const max_features = 16;
const calt = tagOf("calt");
const liga = tagOf("liga");

pub const Typesetting = struct {
    line_height: f32 = 1,
    /// Points, as the settings say it; may be negative.
    letter_spacing: f32 = 0,
    /// The features as OpenType tags (a 4-byte value as DirectWrite reads
    /// it) and whether each is on.
    tags: [max_features]u32 = undefined,
    on: [max_features]bool = undefined,
    count: usize = 0,

    /// From settings.json's list; malformed entries are skipped (the
    /// settings already dropped them when reading).
    pub fn init(line_height: f32, letter_spacing: f32, features: []const []const u8) Typesetting {
        var t: Typesetting = .{ .line_height = line_height, .letter_spacing = letter_spacing };
        for (features) |f| {
            if (t.count == max_features) break;
            const off = f.len > 0 and f[0] == '-';
            const tag = parseTag(if (off) f[1..] else f) orelse continue;
            t.tags[t.count] = tag;
            t.on[t.count] = !off;
            t.count += 1;
        }
        return t;
    }

    /// "calt" or "liga" on: neighbouring symbols are set together, so "->"
    /// can become one arrow across two cells.
    pub fn joinsLetters(self: *const Typesetting) bool {
        for (self.tags[0..self.count], self.on[0..self.count]) |tag, on| {
            if (on and (tag == calt or tag == liga)) return true;
        }
        return false;
    }

    /// One number for "is this the same font": the font is made again
    /// when it changes.
    pub fn key(self: *const Typesetting) u64 {
        var h = std.hash.Wyhash.init(0);
        h.update(std.mem.asBytes(&self.line_height));
        h.update(std.mem.asBytes(&self.letter_spacing));
        h.update(std.mem.sliceAsBytes(self.tags[0..self.count]));
        h.update(std.mem.sliceAsBytes(self.on[0..self.count]));
        return h.final();
    }
};

/// DWRITE_MAKE_OPENTYPE_TAG: the first letter in the lowest byte.
pub fn tagOf(text: *const [4]u8) u32 {
    return @as(u32, text[0]) | @as(u32, text[1]) << 8 | @as(u32, text[2]) << 16 | @as(u32, text[3]) << 24;
}

fn parseTag(text: []const u8) ?u32 {
    if (text.len != 4) return null;
    for (text) |ch| if (!std.ascii.isAlphanumeric(ch)) return null;
    return tagOf(text[0..4]);
}

/// The font's own measures, in pixels, before the typesetting.
pub const Natural = struct {
    advance: f32,
    ascent: f32,
    descent: f32,
    gap: f32,
};

/// The cell from the font's measures and the typesetting, in whole pixels.
pub const Cell = struct {
    width: f32,
    height: f32,
    baseline: f32,
    /// Where a glyph starts inside its cell: half the letter spacing, so
    /// the letters stay centered in wider (or narrower) cells.
    glyph_offset: f32,
};

/// `px_per_point` turns the letter spacing into pixels (4/3 × the window's
/// scale on Windows, where a point is 4/3 of a pixel at 96 dpi). The extra
/// height splits above and below the text, so the baseline moves by half.
pub fn cell(n: Natural, t: Typesetting, px_per_point: f32) Cell {
    const natural_h = @round(n.ascent + n.descent + n.gap);
    const height = @max(@round((n.ascent + n.descent + n.gap) * t.line_height), 1);
    const advance = @max(@round(n.advance), 1);
    const width = @max(@round(n.advance + t.letter_spacing * px_per_point), 1);
    return .{
        .width = width,
        .height = height,
        .baseline = @round(n.ascent + n.gap / 2) + @floor((height - natural_h) / 2),
        .glyph_offset = @floor((width - advance) / 2),
    };
}

const testing = std.testing;
const sample: Natural = .{ .advance = 8.4, .ascent = 13.2, .descent = 3.4, .gap = 0 };

test "plain typesetting gives the font's own cell" {
    const c = cell(sample, .{}, 1);
    try testing.expectEqual(@as(f32, 8), c.width);
    try testing.expectEqual(@as(f32, 17), c.height);
    try testing.expectEqual(@as(f32, 13), c.baseline);
    try testing.expectEqual(@as(f32, 0), c.glyph_offset);
}

test "line height grows the cell and moves the baseline by half" {
    const c = cell(sample, Typesetting.init(1.5, 0, &.{}), 1);
    try testing.expectEqual(@as(f32, 25), c.height);
    try testing.expectEqual(@as(f32, 13 + 4), c.baseline);
    const tight = cell(sample, Typesetting.init(0.8, 0, &.{}), 1);
    try testing.expectEqual(@as(f32, 13), tight.height);
    try testing.expect(tight.baseline < 13);
}

test "letter spacing widens the cell and centers the glyph" {
    const c = cell(sample, Typesetting.init(1, 3, &.{}), 4.0 / 3.0);
    try testing.expectEqual(@as(f32, 12), c.width);
    try testing.expectEqual(@as(f32, 2), c.glyph_offset);
    const narrow = cell(sample, Typesetting.init(1, -1, &.{}), 1);
    try testing.expectEqual(@as(f32, 7), narrow.width);
    try testing.expectEqual(@as(f32, -1), narrow.glyph_offset);
}

test "features: tags on and off, ligatures only with calt or liga on" {
    const t = Typesetting.init(1, 0, &.{ "ss01", "-liga", "bad", "zero" });
    try testing.expectEqual(@as(usize, 3), t.count);
    try testing.expect(!t.on[1]);
    try testing.expect(!t.joinsLetters());
    try testing.expect(Typesetting.init(1, 0, &.{"calt"}).joinsLetters());
    try testing.expect(t.key() != Typesetting.init(1, 0, &.{"ss01"}).key());
    try testing.expectEqual(@as(u32, 0x746c6163), tagOf("calt"));
}
