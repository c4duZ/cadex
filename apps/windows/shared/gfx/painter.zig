//! Drawing for every feature, on a window's Direct2D context: rectangles,
//! lines, text and icons, in window pixels. One solid brush, recolored per
//! call; text through cached DirectWrite formats (fonts.zig).

const std = @import("std");
const w = @import("win32");
const c = w.c;
const geometry = @import("geometry.zig");
const fonts_mod = @import("fonts.zig");

const Rect = geometry.Rect;
const Color = geometry.Color;
const Point = geometry.Point;
pub const Spec = fonts_mod.Spec;

/// Bytes [start, end) of a text drawn in `color` (Painter.textColored).
pub const ColorRun = struct { start: usize, end: usize, color: Color };

pub const Align = enum { leading, center, trailing };

pub const TextOptions = struct {
    @"align": Align = .leading,
    /// Centered on the rectangle's height; otherwise from its top.
    vcenter: bool = true,
    /// Cut with "…" when wider than the rectangle.
    ellipsis: bool = true,
};

pub const Painter = struct {
    context: *c.ID2D1DeviceContext,
    factory: *c.IDWriteFactory5,
    fonts: *fonts_mod.Fonts,
    brush: *c.ID2D1SolidColorBrush,
    /// Brushes for colored ranges of one layout (textColored): DirectWrite
    /// keeps a brush per range, so the one recolored brush cannot serve.
    /// Kept by color across frames; a theme has a couple dozen.
    effects: [max_effects]Effect = undefined,
    effect_count: usize = 0,
    /// Embedded images (the Material file icons) made into bitmaps once,
    /// by the address of their bytes.
    bitmaps: std.AutoHashMapUnmanaged(usize, *c.ID2D1Bitmap) = .empty,
    gpa: std.mem.Allocator = std.heap.page_allocator,
    /// Scratch for UTF-16 conversions; text longer than this is cut.
    wide: [4096]u16 = undefined,

    pub fn init(context: *c.ID2D1DeviceContext, factory: *c.IDWriteFactory5, fonts: *fonts_mod.Fonts) !Painter {
        var brush: [*c]c.ID2D1SolidColorBrush = null;
        const color: c.D2D1_COLOR_F = .{ .r = 0, .g = 0, .b = 0, .a = 1 };
        try w.check(w.call(context, "CreateSolidColorBrush", .{ &color, null, &brush }));
        return .{ .context = context, .factory = factory, .fonts = fonts, .brush = brush };
    }

    pub fn deinit(self: *Painter) void {
        w.release(self.brush);
        self.releaseEffects();
        var it = self.bitmaps.valueIterator();
        while (it.next()) |b| w.release(b.*);
        self.bitmaps.deinit(self.gpa);
    }

    const max_effects = 48;
    const Effect = struct { key: u32, brush: *c.ID2D1SolidColorBrush };

    fn releaseEffects(self: *Painter) void {
        for (self.effects[0..self.effect_count]) |e| w.release(e.brush);
        self.effect_count = 0;
    }

    /// A brush of its own for `color`, made once.
    fn effectBrush(self: *Painter, color: Color) ?*c.ID2D1SolidColorBrush {
        const key = colorKey(color);
        for (self.effects[0..self.effect_count]) |e| if (e.key == key) return e.brush;
        if (self.effect_count == max_effects) self.releaseEffects();
        var brush: [*c]c.ID2D1SolidColorBrush = null;
        const value: c.D2D1_COLOR_F = .{ .r = color.r, .g = color.g, .b = color.b, .a = color.a };
        if (w.call(self.context, "CreateSolidColorBrush", .{ &value, null, &brush }) < 0 or brush == null) return null;
        self.effects[self.effect_count] = .{ .key = key, .brush = brush };
        self.effect_count += 1;
        return brush;
    }

    fn colorKey(color: Color) u32 {
        const byte = struct {
            fn of(v: f32) u32 {
                return @intFromFloat(std.math.clamp(v, 0, 1) * 255 + 0.5);
            }
        }.of;
        return byte(color.r) << 24 | byte(color.g) << 16 | byte(color.b) << 8 | byte(color.a);
    }

    fn paint(self: *Painter, color: Color) *c.ID2D1Brush {
        const value: c.D2D1_COLOR_F = .{ .r = color.r, .g = color.g, .b = color.b, .a = color.a };
        w.call(self.brush, "SetColor", .{&value});
        return @ptrCast(self.brush);
    }

    fn rectF(r: Rect) c.D2D1_RECT_F {
        return .{ .left = r.x, .top = r.y, .right = r.x + r.w, .bottom = r.y + r.h };
    }

    pub fn clear(self: *Painter, color: Color) void {
        const value: c.D2D1_COLOR_F = .{ .r = color.r * color.a, .g = color.g * color.a, .b = color.b * color.a, .a = color.a };
        w.call(self.context, "Clear", .{&value});
    }

    pub fn fill(self: *Painter, r: Rect, color: Color) void {
        if (color.a <= 0 or r.w <= 0 or r.h <= 0) return;
        const rect = rectF(r);
        w.call(self.context, "FillRectangle", .{ &rect, self.paint(color) });
    }

    pub fn fillRounded(self: *Painter, r: Rect, radius: f32, color: Color) void {
        if (color.a <= 0 or r.w <= 0 or r.h <= 0) return;
        const rounded: c.D2D1_ROUNDED_RECT = .{ .rect = rectF(r), .radiusX = radius, .radiusY = radius };
        w.call(self.context, "FillRoundedRectangle", .{ &rounded, self.paint(color) });
    }

    /// A border inside `r`, `width` pixels thick.
    pub fn stroke(self: *Painter, r: Rect, radius: f32, color: Color, width: f32) void {
        if (color.a <= 0) return;
        const half = width / 2;
        const rounded: c.D2D1_ROUNDED_RECT = .{ .rect = rectF(r.inset(half, half)), .radiusX = radius, .radiusY = radius };
        w.call(self.context, "DrawRoundedRectangle", .{ &rounded, self.paint(color), width, null });
    }

    pub fn line(self: *Painter, from: Point, to: Point, color: Color, width: f32) void {
        const a: c.D2D1_POINT_2F = .{ .x = from.x, .y = from.y };
        const b: c.D2D1_POINT_2F = .{ .x = to.x, .y = to.y };
        w.call(self.context, "DrawLine", .{ a, b, self.paint(color), width, null });
    }

    pub fn fillEllipse(self: *Painter, center: Point, rx: f32, ry: f32, color: Color) void {
        const ellipse: c.D2D1_ELLIPSE = .{ .point = .{ .x = center.x, .y = center.y }, .radiusX = rx, .radiusY = ry };
        w.call(self.context, "FillEllipse", .{ &ellipse, self.paint(color) });
    }

    /// Clips what follows to `r`, until popClip.
    pub fn pushClip(self: *Painter, r: Rect) void {
        const rect = rectF(r);
        w.call(self.context, "PushAxisAlignedClip", .{ &rect, c.D2D1_ANTIALIAS_MODE_ALIASED });
    }

    pub fn popClip(self: *Painter) void {
        w.call(self.context, "PopAxisAlignedClip", .{});
    }

    fn toWide(self: *Painter, value: []const u8) []const u16 {
        return utf16(&self.wide, value);
    }

    /// A layout of `text` for drawing or measuring; release when done.
    pub fn layout(self: *Painter, value: []const u8, spec: Spec, max_width: f32, max_height: f32) !*c.IDWriteTextLayout {
        const format = try self.fonts.format(spec);
        const wide = self.toWide(value);
        var made: [*c]c.IDWriteTextLayout = null;
        try w.check(w.call(self.factory, "CreateTextLayout", .{ wide.ptr, @as(c.UINT32, @intCast(wide.len)), format, max_width, max_height, &made }));
        return made;
    }

    /// The width `text` takes in `spec`, in pixels.
    pub fn measure(self: *Painter, value: []const u8, spec: Spec) f32 {
        const made = self.layout(value, spec, 100_000, 1000) catch return 0;
        defer w.release(made);
        var metrics: c.DWRITE_TEXT_METRICS = undefined;
        if (w.call(made, "GetMetrics", .{&metrics}) < 0) return 0;
        return metrics.widthIncludingTrailingWhitespace;
    }

    pub fn text(self: *Painter, value: []const u8, spec: Spec, r: Rect, color: Color, options: TextOptions) void {
        if (value.len == 0 or r.w <= 0) return;
        const made = self.layout(value, spec, r.w, r.h) catch return;
        defer w.release(made);
        _ = w.call(made, "SetTextAlignment", .{switch (options.@"align") {
            .leading => c.DWRITE_TEXT_ALIGNMENT_LEADING,
            .center => c.DWRITE_TEXT_ALIGNMENT_CENTER,
            .trailing => c.DWRITE_TEXT_ALIGNMENT_TRAILING,
        }});
        if (options.vcenter) _ = w.call(made, "SetParagraphAlignment", .{c.DWRITE_PARAGRAPH_ALIGNMENT_CENTER});
        if (options.ellipsis) self.trimWithEllipsis(made);
        const origin: c.D2D1_POINT_2F = .{ .x = r.x, .y = r.y };
        w.call(self.context, "DrawTextLayout", .{ origin, made, self.paint(color), c.D2D1_DRAW_TEXT_OPTIONS_ENABLE_COLOR_FONT | c.D2D1_DRAW_TEXT_OPTIONS_CLIP });
    }

    /// Text with some code points in bold (the letters a search matched),
    /// given as byte offsets into `value`.
    pub fn textBold(self: *Painter, value: []const u8, spec: Spec, r: Rect, color: Color, bold: []const u32) void {
        if (bold.len == 0) return self.text(value, spec, r, color, .{});
        if (value.len == 0 or r.w <= 0) return;
        const made = self.layout(value, spec, r.w, r.h) catch return;
        defer w.release(made);
        _ = w.call(made, "SetParagraphAlignment", .{c.DWRITE_PARAGRAPH_ALIGNMENT_CENTER});
        for (bold) |at| {
            if (at >= value.len) continue;
            const len = std.unicode.utf8ByteSequenceLength(value[at]) catch 1;
            const range: c.DWRITE_TEXT_RANGE = .{ .startPosition = utf16Index(value, at), .length = if (len == 4) 2 else 1 };
            _ = w.call(made, "SetFontWeight", .{ c.DWRITE_FONT_WEIGHT_BOLD, range });
        }
        self.trimWithEllipsis(made);
        const origin: c.D2D1_POINT_2F = .{ .x = r.x, .y = r.y };
        w.call(self.context, "DrawTextLayout", .{ origin, made, self.paint(color), c.D2D1_DRAW_TEXT_OPTIONS_ENABLE_COLOR_FONT | c.D2D1_DRAW_TEXT_OPTIONS_CLIP });
    }

    /// One line of text from `r`'s left edge, centered on its height, in
    /// `color` except the byte ranges of `runs` (a code view's tokens). One
    /// layout for the line, so the glyphs sit as one run would put them.
    pub fn textColored(self: *Painter, value: []const u8, spec: Spec, r: Rect, color: Color, runs: []const ColorRun) void {
        if (value.len == 0 or r.w <= 0) return;
        const made = self.layout(value, spec, 100_000, r.h) catch return;
        defer w.release(made);
        _ = w.call(made, "SetParagraphAlignment", .{c.DWRITE_PARAGRAPH_ALIGNMENT_CENTER});
        for (runs) |run| {
            if (run.end <= run.start or run.start >= value.len) continue;
            const brush = self.effectBrush(run.color) orelse continue;
            const from = utf16Index(value, run.start);
            const range: c.DWRITE_TEXT_RANGE = .{ .startPosition = from, .length = utf16Index(value, @min(run.end, value.len)) - from };
            _ = w.call(made, "SetDrawingEffect", .{ @as(*c.IUnknown, @ptrCast(brush)), range });
        }
        const origin: c.D2D1_POINT_2F = .{ .x = r.x, .y = r.y };
        w.call(self.context, "DrawTextLayout", .{ origin, made, self.paint(color), c.D2D1_DRAW_TEXT_OPTIONS_ENABLE_COLOR_FONT });
    }

    fn trimWithEllipsis(self: *Painter, made: *c.IDWriteTextLayout) void {
        var sign: [*c]c.IDWriteInlineObject = null;
        if (w.call(self.factory, "CreateEllipsisTrimmingSign", .{ @as(*c.IDWriteTextFormat, @ptrCast(made)), &sign }) < 0) return;
        defer w.release(sign);
        const trimming: c.DWRITE_TRIMMING = .{ .granularity = c.DWRITE_TRIMMING_GRANULARITY_CHARACTER, .delimiter = 0, .delimiterCount = 0 };
        _ = w.call(made, "SetTrimming", .{ &trimming, sign });
    }

    /// The x of the caret before byte `at` of `value`, from its left edge.
    pub fn caretX(self: *Painter, value: []const u8, spec: Spec, at: usize) f32 {
        if (at == 0 or value.len == 0) return 0;
        const made = self.layout(value, spec, 100_000, 1000) catch return 0;
        defer w.release(made);
        var x: f32 = 0;
        var y: f32 = 0;
        var metrics: c.DWRITE_HIT_TEST_METRICS = undefined;
        _ = w.call(made, "HitTestTextPosition", .{ utf16Index(value, at), 0, &x, &y, &metrics });
        return x;
    }

    /// The byte of `value` nearest to `x` (a click in a field).
    pub fn hitIndex(self: *Painter, value: []const u8, spec: Spec, x: f32) usize {
        if (value.len == 0) return 0;
        const made = self.layout(value, spec, 100_000, 1000) catch return 0;
        defer w.release(made);
        var trailing: c.BOOL = 0;
        var inside: c.BOOL = 0;
        var metrics: c.DWRITE_HIT_TEST_METRICS = undefined;
        if (w.call(made, "HitTestPoint", .{ x, 1, &trailing, &inside, &metrics }) < 0) return value.len;
        const pos = metrics.textPosition + if (trailing != 0) metrics.length else 0;
        return byteIndex(value, pos);
    }

    /// Glyphs of one font face on one baseline, each `advance` apart (the
    /// terminal's cells): the fast path for text on a grid.
    pub fn glyphRun(self: *Painter, face: *c.IDWriteFontFace, em: f32, glyphs: []const u16, advances: []const f32, origin: Point, color: Color) void {
        if (glyphs.len == 0) return;
        const run: c.DWRITE_GLYPH_RUN = .{
            .fontFace = face,
            .fontEmSize = em,
            .glyphCount = @intCast(glyphs.len),
            .glyphIndices = glyphs.ptr,
            .glyphAdvances = advances.ptr,
            .glyphOffsets = null,
            .isSideways = 0,
            .bidiLevel = 0,
        };
        const at: c.D2D1_POINT_2F = .{ .x = origin.x, .y = origin.y };
        w.call(self.context, "DrawGlyphRun", .{ at, &run, null, self.paint(color), c.DWRITE_MEASURING_MODE_NATURAL });
    }

    /// An embedded PNG, `size` pixels square, centered in `r`, smoothly
    /// scaled (the icons come at 32 and 64 pixels). False when it could not
    /// be decoded: the caller draws something else.
    pub fn png(self: *Painter, bytes: []const u8, size: f32, r: Rect) bool {
        const bitmap = self.bitmapOf(bytes) orelse return false;
        const x = @round(r.x + (r.w - size) / 2);
        const y = @round(r.y + (r.h - size) / 2);
        const dest: c.D2D1_RECT_F = .{ .left = x, .top = y, .right = x + size, .bottom = y + size };
        w.call(self.context, "DrawBitmap", .{ bitmap, &dest, 1.0, c.D2D1_INTERPOLATION_MODE_HIGH_QUALITY_CUBIC, null, null });
        return true;
    }

    fn bitmapOf(self: *Painter, bytes: []const u8) ?*c.ID2D1Bitmap {
        const key = @intFromPtr(bytes.ptr);
        if (self.bitmaps.get(key)) |b| return b;
        const decoded = @import("wic.zig").decodeMemory(bytes) catch return null;
        defer decoded.release();
        var bitmap: [*c]c.ID2D1Bitmap1 = null;
        if (w.call(self.context, "CreateBitmapFromWicBitmap", .{ decoded.source, null, &bitmap }) < 0 or bitmap == null) return null;
        const plain: *c.ID2D1Bitmap = @ptrCast(bitmap);
        self.bitmaps.put(self.gpa, key, plain) catch {
            w.release(plain);
            return null;
        };
        return plain;
    }

    /// A Phosphor icon (its code point from icons.zig) centered in `r`.
    pub fn icon(self: *Painter, codepoint: u21, size: f32, r: Rect, color: Color) void {
        var buf: [4]u8 = undefined;
        const n = std.unicode.utf8Encode(codepoint, &buf) catch return;
        self.text(buf[0..n], .{ .family = "Phosphor", .size = size, .embedded = true }, r, color, .{ .@"align" = .center, .ellipsis = false });
    }
};

/// The UTF-16 index of byte `at` of UTF-8 `value`.
pub fn utf16Index(value: []const u8, at: usize) u32 {
    var n: u32 = 0;
    var i: usize = 0;
    while (i < at and i < value.len) {
        const len = std.unicode.utf8ByteSequenceLength(value[i]) catch 1;
        n += if (len == 4) 2 else 1;
        i += len;
    }
    return n;
}

/// The byte of UTF-8 `value` at UTF-16 index `pos`.
pub fn byteIndex(value: []const u8, pos: u32) usize {
    var n: u32 = 0;
    var i: usize = 0;
    while (i < value.len and n < pos) {
        const len = std.unicode.utf8ByteSequenceLength(value[i]) catch 1;
        n += if (len == 4) 2 else 1;
        i += len;
    }
    return @min(i, value.len);
}

/// `value` as UTF-16 in `out`, cut when it does not fit. Invalid UTF-8 (a
/// file name from an old disk) still draws, each bad byte as U+FFFD.
pub fn utf16(out: []u16, text: []const u8) []const u16 {
    var n: usize = 0;
    var i: usize = 0;
    while (i < text.len and n + 2 <= out.len) {
        const len = std.unicode.utf8ByteSequenceLength(text[i]) catch 1;
        const cp: u21 = if (i + len <= text.len)
            std.unicode.utf8Decode(text[i..][0..len]) catch 0xFFFD
        else
            0xFFFD;
        i += if (cp == 0xFFFD and len > 1) 1 else len;
        if (cp < 0x10000) {
            out[n] = @intCast(cp);
            n += 1;
        } else {
            const v = cp - 0x10000;
            out[n] = @intCast(0xD800 + (v >> 10));
            out[n + 1] = @intCast(0xDC00 + (v & 0x3FF));
            n += 2;
        }
    }
    return out[0..n];
}

test "utf16 keeps valid text and replaces bad bytes" {
    var buf: [16]u16 = undefined;
    const got = utf16(&buf, "a\xffé😀");
    try std.testing.expectEqual(@as(usize, 5), got.len);
    try std.testing.expectEqual(@as(u16, 0xFFFD), got[1]);
    try std.testing.expectEqual(@as(u16, 0xE9), got[2]);
}

test {
    @import("win32").refAllDeep(@This());
}
