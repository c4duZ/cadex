//! The Windows Imaging Component: images in and out without a library of
//! our own. Saves a clipboard bitmap as PNG (the terminal's paste of a
//! screenshot) and decodes files to Direct2D bitmaps (media-preview).

const std = @import("std");
const w = @import("win32");
const c = w.c;

const clsid_factory = w.guid("cacaf262-9370-4615-a13b-9f5539da4c0a");
const iid_factory = w.guid("ec5ec8a9-c395-4314-9c77-54d7a935ff70");
const container_png = w.guid("1b7cfaf4-713f-473c-bbcd-6137425faeaf");
pub const pixel_bgra_premultiplied = w.guid("6fddc324-4e03-4bfe-b185-3d77768dc910");

pub fn factory() !*c.IWICImagingFactory {
    var raw: ?*anyopaque = null;
    try w.check(c.CoCreateInstance(&clsid_factory, null, c.CLSCTX_INPROC_SERVER, &iid_factory, &raw));
    return @ptrCast(@alignCast(raw.?));
}

/// Writes an HBITMAP (CF_BITMAP from the clipboard) as a PNG file.
pub fn savePng(hbitmap: c.HBITMAP, path: []const u8, gpa: std.mem.Allocator) !void {
    const f = try factory();
    defer w.release(f);
    var bitmap: [*c]c.IWICBitmap = null;
    try w.check(w.call(f, "CreateBitmapFromHBITMAP", .{ hbitmap, null, c.WICBitmapIgnoreAlpha, &bitmap }));
    defer w.release(bitmap);
    var stream: [*c]c.IWICStream = null;
    try w.check(w.call(f, "CreateStream", .{&stream}));
    defer w.release(stream);
    const wide = try std.unicode.wtf8ToWtf16LeAllocZ(gpa, path);
    defer gpa.free(wide);
    try w.check(w.call(stream, "InitializeFromFilename", .{ wide.ptr, c.GENERIC_WRITE }));
    var encoder: [*c]c.IWICBitmapEncoder = null;
    try w.check(w.call(f, "CreateEncoder", .{ &container_png, null, &encoder }));
    defer w.release(encoder);
    try w.check(w.call(encoder, "Initialize", .{ @as(*c.IStream, @ptrCast(stream)), c.WICBitmapEncoderNoCache }));
    var frame: [*c]c.IWICBitmapFrameEncode = null;
    try w.check(w.call(encoder, "CreateNewFrame", .{ &frame, null }));
    defer w.release(frame);
    try w.check(w.call(frame, "Initialize", .{null}));
    try w.check(w.call(frame, "WriteSource", .{ @as(*c.IWICBitmapSource, @ptrCast(bitmap)), null }));
    try w.check(w.call(frame, "Commit", .{}));
    try w.check(w.call(encoder, "Commit", .{}));
}

pub const Decoded = struct {
    /// Ready for ID2D1DeviceContext::CreateBitmapFromWicBitmap.
    source: *c.IWICBitmapSource,
    width: u32,
    height: u32,

    pub fn release(self: Decoded) void {
        w.release(self.source);
    }
};

/// The first frame of an image file, as premultiplied BGRA.
pub fn decodeFile(path: []const u8, gpa: std.mem.Allocator) !Decoded {
    const f = try factory();
    defer w.release(f);
    const wide = try std.unicode.wtf8ToWtf16LeAllocZ(gpa, path);
    defer gpa.free(wide);
    var decoder: [*c]c.IWICBitmapDecoder = null;
    try w.check(w.call(f, "CreateDecoderFromFilename", .{ wide.ptr, null, c.GENERIC_READ, c.WICDecodeMetadataCacheOnDemand, &decoder }));
    defer w.release(decoder);
    var frame: [*c]c.IWICBitmapFrameDecode = null;
    try w.check(w.call(decoder, "GetFrame", .{ 0, &frame }));
    defer w.release(frame);
    var converter: [*c]c.IWICFormatConverter = null;
    try w.check(w.call(f, "CreateFormatConverter", .{&converter}));
    errdefer w.release(converter);
    try w.check(w.call(converter, "Initialize", .{ @as(*c.IWICBitmapSource, @ptrCast(frame)), &pixel_bgra_premultiplied, c.WICBitmapDitherTypeNone, null, 0, c.WICBitmapPaletteTypeCustom }));
    var width: c.UINT = 0;
    var height: c.UINT = 0;
    try w.check(w.call(converter, "GetSize", .{ &width, &height }));
    return .{ .source = @ptrCast(converter), .width = width, .height = height };
}

test {
    @import("win32").refAllDeep(@This());
}
