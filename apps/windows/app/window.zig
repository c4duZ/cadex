//! The main window: a Win32 window whose client area covers the whole
//! frame (the app draws its own title bar), with Windows 11's rounded
//! corners, shadow and Mica behind, the resize edges and the caption from
//! hit tests, and the maximize button reported as such so Snap Layouts
//! appear on hover. Messages become the interface's input (ui.Input);
//! drawing happens in WM_PAINT, only when something asked for a frame.

const std = @import("std");
const w = @import("win32");
const gfx = @import("gfx");
const ui = @import("ui");
const c = w.c;

pub const WM_APP_TERMINAL = c.WM_APP + 1;
/// A worker (the explorer's watcher, a search) has news: drain and redraw.
pub const WM_APP_WAKE = c.WM_APP + 2;
const timer_frame = 1;
const timer_poll = 2;

/// What the window asks of the app (app.zig implements it).
pub const Delegate = struct {
    context: *anyopaque,
    /// Draws one frame; `size` in pixels.
    frame: *const fn (context: *anyopaque) void,
    /// A key press, before TranslateMessage: true when used (no WM_CHAR follows).
    key: *const fn (context: *anyopaque, vk: u16, scan: u16, mods: ui.Mods) bool,
    /// Text from WM_CHAR, UTF-8.
    text: *const fn (context: *anyopaque, utf8: []const u8) void,
    /// A queued notice of a terminal (lparam: the session), on this thread.
    terminal: *const fn (context: *anyopaque, lparam: c.LPARAM, wparam: c.WPARAM) void,
    /// Closing the window (the close button, Alt+F4): true lets it close.
    close: *const fn (context: *anyopaque) bool,
    /// A worker posted WM_APP_WAKE.
    wake: *const fn (context: *anyopaque) void,
    /// Once a second: settings edited by hand.
    poll: *const fn (context: *anyopaque) void,
    /// The system switched light/dark or the DPI changed.
    appearance: *const fn (context: *anyopaque) void,
    /// The rectangles of the title bar that are buttons or tabs, not the caption.
    caption_holes: *const fn (context: *anyopaque) []const gfx.Rect,
    /// The maximize button's rectangle (Snap Layouts on hover).
    maximize_button: *const fn (context: *anyopaque) gfx.Rect,
    title_height: *const fn (context: *anyopaque) f32,
};

pub const Window = struct {
    hwnd: c.HWND = null,
    delegate: Delegate = undefined,
    input: *ui.Input = undefined,
    gpa: std.mem.Allocator = undefined,
    dpi: u32 = 96,
    high_surrogate: ?u16 = null,
    tracking_leave: bool = false,
    /// Press, then release over the maximize button: we toggle it ourselves.
    maximize_pressed: bool = false,

    pub fn scale(self: *const Window) f32 {
        return @as(f32, @floatFromInt(self.dpi)) / 96;
    }

    pub fn size(self: *const Window) gfx.Point {
        var r: c.RECT = undefined;
        _ = c.GetClientRect(self.hwnd, &r);
        return .{ .x = @floatFromInt(r.right - r.left), .y = @floatFromInt(r.bottom - r.top) };
    }

    pub fn redraw(self: *Window) void {
        _ = c.InvalidateRect(self.hwnd, null, 0);
    }

    pub fn redrawIn(self: *Window, ms: u32) void {
        _ = c.SetTimer(self.hwnd, timer_frame, @max(ms, 1), null);
    }

    pub fn isMaximized(self: *const Window) bool {
        return c.IsZoomed(self.hwnd) != 0;
    }

    pub fn create(self: *Window, gpa: std.mem.Allocator, input: *ui.Input, delegate: Delegate) !void {
        self.gpa = gpa;
        self.input = input;
        self.delegate = delegate;
        const instance = c.GetModuleHandleW(null);
        const class: c.WNDCLASSEXW = .{
            .cbSize = @sizeOf(c.WNDCLASSEXW),
            .style = c.CS_HREDRAW | c.CS_VREDRAW | c.CS_DBLCLKS,
            .lpfnWndProc = procedure,
            .hInstance = instance,
            .hCursor = w.loadCursor(.arrow),
            .hIcon = w.loadIcon(instance, 1),
            .lpszClassName = w.L("Cadex.Window"),
        };
        _ = c.RegisterClassExW(&class);
        const hwnd = c.CreateWindowExW(
            c.WS_EX_NOREDIRECTIONBITMAP | c.WS_EX_ACCEPTFILES,
            w.L("Cadex.Window"),
            w.L("Cadex"),
            c.WS_OVERLAPPEDWINDOW,
            c.CW_USEDEFAULT,
            c.CW_USEDEFAULT,
            1200,
            780,
            null,
            null,
            instance,
            self,
        ) orelse return error.WindowFailed;
        self.hwnd = hwnd;
        self.dpi = c.GetDpiForWindow(hwnd);
        // The client covers the frame, so the shadow and the rounded corners
        // come from the DWM; Mica shows where the app draws transparent.
        const margins: c.MARGINS = .{ .cxLeftWidth = -1, .cxRightWidth = -1, .cyTopHeight = -1, .cyBottomHeight = -1 };
        _ = c.DwmExtendFrameIntoClientArea(hwnd, &margins);
        const backdrop: c_int = 2; // DWMSBT_MAINWINDOW: Mica.
        _ = c.DwmSetWindowAttribute(hwnd, 38, &backdrop, @sizeOf(c_int)); // DWMWA_SYSTEMBACKDROP_TYPE
        _ = c.SetTimer(hwnd, timer_poll, 1000, null);
        // Resize once so WM_NCCALCSIZE runs with the window known.
        _ = c.SetWindowPos(hwnd, null, 0, 0, 0, 0, c.SWP_FRAMECHANGED | c.SWP_NOMOVE | c.SWP_NOSIZE | c.SWP_NOZORDER);
    }

    /// Dark title bar parts (the system menu, the snap flyout) follow the theme.
    pub fn setDark(self: *Window, dark: bool) void {
        const value: c.BOOL = @intFromBool(dark);
        _ = c.DwmSetWindowAttribute(self.hwnd, 20, &value, @sizeOf(c.BOOL)); // DWMWA_USE_IMMERSIVE_DARK_MODE
    }

    pub fn show(self: *Window, background: bool) void {
        // CADEX_BACKGROUND=1: shown without taking the focus, for tests.
        _ = c.ShowWindow(self.hwnd, if (background) c.SW_SHOWNOACTIVATE else c.SW_SHOWDEFAULT);
    }

    pub fn setTitle(self: *Window, title: []const u8) void {
        const wide = std.unicode.wtf8ToWtf16LeAllocZ(self.gpa, title) catch return;
        defer self.gpa.free(wide);
        _ = c.SetWindowTextW(self.hwnd, wide.ptr);
    }

    /// Where the IME shows the text being composed and its candidates.
    pub fn placeIme(self: *Window, caret: gfx.Rect) void {
        const imc = c.ImmGetContext(self.hwnd);
        if (imc == null) return;
        defer _ = c.ImmReleaseContext(self.hwnd, imc);
        var form: c.COMPOSITIONFORM = .{ .dwStyle = c.CFS_POINT, .ptCurrentPos = .{ .x = @intFromFloat(caret.x), .y = @intFromFloat(caret.y) }, .rcArea = std.mem.zeroes(c.RECT) };
        _ = c.ImmSetCompositionWindow(imc, &form);
        var candidate: c.CANDIDATEFORM = .{
            .dwIndex = 0,
            .dwStyle = c.CFS_EXCLUDE,
            .ptCurrentPos = .{ .x = @intFromFloat(caret.x), .y = @intFromFloat(caret.bottom()) },
            .rcArea = .{ .left = @intFromFloat(caret.x), .top = @intFromFloat(caret.y), .right = @intFromFloat(caret.right()), .bottom = @intFromFloat(caret.bottom()) },
        };
        _ = c.ImmSetCandidateWindow(imc, &candidate);
    }

    pub fn setCursor(cursor: ui.Cursor) void {
        _ = c.SetCursor(w.loadCursor(switch (cursor) {
            .arrow => .arrow,
            .ibeam => .ibeam,
            .hand => .hand,
            .resize_we => .size_we,
            .resize_ns => .size_ns,
        }));
    }

    /// Runs until the window closes. Keys go to the app before
    /// TranslateMessage, so a key it used makes no WM_CHAR.
    pub fn run(self: *Window) void {
        var msg: c.MSG = undefined;
        while (c.GetMessageW(&msg, null, 0, 0) > 0) {
            if ((msg.message == c.WM_KEYDOWN or msg.message == c.WM_SYSKEYDOWN) and msg.hwnd == self.hwnd) {
                const vk: u16 = @truncate(msg.wParam);
                const scan: u16 = @truncate((@as(usize, @bitCast(msg.lParam)) >> 16) & 0x1FF);
                // Alt+F4 and Alt+Space stay the system's.
                const system = msg.message == c.WM_SYSKEYDOWN and (vk == c.VK_F4 or vk == c.VK_SPACE);
                if (!system and self.delegate.key(self.delegate.context, vk, scan, currentMods())) {
                    self.redraw();
                    continue;
                }
            }
            _ = c.TranslateMessage(&msg);
            _ = c.DispatchMessageW(&msg);
        }
    }
};

pub fn currentMods() ui.Mods {
    const down = struct {
        fn key(vk: c_int) bool {
            return (@as(u16, @bitCast(c.GetKeyState(vk))) & 0x8000) != 0;
        }
    }.key;
    return .{ .shift = down(c.VK_SHIFT), .ctrl = down(c.VK_CONTROL), .alt = down(c.VK_MENU), .super = down(c.VK_LWIN) or down(c.VK_RWIN) };
}

fn self_of(hwnd: c.HWND) ?*Window {
    const raw = c.GetWindowLongPtrW(hwnd, c.GWLP_USERDATA);
    if (raw == 0) return null;
    return @ptrFromInt(@as(usize, @bitCast(raw)));
}

fn point(lparam: c.LPARAM) gfx.Point {
    return .{ .x = @floatFromInt(w.xParam(lparam)), .y = @floatFromInt(w.yParam(lparam)) };
}

fn procedure(hwnd: c.HWND, msg: c.UINT, wparam: c.WPARAM, lparam: c.LPARAM) callconv(.winapi) c.LRESULT {
    if (msg == c.WM_NCCREATE) {
        const create: *c.CREATESTRUCTW = @ptrFromInt(@as(usize, @bitCast(lparam)));
        _ = c.SetWindowLongPtrW(hwnd, c.GWLP_USERDATA, @bitCast(@intFromPtr(create.lpCreateParams)));
        return c.DefWindowProcW(hwnd, msg, wparam, lparam);
    }
    const self = self_of(hwnd) orelse return c.DefWindowProcW(hwnd, msg, wparam, lparam);
    return @import("window_messages.zig").handle(self, hwnd, msg, wparam, lparam);
}

test {
    @import("win32").refAllDeep(@This());
}
