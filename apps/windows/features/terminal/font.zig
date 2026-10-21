//! The terminal's font: its four faces (regular, bold, italic, both), the
//! cell size they give with the typesetting (line height, letter spacing),
//! and the glyph of each code point, cached, shaped with the font's
//! OpenType features when there are any. A code point the font lacks
//! (emoji, CJK) has no glyph here: the renderer draws that cell with a
//! DirectWrite layout, which falls back to another font. Runs of symbols a
//! font joins ("->" with "calt") come from `ligature`.

const std = @import("std");
const w = @import("win32");
const typesetting = @import("typesetting.zig");
const shaping = @import("shaping.zig");
const c = w.c;

pub const Typesetting = typesetting.Typesetting;

/// Windows 11 ships it; the Mac's "SF Mono" in a shared settings.json lands here.
pub const fallback_family = "Cascadia Mono";

pub const Style = enum(u2) { regular = 0, bold = 1, italic = 2, bold_italic = 3 };

pub const Metrics = struct {
    /// Pixels, whole, so cells stay on the pixel grid (the text is sharp).
    cell_width: f32,
    cell_height: f32,
    /// From the cell's top to the baseline.
    baseline: f32,
    underline_offset: f32,
    underline_thickness: f32,
    strike_offset: f32,
    /// The em size the faces are drawn at, in pixels.
    em: f32,
    /// Where a glyph starts inside its cell (half the letter spacing).
    glyph_offset: f32 = 0,
};

/// The longest run of symbols drawn as one (QuadBuilder+Ligatures.swift):
/// longer ones are rare and would fill the cache with one-off runs.
pub const longest_run = 8;
const max_cached_runs = 4096;

/// A run of symbols as the font shapes it: `count` 0 when the font sets it
/// letter by letter (nothing to join).
pub const Joined = struct {
    count: u8 = 0,
    glyphs: [shaping.max_glyphs]u16 = undefined,

    pub fn slice(self: *const Joined) []const u16 {
        return self.glyphs[0..self.count];
    }
};

const RunKey = struct { style: Style, len: u8, bytes: [longest_run]u8 };

pub const Glyph = struct { index: u16, style: Style };

pub const Font = struct {
    gpa: std.mem.Allocator,
    faces: [4]*c.IDWriteFontFace,
    metrics: Metrics,
    family: []u8,
    glyphs: std.AutoHashMapUnmanaged(u32, u16) = .empty,
    /// Only with features in the settings: the font's own glyphs otherwise.
    shaper: ?shaping.Shaper = null,
    joins_letters: bool = false,
    runs: std.AutoHashMapUnmanaged(RunKey, Joined) = .empty,

    /// `points` is the settings' size; at 96 dpi a point is 4/3 pixel, as
    /// Windows Terminal sizes its font.
    pub fn init(gpa: std.mem.Allocator, factory: *c.IDWriteFactory5, family: []const u8, points: f32, scale: f32, t: Typesetting) !Font {
        var collection: [*c]c.IDWriteFontCollection = null;
        try w.check(w.call(factory, "GetSystemFontCollection", .{ &collection, 0 }));
        defer w.release(collection);
        const chosen = if (hasFamily(collection, family)) family else fallback_family;
        var faces: [4]*c.IDWriteFontFace = undefined;
        for (&faces, 0..) |*face, i| {
            const style: Style = @enumFromInt(i);
            face.* = try openFace(collection, chosen, style);
        }
        const em = @round(points * 4.0 / 3.0 * scale);
        const name = try gpa.dupe(u8, chosen);
        // A shaper that fails leaves the font's own glyphs: features are a nicety.
        const shaper: ?shaping.Shaper = if (t.count > 0) shaping.Shaper.init(factory, t) catch null else null;
        return .{
            .gpa = gpa,
            .faces = faces,
            .metrics = measure(faces[0], em, t, 4.0 / 3.0 * scale),
            .family = name,
            .shaper = shaper,
            .joins_letters = shaper != null and t.joinsLetters(),
        };
    }

    pub fn deinit(self: *Font) void {
        for (self.faces) |f| w.release(f);
        self.glyphs.deinit(self.gpa);
        self.runs.deinit(self.gpa);
        if (self.shaper) |*s| s.deinit();
        self.gpa.free(self.family);
    }

    /// The glyph of `cp` in `style`, or null when the font does not have it.
    pub fn glyph(self: *Font, cp: u21, style: Style) ?u16 {
        const key = (@as(u32, cp) << 2) | @intFromEnum(style);
        if (self.glyphs.get(key)) |g| return if (g == 0) null else g;
        var index: u16 = 0;
        const codepoint: u32 = cp;
        _ = w.call(self.faces[@intFromEnum(style)], "GetGlyphIndicesW", .{ &codepoint, 1, &index });
        // "ss01", "zero": the features may pick another glyph for the letter.
        if (index != 0) if (self.shaper) |*s| {
            var units: [2]u16 = undefined;
            const len = utf16(cp, &units);
            var out: [shaping.max_glyphs]u16 = undefined;
            if (s.shape(self.faces[@intFromEnum(style)], units[0..len], &out)) |count| if (count == 1 and out[0] != 0) {
                index = out[0];
            };
        };
        self.glyphs.put(self.gpa, key, index) catch {};
        return if (index == 0) null else index;
    }

    /// `text` (2 to 8 ASCII symbols, one per cell) as the font shapes it
    /// with the features, when that differs from letter by letter: a
    /// ligature or contextual alternates (GlyphAtlas.joins on the Mac).
    pub fn ligature(self: *Font, text: []const u8, style: Style) ?*const Joined {
        if (text.len < 2 or text.len > longest_run) return null;
        var key: RunKey = .{ .style = style, .len = @intCast(text.len), .bytes = @splat(0) };
        @memcpy(key.bytes[0..text.len], text);
        // Distinct runs are few in practice; a cap keeps a long session bounded.
        if (self.runs.count() >= max_cached_runs) self.runs.clearRetainingCapacity();
        const entry = self.runs.getOrPut(self.gpa, key) catch return null;
        if (!entry.found_existing) entry.value_ptr.* = self.shapeRun(text, style);
        return if (entry.value_ptr.count == 0) null else entry.value_ptr;
    }

    fn shapeRun(self: *Font, text: []const u8, style: Style) Joined {
        var joined: Joined = .{};
        const s = &(self.shaper orelse return joined);
        var units: [longest_run]u16 = undefined;
        for (text, 0..) |ch, i| units[i] = ch;
        const count = s.shape(self.faces[@intFromEnum(style)], units[0..text.len], &joined.glyphs) orelse return .{};
        var same = count == text.len;
        if (same) for (text, 0..) |ch, i| {
            if (self.glyph(ch, style) != joined.glyphs[i]) same = false;
        };
        if (same) return .{};
        joined.count = @intCast(count);
        return joined;
    }
};

/// `cp` in UTF-16, one unit or a surrogate pair; how many units.
fn utf16(cp: u21, out: *[2]u16) usize {
    if (cp < 0x10000) {
        out[0] = @intCast(cp);
        return 1;
    }
    const v = cp - 0x10000;
    out[0] = @intCast(0xD800 + (v >> 10));
    out[1] = @intCast(0xDC00 + (v & 0x3ff));
    return 2;
}

fn hasFamily(collection: *c.IDWriteFontCollection, family: []const u8) bool {
    var name: [128:0]u16 = undefined;
    const n = std.unicode.wtf8ToWtf16Le(&name, family) catch return false;
    name[n] = 0;
    var index: c.UINT32 = 0;
    var exists: c.BOOL = 0;
    if (w.call(collection, "FindFamilyName", .{ &name, &index, &exists }) < 0) return false;
    return exists != 0;
}

fn openFace(collection: *c.IDWriteFontCollection, family: []const u8, style: Style) !*c.IDWriteFontFace {
    var name: [128:0]u16 = undefined;
    const n = std.unicode.wtf8ToWtf16Le(&name, family) catch return error.ComFailed;
    name[n] = 0;
    var index: c.UINT32 = 0;
    var exists: c.BOOL = 0;
    try w.check(w.call(collection, "FindFamilyName", .{ &name, &index, &exists }));
    if (exists == 0) return error.ComFailed;
    var family_ptr: [*c]c.IDWriteFontFamily = null;
    try w.check(w.call(collection, "GetFontFamily", .{ index, &family_ptr }));
    defer w.release(family_ptr);
    const bold = style == .bold or style == .bold_italic;
    const italic = style == .italic or style == .bold_italic;
    var font: [*c]c.IDWriteFont = null;
    try w.check(w.call(family_ptr, "GetFirstMatchingFont", .{
        if (bold) c.DWRITE_FONT_WEIGHT_BOLD else c.DWRITE_FONT_WEIGHT_NORMAL,
        c.DWRITE_FONT_STRETCH_NORMAL,
        if (italic) c.DWRITE_FONT_STYLE_ITALIC else c.DWRITE_FONT_STYLE_NORMAL,
        &font,
    }));
    defer w.release(font);
    var face: [*c]c.IDWriteFontFace = null;
    try w.check(w.call(font, "CreateFontFace", .{&face}));
    return face;
}

/// Cell size from the font's design metrics: the advance of "0" for the
/// width, ascent + descent + line gap for the height, then the
/// typesetting's line height and letter spacing, in whole pixels.
fn measure(face: *c.IDWriteFontFace, em: f32, t: Typesetting, px_per_point: f32) Metrics {
    var fm: c.DWRITE_FONT_METRICS = undefined;
    w.call(face, "GetMetrics", .{&fm});
    const units: f32 = @floatFromInt(fm.designUnitsPerEm);
    const k = em / units;
    var zero_glyph: u16 = 0;
    const zero: u32 = '0';
    _ = w.call(face, "GetGlyphIndicesW", .{ &zero, 1, &zero_glyph });
    var gm: c.DWRITE_GLYPH_METRICS = undefined;
    _ = w.call(face, "GetDesignGlyphMetrics", .{ &zero_glyph, 1, &gm, 0 });
    const natural: typesetting.Natural = .{
        .advance = @as(f32, @floatFromInt(gm.advanceWidth)) * k,
        .ascent = @as(f32, @floatFromInt(fm.ascent)) * k,
        .descent = @as(f32, @floatFromInt(fm.descent)) * k,
        .gap = @as(f32, @floatFromInt(fm.lineGap)) * k,
    };
    const cell = typesetting.cell(natural, t, px_per_point);
    const baseline = cell.baseline;
    return .{
        .cell_width = cell.width,
        .cell_height = cell.height,
        .baseline = baseline,
        .glyph_offset = cell.glyph_offset,
        .underline_offset = baseline - @as(f32, @floatFromInt(fm.underlinePosition)) * k,
        .underline_thickness = @max(@round(@as(f32, @floatFromInt(fm.underlineThickness)) * k), 1),
        .strike_offset = baseline - @as(f32, @floatFromInt(fm.strikethroughPosition)) * k,
        .em = em,
    };
}

test {
    _ = @import("typesetting.zig");
    _ = @import("shaping.zig");
}

test {
    @import("win32").refAllDeep(@This());
}
