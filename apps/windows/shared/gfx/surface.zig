//! A window's drawing surface: a composition swap chain (premultiplied
//! alpha, so the Mica backdrop shows through where the app leaves it
//! transparent), shown by DirectComposition, with a Direct2D device context
//! drawing into its back buffer.

const std = @import("std");
const w = @import("win32");
const c = w.c;
const Device = @import("device.zig").Device;

pub const Surface = struct {
    swap_chain: *c.IDXGISwapChain1,
    target: *w.dcomp.Target,
    visual: *w.dcomp.Visual,
    context: *c.ID2D1DeviceContext,
    /// The back buffer as a D2D target; remade on every resize.
    bitmap: ?*c.ID2D1Bitmap1 = null,
    width: u32,
    height: u32,

    pub fn create(device: *Device, hwnd: c.HWND, width: u32, height: u32) !Surface {
        const desc: c.DXGI_SWAP_CHAIN_DESC1 = .{
            .Width = @max(width, 1),
            .Height = @max(height, 1),
            .Format = c.DXGI_FORMAT_B8G8R8A8_UNORM,
            .Stereo = 0,
            .SampleDesc = .{ .Count = 1, .Quality = 0 },
            .BufferUsage = c.DXGI_USAGE_RENDER_TARGET_OUTPUT,
            .BufferCount = 2,
            .Scaling = c.DXGI_SCALING_STRETCH,
            .SwapEffect = c.DXGI_SWAP_EFFECT_FLIP_SEQUENTIAL,
            .AlphaMode = c.DXGI_ALPHA_MODE_PREMULTIPLIED,
            .Flags = 0,
        };
        var swap_chain: [*c]c.IDXGISwapChain1 = null;
        try w.check(w.call(device.dxgi_factory, "CreateSwapChainForComposition", .{ @as(*c.IUnknown, @ptrCast(device.d3d)), &desc, null, &swap_chain }));
        errdefer w.release(swap_chain);

        var target: ?*w.dcomp.Target = null;
        try w.check(device.composition.createTargetForHwnd(hwnd, true, &target));
        errdefer target.?.release();
        var visual: ?*w.dcomp.Visual = null;
        try w.check(device.composition.createVisual(&visual));
        errdefer visual.?.release();
        try w.check(visual.?.setContent(swap_chain));
        try w.check(target.?.setRoot(visual));
        try w.check(device.composition.commit());

        var context: [*c]c.ID2D1DeviceContext = null;
        try w.check(w.call(device.d2d, "CreateDeviceContext", .{ c.D2D1_DEVICE_CONTEXT_OPTIONS_NONE, &context }));
        var self: Surface = .{ .swap_chain = swap_chain, .target = target.?, .visual = visual.?, .context = context, .width = desc.Width, .height = desc.Height };
        try self.bindBackBuffer();
        return self;
    }

    pub fn destroy(self: *Surface) void {
        self.unbind();
        w.release(self.context);
        self.visual.release();
        self.target.release();
        w.release(self.swap_chain);
    }

    /// The window changed size (in pixels).
    pub fn resize(self: *Surface, width: u32, height: u32) !void {
        const wd = @max(width, 1);
        const ht = @max(height, 1);
        if (wd == self.width and ht == self.height) return;
        self.unbind();
        try w.check(w.call(self.swap_chain, "ResizeBuffers", .{ 0, wd, ht, c.DXGI_FORMAT_UNKNOWN, 0 }));
        self.width = wd;
        self.height = ht;
        try self.bindBackBuffer();
    }

    fn unbind(self: *Surface) void {
        w.call(self.context, "SetTarget", .{null});
        if (self.bitmap) |b| w.release(b);
        self.bitmap = null;
    }

    fn bindBackBuffer(self: *Surface) !void {
        var surface_raw: ?*anyopaque = null;
        try w.check(w.call(self.swap_chain, "GetBuffer", .{ 0, &w.iid.IDXGISurface, &surface_raw }));
        const surface: *c.IDXGISurface = @ptrCast(@alignCast(surface_raw.?));
        defer w.release(surface);
        const props: c.D2D1_BITMAP_PROPERTIES1 = .{
            .pixelFormat = .{ .format = c.DXGI_FORMAT_B8G8R8A8_UNORM, .alphaMode = c.D2D1_ALPHA_MODE_PREMULTIPLIED },
            .dpiX = 96,
            .dpiY = 96,
            .bitmapOptions = c.D2D1_BITMAP_OPTIONS_TARGET | c.D2D1_BITMAP_OPTIONS_CANNOT_DRAW,
            .colorContext = null,
        };
        var bitmap: [*c]c.ID2D1Bitmap1 = null;
        try w.check(w.call(self.context, "CreateBitmapFromDxgiSurface", .{ surface, &props, &bitmap }));
        self.bitmap = bitmap;
        w.call(self.context, "SetTarget", .{@as(*c.ID2D1Image, @ptrCast(bitmap))});
        // Text antialiasing: grayscale, because ClearType needs an opaque
        // target and this one has alpha.
        w.call(self.context, "SetTextAntialiasMode", .{c.D2D1_TEXT_ANTIALIAS_MODE_GRAYSCALE});
    }

    pub fn begin(self: *Surface) void {
        w.call(self.context, "BeginDraw", .{});
    }

    /// Ends the frame and shows it, in step with the display.
    pub fn end(self: *Surface) !void {
        const hr = w.call(self.context, "EndDraw", .{ null, null });
        if (hr == c.D2DERR_RECREATE_TARGET) return error.DeviceLost;
        try w.check(hr);
        try w.check(w.call(self.swap_chain, "Present", .{ 1, 0 }));
    }
};

test {
    @import("std").testing.refAllDecls(@This());
}
