//! The main window: its class, its procedure and the message loop.

const w = @import("win32");
const user32 = w.user32;

const class_name = w.L("Cadex.Window");

pub fn open() error{WindowFailed}!w.HWND {
    const instance = w.kernel32.GetModuleHandleW(null);
    const class: user32.WNDCLASSEXW = .{
        .style = user32.CS_HREDRAW | user32.CS_VREDRAW,
        .lpfnWndProc = procedure,
        .hInstance = instance,
        .hCursor = user32.LoadCursorW(null, user32.IDC_ARROW),
        .lpszClassName = class_name,
    };
    if (user32.RegisterClassExW(&class) == 0) return error.WindowFailed;
    return user32.CreateWindowExW(0, class_name, w.L("Cadex"), user32.WS_OVERLAPPEDWINDOW, user32.CW_USEDEFAULT, user32.CW_USEDEFAULT, 1100, 720, null, null, instance, null) orelse error.WindowFailed;
}

/// Until the window closes.
pub fn run() void {
    var msg: user32.MSG = undefined;
    while (user32.GetMessageW(&msg, null, 0, 0) > 0) {
        _ = user32.TranslateMessage(&msg);
        _ = user32.DispatchMessageW(&msg);
    }
}

fn procedure(hwnd: w.HWND, msg: w.UINT, wparam: w.WPARAM, lparam: w.LPARAM) callconv(.winapi) w.LRESULT {
    switch (msg) {
        user32.WM_DESTROY => {
            user32.PostQuitMessage(0);
            return 0;
        },
        else => return user32.DefWindowProcW(hwnd, msg, wparam, lparam),
    }
}
