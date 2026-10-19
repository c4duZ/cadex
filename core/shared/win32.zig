//! The Win32 functions the core calls, declared by hand: Zig 0.16's std
//! binds almost only ntdll, and a generated bindings package is far more
//! than the core uses (docs/adr/0012-windows-zig-win32-d3d11.md). Only
//! referenced on Windows, so these never reach the macOS link.

const std = @import("std");
const windows = std.os.windows;

pub const BOOL = windows.BOOL;
pub const DWORD = windows.DWORD;
pub const HANDLE = windows.HANDLE;
pub const SRWLOCK = windows.SRWLOCK;
pub const CONDITION_VARIABLE = windows.CONDITION_VARIABLE;

pub const INFINITE: DWORD = 0xFFFFFFFF;

pub extern "kernel32" fn AcquireSRWLockExclusive(lock: *SRWLOCK) callconv(.winapi) void;
pub extern "kernel32" fn ReleaseSRWLockExclusive(lock: *SRWLOCK) callconv(.winapi) void;
pub extern "kernel32" fn SleepConditionVariableSRW(cond: *CONDITION_VARIABLE, lock: *SRWLOCK, ms: DWORD, flags: windows.ULONG) callconv(.winapi) BOOL;
pub extern "kernel32" fn WakeConditionVariable(cond: *CONDITION_VARIABLE) callconv(.winapi) void;
pub extern "kernel32" fn Sleep(ms: DWORD) callconv(.winapi) void;
pub extern "kernel32" fn GetTickCount64() callconv(.winapi) u64;
pub extern "kernel32" fn GetLastError() callconv(.winapi) DWORD;
pub extern "kernel32" fn CloseHandle(handle: HANDLE) callconv(.winapi) BOOL;
pub extern "kernel32" fn GetCurrentProcessId() callconv(.winapi) DWORD;
