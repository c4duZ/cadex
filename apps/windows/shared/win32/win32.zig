//! The Win32 the app calls, declared by hand and only what is used
//! (docs/adr/0012-windows-zig-win32-d3d11.md): no generated bindings
//! package. One file per DLL; this file gathers them and the shared types.

const std = @import("std");

pub const kernel32 = @import("kernel32.zig");
pub const user32 = @import("user32.zig");

pub const BOOL = c_int;
pub const UINT = c_uint;
pub const DWORD = u32;
pub const WORD = u16;
pub const ATOM = u16;
pub const LONG = i32;
pub const WPARAM = usize;
pub const LPARAM = isize;
pub const LRESULT = isize;
pub const HANDLE = *anyopaque;
pub const HINSTANCE = *opaque {};
pub const HWND = *opaque {};
pub const HICON = *opaque {};
pub const HCURSOR = *opaque {};
pub const HBRUSH = *opaque {};
pub const HMENU = *opaque {};
pub const LPCWSTR = [*:0]const u16;

pub const POINT = extern struct { x: LONG, y: LONG };
pub const RECT = extern struct { left: LONG, top: LONG, right: LONG, bottom: LONG };

/// A UTF-16 literal for the W functions.
pub fn L(comptime text: []const u8) LPCWSTR {
    return std.unicode.utf8ToUtf16LeStringLiteral(text);
}
