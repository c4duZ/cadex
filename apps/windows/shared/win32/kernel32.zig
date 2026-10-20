//! kernel32.dll: the process and debugging output.

const w = @import("win32.zig");

pub extern "kernel32" fn GetModuleHandleW(name: ?w.LPCWSTR) callconv(.winapi) ?w.HINSTANCE;
pub extern "kernel32" fn OutputDebugStringW(text: w.LPCWSTR) callconv(.winapi) void;
