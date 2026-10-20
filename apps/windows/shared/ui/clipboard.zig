//! The Windows clipboard as UTF-8 text, and the files copied in Explorer
//! (CF_HDROP). Used by the text fields and the terminal.

const std = @import("std");
const w = @import("win32");
const c = w.c;

/// The text on the clipboard, owned by the caller; null when there is none.
pub fn readText(gpa: std.mem.Allocator, hwnd: c.HWND) ?[]u8 {
    if (c.OpenClipboard(hwnd) == 0) return null;
    defer _ = c.CloseClipboard();
    const handle = c.GetClipboardData(c.CF_UNICODETEXT) orelse return null;
    const raw = c.GlobalLock(handle) orelse return null;
    defer _ = c.GlobalUnlock(handle);
    const wide: [*:0]const u16 = @ptrCast(@alignCast(raw));
    const text = std.unicode.wtf16LeToWtf8Alloc(gpa, std.mem.span(wide)) catch return null;
    // Windows line ends become the \n the shell and the fields expect.
    var n: usize = 0;
    for (text) |b| {
        if (b == '\r') continue;
        text[n] = b;
        n += 1;
    }
    return gpa.realloc(text, n) catch text[0..n];
}

pub fn writeText(gpa: std.mem.Allocator, hwnd: c.HWND, text: []const u8) void {
    // \n back to \r\n, which other Windows apps paste as line breaks.
    var crlf: std.ArrayList(u8) = .empty;
    defer crlf.deinit(gpa);
    for (text) |b| {
        if (b == '\n') crlf.append(gpa, '\r') catch return;
        crlf.append(gpa, b) catch return;
    }
    const wide = std.unicode.wtf8ToWtf16LeAllocZ(gpa, crlf.items) catch return;
    defer gpa.free(wide);
    const bytes = (wide.len + 1) * 2;
    const memory = c.GlobalAlloc(c.GMEM_MOVEABLE, bytes) orelse return;
    const raw = c.GlobalLock(memory) orelse return;
    @memcpy(@as([*]u8, @ptrCast(raw))[0..bytes], std.mem.sliceAsBytes(wide.ptr[0 .. wide.len + 1]));
    _ = c.GlobalUnlock(memory);
    if (c.OpenClipboard(hwnd) == 0) {
        _ = c.GlobalFree(memory);
        return;
    }
    defer _ = c.CloseClipboard();
    _ = c.EmptyClipboard();
    // The clipboard owns the memory once set.
    if (c.SetClipboardData(c.CF_UNICODETEXT, memory) == null) _ = c.GlobalFree(memory);
}

/// The files copied in Explorer, as full paths; empty when none.
pub fn readFiles(gpa: std.mem.Allocator, hwnd: c.HWND) [][]u8 {
    if (c.OpenClipboard(hwnd) == 0) return &.{};
    defer _ = c.CloseClipboard();
    const handle = c.GetClipboardData(c.CF_HDROP) orelse return &.{};
    return dropFiles(gpa, @ptrCast(@alignCast(handle)));
}

/// The paths in an HDROP (the clipboard's, or a drag onto the window).
pub fn dropFiles(gpa: std.mem.Allocator, drop: c.HDROP) [][]u8 {
    const count = c.DragQueryFileW(drop, 0xFFFFFFFF, null, 0);
    var list: std.ArrayList([]u8) = .empty;
    var i: c.UINT = 0;
    while (i < count) : (i += 1) {
        var buf: [32768]u16 = undefined;
        const n = c.DragQueryFileW(drop, i, &buf, buf.len);
        if (n == 0) continue;
        const path = std.unicode.wtf16LeToWtf8Alloc(gpa, buf[0..n]) catch continue;
        list.append(gpa, path) catch gpa.free(path);
    }
    return list.toOwnedSlice(gpa) catch &.{};
}

test {
    @import("std").testing.refAllDecls(@This());
}
