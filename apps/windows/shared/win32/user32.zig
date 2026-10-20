//! user32.dll: windows, messages and input.

const w = @import("win32.zig");

pub const WNDPROC = *const fn (hwnd: w.HWND, msg: w.UINT, wparam: w.WPARAM, lparam: w.LPARAM) callconv(.winapi) w.LRESULT;

pub const WNDCLASSEXW = extern struct {
    cbSize: w.UINT = @sizeOf(WNDCLASSEXW),
    style: w.UINT = 0,
    lpfnWndProc: WNDPROC,
    cbClsExtra: c_int = 0,
    cbWndExtra: c_int = 0,
    hInstance: ?w.HINSTANCE = null,
    hIcon: ?w.HICON = null,
    hCursor: ?w.HCURSOR = null,
    hbrBackground: ?w.HBRUSH = null,
    lpszMenuName: ?w.LPCWSTR = null,
    lpszClassName: w.LPCWSTR,
    hIconSm: ?w.HICON = null,
};

pub const MSG = extern struct {
    hwnd: ?w.HWND,
    message: w.UINT,
    wParam: w.WPARAM,
    lParam: w.LPARAM,
    time: w.DWORD,
    pt: w.POINT,
    lPrivate: w.DWORD,
};

pub const CS_HREDRAW: w.UINT = 0x2;
pub const CS_VREDRAW: w.UINT = 0x1;
pub const WS_OVERLAPPEDWINDOW: w.DWORD = 0x00CF0000;
pub const CW_USEDEFAULT: c_int = @bitCast(@as(u32, 0x80000000));
pub const SW_SHOWDEFAULT: c_int = 10;
pub const WM_DESTROY: w.UINT = 0x0002;
/// MAKEINTRESOURCE(32512), the standard arrow.
pub const IDC_ARROW: w.LPCWSTR = @ptrFromInt(32512);

pub extern "user32" fn RegisterClassExW(class: *const WNDCLASSEXW) callconv(.winapi) w.ATOM;
pub extern "user32" fn CreateWindowExW(ex_style: w.DWORD, class: w.LPCWSTR, title: w.LPCWSTR, style: w.DWORD, x: c_int, y: c_int, width: c_int, height: c_int, parent: ?w.HWND, menu: ?w.HMENU, instance: ?w.HINSTANCE, param: ?*anyopaque) callconv(.winapi) ?w.HWND;
pub extern "user32" fn ShowWindow(hwnd: w.HWND, show: c_int) callconv(.winapi) w.BOOL;
pub extern "user32" fn GetMessageW(msg: *MSG, hwnd: ?w.HWND, min: w.UINT, max: w.UINT) callconv(.winapi) w.BOOL;
pub extern "user32" fn TranslateMessage(msg: *const MSG) callconv(.winapi) w.BOOL;
pub extern "user32" fn DispatchMessageW(msg: *const MSG) callconv(.winapi) w.LRESULT;
pub extern "user32" fn DefWindowProcW(hwnd: w.HWND, msg: w.UINT, wparam: w.WPARAM, lparam: w.LPARAM) callconv(.winapi) w.LRESULT;
pub extern "user32" fn PostQuitMessage(code: c_int) callconv(.winapi) void;
pub extern "user32" fn LoadCursorW(instance: ?w.HINSTANCE, name: w.LPCWSTR) callconv(.winapi) ?w.HCURSOR;
