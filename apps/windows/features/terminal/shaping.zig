//! The font's OpenType features on Windows (terminal.fontFeatures, plan 15
//! phase C): glyph ids shaped by DirectWrite's text analyzer with the
//! features on or off, for a single character ("ss01", "zero") and for a
//! run of symbols that a programming font may join ("->" with "calt").
//! The script of the run comes from AnalyzeScript once, on a sample of
//! symbols: the runs are always ASCII symbols (the Common script).

const std = @import("std");
const w = @import("win32");
const Typesetting = @import("typesetting.zig").Typesetting;

const c = w.c;

/// The most glyphs a shaped run may give (runs are at most 8 cells).
pub const max_glyphs = 32;

pub const Shaper = struct {
    analyzer: *c.IDWriteTextAnalyzer,
    script: c.DWRITE_SCRIPT_ANALYSIS = .{},
    features: [@import("typesetting.zig").max_features]c.DWRITE_FONT_FEATURE = undefined,
    count: u32 = 0,

    pub fn init(factory: *c.IDWriteFactory5, t: Typesetting) !Shaper {
        var analyzer: [*c]c.IDWriteTextAnalyzer = null;
        try w.check(w.call(factory, "CreateTextAnalyzer", .{&analyzer}));
        var self: Shaper = .{ .analyzer = analyzer };
        for (0..t.count) |i| self.features[i] = .{ .nameTag = t.tags[i], .parameter = @intFromBool(t.on[i]) };
        self.count = @intCast(t.count);
        self.script = analyzeScript(self.analyzer, std.unicode.utf8ToUtf16LeStringLiteral("->"));
        return self;
    }

    pub fn deinit(self: *Shaper) void {
        w.release(self.analyzer);
    }

    /// The glyph ids of `text` in `face` with the features; how many went
    /// into `out`, or null when DirectWrite could not shape it.
    pub fn shape(self: *Shaper, face: *c.IDWriteFontFace, text: []const u16, out: *[max_glyphs]u16) ?usize {
        if (text.len == 0 or text.len > 16) return null;
        var clusters: [16]u16 = undefined;
        var text_props: [16]u16 = undefined;
        var glyph_props: [max_glyphs]u16 = undefined;
        var actual: u32 = 0;
        var typographic: c.DWRITE_TYPOGRAPHIC_FEATURES = .{ .features = &self.features, .featureCount = self.count };
        var ranges = [1][*c]const c.DWRITE_TYPOGRAPHIC_FEATURES{&typographic};
        const lengths = [1]u32{@intCast(text.len)};
        const with = self.count > 0;
        const range_ptr: [*c][*c]const c.DWRITE_TYPOGRAPHIC_FEATURES = if (with) &ranges else null;
        const length_ptr: [*c]const u32 = if (with) &lengths else null;
        const hr = w.call(self.analyzer, "GetGlyphs", .{
            text.ptr,                   @as(u32, @intCast(text.len)),
            face,                       @as(c.WINBOOL, 0),
            @as(c.WINBOOL, 0),          &self.script,
            w.L("en-us"),               null,
            range_ptr,                  length_ptr,
            @as(u32, if (with) 1 else 0), @as(u32, max_glyphs),
            &clusters,                  @as(?*c.DWRITE_SHAPING_TEXT_PROPERTIES, @ptrCast(&text_props)),
            out,                        @as(?*c.DWRITE_SHAPING_GLYPH_PROPERTIES, @ptrCast(&glyph_props)),
            &actual,
        });
        if (hr < 0) return null;
        return actual;
    }
};

// ---- AnalyzeScript's source and sink: the least of each interface ----

const Source = extern struct {
    base: c.IDWriteTextAnalysisSource,
    text: [*]const u16,
    len: u32,

    fn of(this: [*c]c.IDWriteTextAnalysisSource) *Source {
        return @ptrCast(@alignCast(this));
    }
    fn queryInterface(_: [*c]c.IDWriteTextAnalysisSource, _: [*c]const c.IID, out: [*c]?*anyopaque) callconv(.c) c.HRESULT {
        out.* = null;
        return @bitCast(@as(u32, 0x80004002)); // E_NOINTERFACE: nothing beyond this interface.
    }
    fn addRef(_: [*c]c.IDWriteTextAnalysisSource) callconv(.c) c.ULONG {
        return 1;
    }
    fn release(_: [*c]c.IDWriteTextAnalysisSource) callconv(.c) c.ULONG {
        return 1;
    }
    fn textAt(this: [*c]c.IDWriteTextAnalysisSource, pos: u32, text: [*c][*c]const c.WCHAR, len: [*c]u32) callconv(.c) c.HRESULT {
        const s = of(this);
        text.* = if (pos < s.len) s.text + pos else null;
        len.* = if (pos < s.len) s.len - pos else 0;
        return 0;
    }
    fn textBefore(this: [*c]c.IDWriteTextAnalysisSource, pos: u32, text: [*c][*c]const c.WCHAR, len: [*c]u32) callconv(.c) c.HRESULT {
        const s = of(this);
        text.* = if (pos > 0 and pos <= s.len) s.text else null;
        len.* = if (pos > 0 and pos <= s.len) pos else 0;
        return 0;
    }
    fn direction(_: [*c]c.IDWriteTextAnalysisSource) callconv(.c) c.DWRITE_READING_DIRECTION {
        return c.DWRITE_READING_DIRECTION_LEFT_TO_RIGHT;
    }
    fn locale(this: [*c]c.IDWriteTextAnalysisSource, pos: u32, len: [*c]u32, name: [*c][*c]const c.WCHAR) callconv(.c) c.HRESULT {
        len.* = of(this).len -| pos;
        name.* = w.L("en-us");
        return 0;
    }
    fn numbers(this: [*c]c.IDWriteTextAnalysisSource, pos: u32, len: [*c]u32, sub: [*c][*c]c.IDWriteNumberSubstitution) callconv(.c) c.HRESULT {
        len.* = of(this).len -| pos;
        sub.* = null;
        return 0;
    }
    const vtbl: c.IDWriteTextAnalysisSourceVtbl = .{
        .QueryInterface = queryInterface,
        .AddRef = addRef,
        .Release = release,
        .GetTextAtPosition = textAt,
        .GetTextBeforePosition = textBefore,
        .GetParagraphReadingDirection = direction,
        .GetLocaleName = locale,
        .GetNumberSubstitution = numbers,
    };
};

const Sink = extern struct {
    base: c.IDWriteTextAnalysisSink,
    script: c.DWRITE_SCRIPT_ANALYSIS = .{},

    fn queryInterface(_: [*c]c.IDWriteTextAnalysisSink, _: [*c]const c.IID, out: [*c]?*anyopaque) callconv(.c) c.HRESULT {
        out.* = null;
        return @bitCast(@as(u32, 0x80004002));
    }
    fn addRef(_: [*c]c.IDWriteTextAnalysisSink) callconv(.c) c.ULONG {
        return 1;
    }
    fn release(_: [*c]c.IDWriteTextAnalysisSink) callconv(.c) c.ULONG {
        return 1;
    }
    fn setScript(this: [*c]c.IDWriteTextAnalysisSink, _: u32, _: u32, analysis: [*c]const c.DWRITE_SCRIPT_ANALYSIS) callconv(.c) c.HRESULT {
        const s: *Sink = @ptrCast(@alignCast(this));
        s.script = analysis.*;
        return 0;
    }
    fn breakpoints(_: [*c]c.IDWriteTextAnalysisSink, _: u32, _: u32, _: ?*const c.DWRITE_LINE_BREAKPOINT) callconv(.c) c.HRESULT {
        return 0;
    }
    fn bidi(_: [*c]c.IDWriteTextAnalysisSink, _: u32, _: u32, _: u8, _: u8) callconv(.c) c.HRESULT {
        return 0;
    }
    fn numbers(_: [*c]c.IDWriteTextAnalysisSink, _: u32, _: u32, _: [*c]c.IDWriteNumberSubstitution) callconv(.c) c.HRESULT {
        return 0;
    }
    const vtbl: c.IDWriteTextAnalysisSinkVtbl = .{
        .QueryInterface = queryInterface,
        .AddRef = addRef,
        .Release = release,
        .SetScriptAnalysis = setScript,
        .SetLineBreakpoints = breakpoints,
        .SetBidiLevel = bidi,
        .SetNumberSubstitution = numbers,
    };
};

/// The script DirectWrite gives `sample`; a zeroed analysis (the default
/// script) if it fails.
fn analyzeScript(analyzer: *c.IDWriteTextAnalyzer, sample: []const u16) c.DWRITE_SCRIPT_ANALYSIS {
    var source: Source = .{ .base = .{ .lpVtbl = @constCast(&Source.vtbl) }, .text = sample.ptr, .len = @intCast(sample.len) };
    var sink: Sink = .{ .base = .{ .lpVtbl = @constCast(&Sink.vtbl) } };
    _ = w.call(analyzer, "AnalyzeScript", .{ &source.base, @as(u32, 0), @as(u32, @intCast(sample.len)), &sink.base });
    return sink.script;
}

test {
    w.refAllDeep(@This());
}
