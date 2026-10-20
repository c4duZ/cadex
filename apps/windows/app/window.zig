//! The main window: its class, its procedure and the message loop.

const std = @import("std");
const w = @import("win32");
const gfx = @import("gfx");
const c = w.c;

const class_name = w.L("Cadex.Window");

var device: gfx.Device = undefined;
var surface: ?gfx.Surface = null;
var fonts: gfx.Fonts = undefined;
var painter: gfx.Painter = undefined;

pub fn open() !c.HWND {
    device = try gfx.Device.create();
    fonts = try gfx.Fonts.init(std.heap.c_allocator, device.dwrite, &.{});
    const instance = c.GetModuleHandleW(null);
    const class: c.WNDCLASSEXW = .{
        .cbSize = @sizeOf(c.WNDCLASSEXW),
        .style = c.CS_HREDRAW | c.CS_VREDRAW,
        .lpfnWndProc = procedure,
        .hInstance = instance,
        .hCursor = c.LoadCursorW(null, w.IDC_ARROW),
        .lpszClassName = class_name,
    };
    if (c.RegisterClassExW(&class) == 0) return error.WindowFailed;
    const hwnd = c.CreateWindowExW(c.WS_EX_NOREDIRECTIONBITMAP, class_name, w.L("Cadex"), c.WS_OVERLAPPEDWINDOW, c.CW_USEDEFAULT, c.CW_USEDEFAULT, 1100, 720, null, null, instance, null) orelse return error.WindowFailed;
    var rect: c.RECT = undefined;
    _ = c.GetClientRect(hwnd, &rect);
    surface = try gfx.Surface.create(&device, hwnd, @intCast(rect.right), @intCast(rect.bottom));
    painter = try gfx.Painter.init(surface.?.context, device.dwrite, &fonts);
    return hwnd;
}

/// Until the window closes.
pub fn run() void {
    var msg: c.MSG = undefined;
    while (c.GetMessageW(&msg, null, 0, 0) > 0) {
        _ = c.TranslateMessage(&msg);
        _ = c.DispatchMessageW(&msg);
    }
}

fn draw() void {
    const s = &(surface orelse return);
    s.begin();
    painter.clear(gfx.Color.rgb(0x1e1e2e));
    painter.text("Cadex", .{ .family = "Segoe UI Variable Text", .size = 28 }, .{ .x = 0, .y = 0, .w = @floatFromInt(s.width), .h = @floatFromInt(s.height) }, gfx.Color.white, .{ .@"align" = .center });
    s.end() catch {};
}

fn procedure(hwnd: c.HWND, msg: c.UINT, wparam: c.WPARAM, lparam: c.LPARAM) callconv(.winapi) c.LRESULT {
    switch (msg) {
        c.WM_SIZE => {
            if (surface) |*s| s.resize(w.LOWORD(lparam), w.HIWORD(lparam)) catch {};
            _ = c.InvalidateRect(hwnd, null, 0);
            return 0;
        },
        c.WM_PAINT => {
            var ps: c.PAINTSTRUCT = undefined;
            _ = c.BeginPaint(hwnd, &ps);
            draw();
            _ = c.EndPaint(hwnd, &ps);
            return 0;
        },
        c.WM_DESTROY => {
            c.PostQuitMessage(0);
            return 0;
        },
        else => return c.DefWindowProcW(hwnd, msg, wparam, lparam),
    }
}
