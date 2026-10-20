//! The main window: its class, its procedure and the message loop.

const w = @import("win32");
const c = w.c;

const class_name = w.L("Cadex.Window");

pub fn open() error{WindowFailed}!c.HWND {
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
    return c.CreateWindowExW(0, class_name, w.L("Cadex"), c.WS_OVERLAPPEDWINDOW, c.CW_USEDEFAULT, c.CW_USEDEFAULT, 1100, 720, null, null, instance, null) orelse error.WindowFailed;
}

/// Until the window closes.
pub fn run() void {
    var msg: c.MSG = undefined;
    while (c.GetMessageW(&msg, null, 0, 0) > 0) {
        _ = c.TranslateMessage(&msg);
        _ = c.DispatchMessageW(&msg);
    }
}

fn procedure(hwnd: c.HWND, msg: c.UINT, wparam: c.WPARAM, lparam: c.LPARAM) callconv(.winapi) c.LRESULT {
    switch (msg) {
        c.WM_DESTROY => {
            c.PostQuitMessage(0);
            return 0;
        },
        else => return c.DefWindowProcW(hwnd, msg, wparam, lparam),
    }
}
