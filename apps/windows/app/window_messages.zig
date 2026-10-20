//! The main window's messages: the frame the app draws itself, hit tests
//! for the edges, the caption and the maximize button, the mouse, the
//! wheel, text and the IME, dropped files, DPI and theme changes.

const std = @import("std");
const w = @import("win32");
const gfx = @import("gfx");
const ui = @import("ui");
const window = @import("window.zig");
const c = w.c;

const Window = window.Window;

pub fn handle(self: *Window, hwnd: c.HWND, msg: c.UINT, wparam: c.WPARAM, lparam: c.LPARAM) c.LRESULT {
    const d = self.delegate;
    switch (msg) {
        c.WM_NCCALCSIZE => if (wparam != 0) {
            // The client covers the whole window; maximized, the frame
            // would hang off the screen, so keep it inside.
            if (self.isMaximized()) {
                const params: *c.NCCALCSIZE_PARAMS = @ptrFromInt(@as(usize, @bitCast(lparam)));
                const frame = c.GetSystemMetricsForDpi(c.SM_CXFRAME, self.dpi) + c.GetSystemMetricsForDpi(c.SM_CXPADDEDBORDER, self.dpi);
                params.rgrc[0].left += frame;
                params.rgrc[0].right -= frame;
                params.rgrc[0].top += frame;
                params.rgrc[0].bottom -= frame;
            }
            return 0;
        },
        c.WM_NCHITTEST => return hitTest(self, hwnd, lparam),
        c.WM_NCMOUSEMOVE => {
            // Over the maximize button the mouse is "non-client": still hover it.
            var p: c.POINT = .{ .x = w.xParam(lparam), .y = w.yParam(lparam) };
            _ = c.ScreenToClient(hwnd, &p);
            self.input.mouse = .{ .x = @floatFromInt(p.x), .y = @floatFromInt(p.y) };
            self.input.mouse_inside = true;
            self.redraw();
            return c.DefWindowProcW(hwnd, msg, wparam, lparam);
        },
        c.WM_NCLBUTTONDOWN => if (wparam == c.HTMAXBUTTON) {
            self.maximize_pressed = true;
            return 0;
        },
        c.WM_NCLBUTTONUP => if (wparam == c.HTMAXBUTTON) {
            if (self.maximize_pressed) _ = c.ShowWindow(hwnd, if (self.isMaximized()) c.SW_RESTORE else c.SW_MAXIMIZE);
            self.maximize_pressed = false;
            return 0;
        },
        c.WM_NCMOUSELEAVE, c.WM_MOUSELEAVE => {
            self.input.mouse_inside = false;
            self.tracking_leave = false;
            self.redraw();
            return 0;
        },
        c.WM_MOUSEMOVE => {
            self.input.mouse = window_point(lparam);
            self.input.mouse_inside = true;
            if (!self.tracking_leave) {
                var track: c.TRACKMOUSEEVENT = .{ .cbSize = @sizeOf(c.TRACKMOUSEEVENT), .dwFlags = c.TME_LEAVE, .hwndTrack = hwnd, .dwHoverTime = 0 };
                _ = c.TrackMouseEvent(&track);
                self.tracking_leave = true;
            }
            self.redraw();
            return 0;
        },
        c.WM_LBUTTONDOWN, c.WM_LBUTTONDBLCLK, c.WM_RBUTTONDOWN, c.WM_MBUTTONDOWN => {
            const button: ui.Button = switch (msg) {
                c.WM_RBUTTONDOWN => .right,
                c.WM_MBUTTONDOWN => .middle,
                else => .left,
            };
            _ = c.SetCapture(hwnd);
            // A click outside a web page takes the keyboard back from it
            // (its child window keeps the focus otherwise).
            _ = c.SetFocus(hwnd);
            self.input.mods = window.currentMods();
            self.input.press(button, window_point(lparam), @intCast(c.GetTickCount64()), c.GetDoubleClickTime(), @floatFromInt(c.GetSystemMetrics(c.SM_CXDOUBLECLK)));
            self.redraw();
            return 0;
        },
        c.WM_LBUTTONUP, c.WM_RBUTTONUP, c.WM_MBUTTONUP => {
            const button: ui.Button = switch (msg) {
                c.WM_RBUTTONUP => .right,
                c.WM_MBUTTONUP => .middle,
                else => .left,
            };
            self.input.release(button, window_point(lparam));
            if (!self.input.down[0] and !self.input.down[1] and !self.input.down[2]) _ = c.ReleaseCapture();
            self.redraw();
            return 0;
        },
        c.WM_MOUSEWHEEL, c.WM_MOUSEHWHEEL => {
            var p: c.POINT = .{ .x = w.xParam(lparam), .y = w.yParam(lparam) };
            _ = c.ScreenToClient(hwnd, &p);
            self.input.mouse = .{ .x = @floatFromInt(p.x), .y = @floatFromInt(p.y) };
            self.input.mods = window.currentMods();
            const delta: i16 = @bitCast(w.HIWORD(wparam));
            if (msg == c.WM_MOUSEWHEEL) self.input.wheel += delta else self.input.wheel_horizontal += delta;
            self.redraw();
            return 0;
        },
        c.WM_SETCURSOR => if (w.LOWORD(lparam) == c.HTCLIENT) {
            return 1;
        },
        c.WM_KEYDOWN, c.WM_SYSKEYDOWN => {
            // Keys the app did not take (the window's loop asked first).
            self.input.mods = window.currentMods();
            self.input.keys.append(self.gpa, .{ .vk = @truncate(wparam), .mods = self.input.mods, .repeat = (lparam & (1 << 30)) != 0 }) catch {};
            self.redraw();
            if (msg == c.WM_SYSKEYDOWN and (wparam == c.VK_F4 or wparam == c.VK_SPACE)) return c.DefWindowProcW(hwnd, msg, wparam, lparam);
            return 0;
        },
        c.WM_KEYUP, c.WM_SYSKEYUP => {
            self.input.mods = window.currentMods();
            self.redraw();
            return 0;
        },
        c.WM_CHAR, c.WM_SYSCHAR => return text(self, @truncate(wparam)),
        c.WM_SYSCOMMAND => {
            // Alt alone opens no menu bar: there is none.
            if ((wparam & 0xFFF0) == c.SC_KEYMENU) return 0;
            return c.DefWindowProcW(hwnd, msg, wparam, lparam);
        },
        c.WM_IME_STARTCOMPOSITION => {
            self.redraw();
            return c.DefWindowProcW(hwnd, msg, wparam, lparam);
        },
        c.WM_IME_COMPOSITION => {
            if (lparam & c.GCS_COMPSTR != 0) readComposition(self, hwnd);
            if (lparam & c.GCS_RESULTSTR != 0) self.input.composition.clearRetainingCapacity();
            self.redraw();
            // DefWindowProc turns the result into WM_CHAR; the composition
            // itself is drawn by the app, not in the IME's own window.
            if (lparam & c.GCS_RESULTSTR != 0) return c.DefWindowProcW(hwnd, msg, wparam, lparam);
            return 0;
        },
        c.WM_IME_ENDCOMPOSITION => {
            self.input.composition.clearRetainingCapacity();
            self.redraw();
            return c.DefWindowProcW(hwnd, msg, wparam, lparam);
        },
        c.WM_IME_SETCONTEXT => return c.DefWindowProcW(hwnd, msg, wparam, lparam & ~@as(c.LPARAM, c.ISC_SHOWUICOMPOSITIONWINDOW)),
        c.WM_DROPFILES => {
            const drop: c.HDROP = @ptrFromInt(wparam);
            var p: c.POINT = undefined;
            _ = c.DragQueryPoint(drop, &p);
            self.input.drop_point = .{ .x = @floatFromInt(p.x), .y = @floatFromInt(p.y) };
            const paths = ui.clipboard.dropFiles(self.gpa, drop);
            defer self.gpa.free(paths);
            self.input.dropped.appendSlice(self.gpa, paths) catch for (paths) |path| self.gpa.free(path);
            c.DragFinish(drop);
            self.redraw();
            return 0;
        },
        c.WM_PAINT => {
            var ps: c.PAINTSTRUCT = undefined;
            _ = c.BeginPaint(hwnd, &ps);
            d.frame(d.context);
            _ = c.EndPaint(hwnd, &ps);
            return 0;
        },
        c.WM_ERASEBKGND => return 1,
        c.WM_SIZE => {
            self.redraw();
            return 0;
        },
        c.WM_MOVE => {
            if (d.moved) |f| f(d.context);
            return 0;
        },
        c.WM_TIMER => {
            if (wparam == 1) {
                _ = c.KillTimer(hwnd, 1);
                self.redraw();
            } else d.poll(d.context);
            return 0;
        },
        c.WM_DPICHANGED => {
            self.dpi = w.HIWORD(wparam);
            const r: *const c.RECT = @ptrFromInt(@as(usize, @bitCast(lparam)));
            _ = c.SetWindowPos(hwnd, null, r.left, r.top, r.right - r.left, r.bottom - r.top, c.SWP_NOZORDER | c.SWP_NOACTIVATE);
            d.appearance(d.context);
            self.redraw();
            return 0;
        },
        c.WM_SETTINGCHANGE => {
            d.appearance(d.context);
            self.redraw();
            return 0;
        },
        c.WM_GETMINMAXINFO => {
            const info: *c.MINMAXINFO = @ptrFromInt(@as(usize, @bitCast(lparam)));
            const s = self.scale();
            info.ptMinTrackSize = .{ .x = @intFromFloat(480 * s), .y = @intFromFloat(320 * s) };
            return 0;
        },
        c.WM_SETFOCUS, c.WM_KILLFOCUS, c.WM_ACTIVATE => {
            self.redraw();
            return c.DefWindowProcW(hwnd, msg, wparam, lparam);
        },
        window.WM_APP_WAKE => {
            d.wake(d.context);
            self.redraw();
            return 0;
        },
        window.WM_APP_TERMINAL => {
            d.terminal(d.context, lparam, wparam);
            return 0;
        },
        c.WM_CLOSE => {
            if (d.close(d.context)) _ = c.DestroyWindow(hwnd);
            return 0;
        },
        c.WM_DESTROY => {
            c.PostQuitMessage(0);
            return 0;
        },
        else => {},
    }
    return c.DefWindowProcW(hwnd, msg, wparam, lparam);
}

fn window_point(lparam: c.LPARAM) gfx.Point {
    return .{ .x = @floatFromInt(w.xParam(lparam)), .y = @floatFromInt(w.yParam(lparam)) };
}

/// A UTF-16 unit of typed text; surrogate pairs come in two messages.
fn text(self: *Window, unit: u16) c.LRESULT {
    if (unit >= 0xD800 and unit < 0xDC00) {
        self.high_surrogate = unit;
        return 0;
    }
    var units: [2]u16 = undefined;
    var n: usize = 0;
    if (unit >= 0xDC00 and unit < 0xE000) {
        units[0] = self.high_surrogate orelse return 0;
        units[1] = unit;
        n = 2;
        self.high_surrogate = null;
    } else {
        units[0] = unit;
        n = 1;
    }
    // Control characters are keys, not text (Enter, Tab, Esc, Backspace).
    if (n == 1 and (unit < 0x20 or unit == 0x7F)) return 0;
    var utf8: [8]u8 = undefined;
    const len = std.unicode.wtf16LeToWtf8(&utf8, units[0..n]);
    self.delegate.text(self.delegate.context, utf8[0..len]);
    self.redraw();
    return 0;
}

fn readComposition(self: *Window, hwnd: c.HWND) void {
    const imc = c.ImmGetContext(hwnd);
    if (imc == null) return;
    defer _ = c.ImmReleaseContext(hwnd, imc);
    var buf: [256]u16 = undefined;
    const bytes = c.ImmGetCompositionStringW(imc, c.GCS_COMPSTR, &buf, buf.len * 2);
    self.input.composition.clearRetainingCapacity();
    if (bytes <= 0) return;
    const units: usize = @intCast(@divTrunc(bytes, 2));
    var utf8: [768]u8 = undefined;
    const len = std.unicode.wtf16LeToWtf8(&utf8, buf[0..@min(units, buf.len)]);
    self.input.composition.appendSlice(self.gpa, utf8[0..len]) catch {};
}

/// The resize edges (inside the client, which covers the frame), the
/// maximize button, the title bar's holes (tabs, buttons) and its caption.
fn hitTest(self: *Window, hwnd: c.HWND, lparam: c.LPARAM) c.LRESULT {
    var p: c.POINT = .{ .x = w.xParam(lparam), .y = w.yParam(lparam) };
    _ = c.ScreenToClient(hwnd, &p);
    const at: gfx.Point = .{ .x = @floatFromInt(p.x), .y = @floatFromInt(p.y) };
    const s = self.size();
    if (!self.isMaximized()) {
        const edge: f32 = @floatFromInt(c.GetSystemMetricsForDpi(c.SM_CXFRAME, self.dpi) + c.GetSystemMetricsForDpi(c.SM_CXPADDEDBORDER, self.dpi));
        const left = at.x < edge;
        const right = at.x >= s.x - edge;
        const top = at.y < edge;
        const bottom = at.y >= s.y - edge;
        if (top and left) return c.HTTOPLEFT;
        if (top and right) return c.HTTOPRIGHT;
        if (bottom and left) return c.HTBOTTOMLEFT;
        if (bottom and right) return c.HTBOTTOMRIGHT;
        if (left) return c.HTLEFT;
        if (right) return c.HTRIGHT;
        if (top) return c.HTTOP;
        if (bottom) return c.HTBOTTOM;
    }
    const d = self.delegate;
    if (d.maximize_button(d.context).contains(at)) return c.HTMAXBUTTON;
    if (at.y < d.title_height(d.context)) {
        for (d.caption_holes(d.context)) |hole| if (hole.contains(at)) return c.HTCLIENT;
        return c.HTCAPTION;
    }
    return c.HTCLIENT;
}

test {
    @import("win32").refAllDeep(@This());
}
