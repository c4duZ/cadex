//! The GPU objects one per process: Direct3D 11 (BGRA, for Direct2D), its
//! DXGI device, the Direct2D factory and device, DirectWrite and
//! DirectComposition (docs/adr/0012-windows-zig-win32-d3d11.md).

const std = @import("std");
const w = @import("win32");
const c = w.c;

pub const Device = struct {
    d3d: *c.ID3D11Device,
    d3d_context: *c.ID3D11DeviceContext,
    dxgi: *c.IDXGIDevice,
    dxgi_factory: *c.IDXGIFactory2,
    d2d_factory: *c.ID2D1Factory1,
    d2d: *c.ID2D1Device,
    dwrite: *c.IDWriteFactory5,
    composition: *w.dcomp.Device,

    pub fn create() !Device {
        var d3d: [*c]c.ID3D11Device = null;
        var context: [*c]c.ID3D11DeviceContext = null;
        const levels = [_]c.D3D_FEATURE_LEVEL{ c.D3D_FEATURE_LEVEL_11_1, c.D3D_FEATURE_LEVEL_11_0, c.D3D_FEATURE_LEVEL_10_1 };
        // A VM without a GPU driver (the UTM test VM) still gets WARP.
        var hr = c.D3D11CreateDevice(null, c.D3D_DRIVER_TYPE_HARDWARE, null, c.D3D11_CREATE_DEVICE_BGRA_SUPPORT, &levels, levels.len, c.D3D11_SDK_VERSION, &d3d, null, &context);
        if (hr < 0) hr = c.D3D11CreateDevice(null, c.D3D_DRIVER_TYPE_WARP, null, c.D3D11_CREATE_DEVICE_BGRA_SUPPORT, &levels, levels.len, c.D3D11_SDK_VERSION, &d3d, null, &context);
        try w.check(hr);
        errdefer w.release(d3d);
        errdefer w.release(context);

        const dxgi = try w.query(d3d, c.IDXGIDevice, &w.iid.IDXGIDevice);
        errdefer w.release(dxgi);
        var adapter: [*c]c.IDXGIAdapter = null;
        try w.check(w.call(dxgi, "GetAdapter", .{&adapter}));
        defer w.release(adapter);
        var factory_raw: ?*anyopaque = null;
        try w.check(w.call(adapter, "GetParent", .{ &w.iid.IDXGIFactory2, &factory_raw }));
        const dxgi_factory: *c.IDXGIFactory2 = @ptrCast(@alignCast(factory_raw.?));
        errdefer w.release(dxgi_factory);

        var d2d_raw: ?*anyopaque = null;
        try w.check(c.D2D1CreateFactory(c.D2D1_FACTORY_TYPE_SINGLE_THREADED, &w.iid.ID2D1Factory1, null, &d2d_raw));
        const d2d_factory: *c.ID2D1Factory1 = @ptrCast(@alignCast(d2d_raw.?));
        errdefer w.release(d2d_factory);
        var d2d: [*c]c.ID2D1Device = null;
        try w.check(w.call(d2d_factory, "CreateDevice", .{ dxgi, &d2d }));
        errdefer w.release(d2d);

        var dwrite_raw: [*c]c.IUnknown = null;
        try w.check(c.DWriteCreateFactory(c.DWRITE_FACTORY_TYPE_SHARED, &w.iid.IDWriteFactory5, &dwrite_raw));
        const dwrite: *c.IDWriteFactory5 = @ptrCast(@alignCast(dwrite_raw));
        errdefer w.release(dwrite);

        var composition_raw: ?*anyopaque = null;
        try w.check(w.dcomp.DCompositionCreateDevice(dxgi, &w.iid.IDCompositionDevice, &composition_raw));

        return .{
            .d3d = d3d,
            .d3d_context = context,
            .dxgi = dxgi,
            .dxgi_factory = dxgi_factory,
            .d2d_factory = d2d_factory,
            .d2d = d2d,
            .dwrite = dwrite,
            .composition = @ptrCast(@alignCast(composition_raw.?)),
        };
    }

    pub fn destroy(self: *Device) void {
        self.composition.release();
        w.release(self.dwrite);
        w.release(self.d2d);
        w.release(self.d2d_factory);
        w.release(self.dxgi_factory);
        w.release(self.dxgi);
        w.release(self.d3d_context);
        w.release(self.d3d);
    }
};

test {
    @import("std").testing.refAllDecls(@This());
}
