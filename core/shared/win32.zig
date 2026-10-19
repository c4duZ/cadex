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

// Files (fs_windows.zig).

pub const WCHAR = u16;
pub const LPCWSTR = [*:0]const WCHAR;
pub const INVALID_HANDLE_VALUE = windows.INVALID_HANDLE_VALUE;
pub const FILETIME = windows.FILETIME;

pub const GENERIC_READ: DWORD = 0x80000000;
pub const GENERIC_WRITE: DWORD = 0x40000000;
pub const FILE_SHARE_READ: DWORD = 0x1;
pub const FILE_SHARE_WRITE: DWORD = 0x2;
pub const FILE_SHARE_DELETE: DWORD = 0x4;
pub const CREATE_NEW: DWORD = 1;
pub const CREATE_ALWAYS: DWORD = 2;
pub const OPEN_EXISTING: DWORD = 3;
pub const FILE_ATTRIBUTE_DIRECTORY: DWORD = 0x10;
pub const FILE_ATTRIBUTE_NORMAL: DWORD = 0x80;
pub const FILE_ATTRIBUTE_REPARSE_POINT: DWORD = 0x400;
pub const FILE_FLAG_BACKUP_SEMANTICS: DWORD = 0x02000000;
pub const FILE_FLAG_OPEN_REPARSE_POINT: DWORD = 0x00200000;
pub const IO_REPARSE_TAG_MOUNT_POINT: DWORD = 0xA0000003;
pub const IO_REPARSE_TAG_SYMLINK: DWORD = 0xA000000C;
pub const MOVEFILE_REPLACE_EXISTING: DWORD = 0x1;
pub const MOVEFILE_WRITE_THROUGH: DWORD = 0x8;
pub const COPY_FILE_FAIL_IF_EXISTS: DWORD = 0x1;
pub const COPY_FILE_COPY_SYMLINK: DWORD = 0x800;
pub const FIND_FIRST_EX_LARGE_FETCH: DWORD = 0x2;
/// FindExInfoBasic and FindExSearchNameMatch.
pub const FindExInfoBasic: c_int = 1;
pub const FindExSearchNameMatch: c_int = 0;
pub const GetFileExInfoStandard: c_int = 0;

pub const ERROR_FILE_NOT_FOUND: DWORD = 2;
pub const ERROR_PATH_NOT_FOUND: DWORD = 3;
pub const ERROR_ACCESS_DENIED: DWORD = 5;
pub const ERROR_NOT_ENOUGH_MEMORY: DWORD = 8;
pub const ERROR_OUTOFMEMORY: DWORD = 14;
pub const ERROR_NOT_SAME_DEVICE: DWORD = 17;
pub const ERROR_NO_MORE_FILES: DWORD = 18;
pub const ERROR_SHARING_VIOLATION: DWORD = 32;
pub const ERROR_HANDLE_EOF: DWORD = 38;
pub const ERROR_FILE_EXISTS: DWORD = 80;
pub const ERROR_BROKEN_PIPE: DWORD = 109;
pub const ERROR_INVALID_NAME: DWORD = 123;
pub const ERROR_DIR_NOT_EMPTY: DWORD = 145;
pub const ERROR_ALREADY_EXISTS: DWORD = 183;
pub const ERROR_FILENAME_EXCED_RANGE: DWORD = 206;
pub const ERROR_DIRECTORY: DWORD = 267;

pub const WIN32_FIND_DATAW = extern struct {
    dwFileAttributes: DWORD,
    ftCreationTime: FILETIME,
    ftLastAccessTime: FILETIME,
    ftLastWriteTime: FILETIME,
    nFileSizeHigh: DWORD,
    nFileSizeLow: DWORD,
    /// The reparse tag, when the attributes have FILE_ATTRIBUTE_REPARSE_POINT.
    dwReserved0: DWORD,
    dwReserved1: DWORD,
    cFileName: [260]WCHAR,
    cAlternateFileName: [14]WCHAR,
};

pub const BY_HANDLE_FILE_INFORMATION = extern struct {
    dwFileAttributes: DWORD,
    ftCreationTime: FILETIME,
    ftLastAccessTime: FILETIME,
    ftLastWriteTime: FILETIME,
    dwVolumeSerialNumber: DWORD,
    nFileSizeHigh: DWORD,
    nFileSizeLow: DWORD,
    nNumberOfLinks: DWORD,
    nFileIndexHigh: DWORD,
    nFileIndexLow: DWORD,
};

pub const WIN32_FILE_ATTRIBUTE_DATA = extern struct {
    dwFileAttributes: DWORD,
    ftCreationTime: FILETIME,
    ftLastAccessTime: FILETIME,
    ftLastWriteTime: FILETIME,
    nFileSizeHigh: DWORD,
    nFileSizeLow: DWORD,
};

pub extern "kernel32" fn CreateFileW(name: LPCWSTR, access: DWORD, share: DWORD, security: ?*anyopaque, disposition: DWORD, flags: DWORD, template: ?HANDLE) callconv(.winapi) HANDLE;
pub extern "kernel32" fn ReadFile(file: HANDLE, buffer: [*]u8, len: DWORD, read: ?*DWORD, overlapped: ?*anyopaque) callconv(.winapi) BOOL;
pub extern "kernel32" fn WriteFile(file: HANDLE, buffer: [*]const u8, len: DWORD, written: ?*DWORD, overlapped: ?*anyopaque) callconv(.winapi) BOOL;
pub extern "kernel32" fn FlushFileBuffers(file: HANDLE) callconv(.winapi) BOOL;
pub extern "kernel32" fn GetFileInformationByHandle(file: HANDLE, info: *BY_HANDLE_FILE_INFORMATION) callconv(.winapi) BOOL;
pub extern "kernel32" fn GetFileAttributesExW(name: LPCWSTR, level: c_int, info: *WIN32_FILE_ATTRIBUTE_DATA) callconv(.winapi) BOOL;
pub extern "kernel32" fn GetFinalPathNameByHandleW(file: HANDLE, path: [*]WCHAR, len: DWORD, flags: DWORD) callconv(.winapi) DWORD;
pub extern "kernel32" fn FindFirstFileExW(name: LPCWSTR, level: c_int, data: *WIN32_FIND_DATAW, search: c_int, filter: ?*anyopaque, flags: DWORD) callconv(.winapi) HANDLE;
pub extern "kernel32" fn FindNextFileW(find: HANDLE, data: *WIN32_FIND_DATAW) callconv(.winapi) BOOL;
pub extern "kernel32" fn FindClose(find: HANDLE) callconv(.winapi) BOOL;
pub extern "kernel32" fn CreateDirectoryW(name: LPCWSTR, security: ?*anyopaque) callconv(.winapi) BOOL;
pub extern "kernel32" fn MoveFileExW(from: LPCWSTR, to: LPCWSTR, flags: DWORD) callconv(.winapi) BOOL;
pub extern "kernel32" fn CopyFileExW(from: LPCWSTR, to: LPCWSTR, progress: ?*anyopaque, data: ?*anyopaque, cancel: ?*BOOL, flags: DWORD) callconv(.winapi) BOOL;
pub extern "kernel32" fn DeleteFileW(name: LPCWSTR) callconv(.winapi) BOOL;
