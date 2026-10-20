//! The terminal's font: its four faces (regular, bold, italic, both), the
//! cell size they give, and the glyph of each code point, cached. A code
//! point the font lacks (emoji, CJK) has no glyph here: the renderer draws
//! that cell with a DirectWrite layout, which falls back to another font.

const std = @import("std");
const w = @import("win32");
const c = w.c;

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
};

pub const Glyph = struct { index: u16, style: Style };

pub const Font = struct {
    gpa: std.mem.Allocator,
    faces: [4]*c.IDWriteFontFace,
    metrics: Metrics,
    family: []u8,
    glyphs: std.AutoHashMapUnmanaged(u32, u16) = .empty,

    /// `points` is the settings' size; at 96 dpi a point is 4/3 pixel, as
    /// Windows Terminal sizes its font.
    pub fn init(gpa: std.mem.Allocator, factory: *c.IDWriteFactory5, family: []const u8, points: f32, scale: f32) !Font {
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
        return .{ .gpa = gpa, .faces = faces, .metrics = measure(faces[0], em), .family = try gpa.dupe(u8, chosen) };
    }

    pub fn deinit(self: *Font) void {
        for (self.faces) |f| w.release(f);
        self.glyphs.deinit(self.gpa);
        self.gpa.free(self.family);
    }

    /// The glyph of `cp` in `style`, or null when the font does not have it.
    pub fn glyph(self: *Font, cp: u21, style: Style) ?u16 {
        const key = (@as(u32, cp) << 2) | @intFromEnum(style);
        if (self.glyphs.get(key)) |g| return if (g == 0) null else g;
        var index: u16 = 0;
        const codepoint: u32 = cp;
        _ = w.call(self.faces[@intFromEnum(style)], "GetGlyphIndicesW", .{ &codepoint, 1, &index });
        self.glyphs.put(self.gpa, key, index) catch {};
        return if (index == 0) null else index;
    }
};

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
/// width, ascent + descent + line gap for the height, rounded to pixels.
fn measure(face: *c.IDWriteFontFace, em: f32) Metrics {
    var fm: c.DWRITE_FONT_METRICS = undefined;
    w.call(face, "GetMetrics", .{&fm});
    const units: f32 = @floatFromInt(fm.designUnitsPerEm);
    const k = em / units;
    var zero_glyph: u16 = 0;
    const zero: u32 = '0';
    _ = w.call(face, "GetGlyphIndicesW", .{ &zero, 1, &zero_glyph });
    var gm: c.DWRITE_GLYPH_METRICS = undefined;
    _ = w.call(face, "GetDesignGlyphMetrics", .{ &zero_glyph, 1, &gm, 0 });
    const ascent = @as(f32, @floatFromInt(fm.ascent)) * k;
    const descent = @as(f32, @floatFromInt(fm.descent)) * k;
    const gap = @as(f32, @floatFromInt(fm.lineGap)) * k;
    const height = @round(ascent + descent + gap);
    const baseline = @round(ascent + gap / 2);
    return .{
        .cell_width = @max(@round(@as(f32, @floatFromInt(gm.advanceWidth)) * k), 1),
        .cell_height = @max(height, 1),
        .baseline = baseline,
        .underline_offset = baseline - @as(f32, @floatFromInt(fm.underlinePosition)) * k,
        .underline_thickness = @max(@round(@as(f32, @floatFromInt(fm.underlineThickness)) * k), 1),
        .strike_offset = baseline - @as(f32, @floatFromInt(fm.strikethroughPosition)) * k,
        .em = em,
    };
}

test {
    std.testing.refAllDecls(@This());
}
