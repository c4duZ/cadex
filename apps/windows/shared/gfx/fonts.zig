//! Text formats for DirectWrite, cached by family, size and weight, and the
//! app's own fonts loaded from memory (Phosphor, embedded in the exe, so
//! the install stays one file: docs/adr/0007-one-step-install.md).

const std = @import("std");
const w = @import("win32");
const c = w.c;

pub const Weight = enum(c_int) { regular = 400, medium = 500, semibold = 600, bold = 700 };

pub const Spec = struct {
    family: []const u8,
    size: f32,
    weight: Weight = .regular,
    italic: bool = false,
    /// Phosphor and other fonts the app embeds.
    embedded: bool = false,
};

const Key = struct { family: u64, size: u32, weight: Weight, italic: bool, embedded: bool };

pub const Fonts = struct {
    gpa: std.mem.Allocator,
    factory: *c.IDWriteFactory5,
    loader: *c.IDWriteInMemoryFontFileLoader,
    embedded: *c.IDWriteFontCollection1,
    formats: std.AutoHashMapUnmanaged(Key, *c.IDWriteTextFormat) = .empty,

    /// `files`: the bytes of each embedded font, alive as long as Fonts.
    pub fn init(gpa: std.mem.Allocator, factory: *c.IDWriteFactory5, files: []const []const u8) !Fonts {
        var loader: [*c]c.IDWriteInMemoryFontFileLoader = null;
        try w.check(w.call(factory, "CreateInMemoryFontFileLoader", .{&loader}));
        errdefer w.release(loader);
        try w.check(w.call(factory, "RegisterFontFileLoader", .{@as(*c.IDWriteFontFileLoader, @ptrCast(loader))}));

        var builder: [*c]c.IDWriteFontSetBuilder1 = null;
        try w.check(w.call(factory, "IDWriteFactory5_CreateFontSetBuilder", .{&builder}));
        defer w.release(builder);
        for (files) |bytes| {
            var file: [*c]c.IDWriteFontFile = null;
            try w.check(w.call(loader, "CreateInMemoryFontFileReference", .{ @as(*c.IDWriteFactory, @ptrCast(factory)), bytes.ptr, @as(c.UINT32, @intCast(bytes.len)), null, &file }));
            defer w.release(file);
            try w.check(w.call(builder, "AddFontFile", .{file}));
        }
        var set: [*c]c.IDWriteFontSet = null;
        try w.check(w.call(builder, "CreateFontSet", .{&set}));
        defer w.release(set);
        var collection: [*c]c.IDWriteFontCollection1 = null;
        try w.check(w.call(factory, "CreateFontCollectionFromFontSet", .{ set, &collection }));
        return .{ .gpa = gpa, .factory = factory, .loader = loader, .embedded = collection };
    }

    pub fn deinit(self: *Fonts) void {
        var it = self.formats.valueIterator();
        while (it.next()) |f| w.release(f.*);
        self.formats.deinit(self.gpa);
        w.release(self.embedded);
        _ = w.call(self.factory, "UnregisterFontFileLoader", .{@as(*c.IDWriteFontFileLoader, @ptrCast(self.loader))});
        w.release(self.loader);
    }

    /// The format for `spec`, made once. Sizes are in pixels.
    pub fn format(self: *Fonts, spec: Spec) !*c.IDWriteTextFormat {
        const key: Key = .{
            .family = std.hash.Wyhash.hash(0, spec.family),
            .size = @bitCast(spec.size),
            .weight = spec.weight,
            .italic = spec.italic,
            .embedded = spec.embedded,
        };
        if (self.formats.get(key)) |f| return f;
        var family_buf: [128:0]u16 = undefined;
        const n = std.unicode.wtf8ToWtf16Le(&family_buf, spec.family) catch return error.ComFailed;
        family_buf[n] = 0;
        var made: [*c]c.IDWriteTextFormat = null;
        const collection: ?*c.IDWriteFontCollection = if (spec.embedded) @ptrCast(self.embedded) else null;
        try w.check(w.call(self.factory, "CreateTextFormat", .{
            &family_buf,
            collection,
            @intFromEnum(spec.weight),
            if (spec.italic) c.DWRITE_FONT_STYLE_ITALIC else c.DWRITE_FONT_STYLE_NORMAL,
            c.DWRITE_FONT_STRETCH_NORMAL,
            spec.size,
            w.L("en-us"),
            &made,
        }));
        _ = w.call(made, "SetWordWrapping", .{c.DWRITE_WORD_WRAPPING_NO_WRAP});
        try self.formats.put(self.gpa, key, made);
        return made;
    }
};

test {
    @import("std").testing.refAllDecls(@This());
}
