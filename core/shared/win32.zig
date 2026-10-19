//! The Win32 functions the core calls, declared by hand: Zig 0.16's std
//! binds almost only ntdll, and a generated bindings package is far more
//! than the core uses (docs/adr/0012-windows-zig-win32-d3d11.md). Only
//! referenced on Windows, so these never reach the macOS link.

const std = @import("std");
const windows = std.os.windows;

/// A plain int: Zig 0.16's windows.BOOL is a wrapper type, awkward against 0.
pub const BOOL = c_int;
pub const DWORD = windows.DWORD;
pub const HANDLE = windows.HANDLE;
pub const SRWLOCK = windows.SRWLOCK;
pub const CONDITION_VARIABLE = windows.CONDITION_VARIABLE;

pub const INFINITE: DWORD = 0xFFFFFFFF;

pub extern "kernel32" fn AcquireSRWLockExclusive(lock: *SRWLOCK) callconv(.winapi) void;
pub extern "kernel32" fn ReleaseSRWLockExclusive(lock: *SRWLOCK) callconv(.winapi) void;
pub extern "kernel32" fn SleepConditionVariableSRW(cond: *CONDITION_VARIABLE, lock: *SRWLOCK, ms: DWORD, flags: u32) callconv(.winapi) BOOL;
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

// Processes (process_windows.zig) and the terminal's ConPTY.

pub const SECURITY_ATTRIBUTES = extern struct {
    nLength: DWORD = @sizeOf(SECURITY_ATTRIBUTES),
    lpSecurityDescriptor: ?*anyopaque = null,
    bInheritHandle: BOOL = 0,
};

pub const STARTUPINFOW = extern struct {
    cb: DWORD,
    lpReserved: ?[*:0]WCHAR = null,
    lpDesktop: ?[*:0]WCHAR = null,
    lpTitle: ?[*:0]WCHAR = null,
    dwX: DWORD = 0,
    dwY: DWORD = 0,
    dwXSize: DWORD = 0,
    dwYSize: DWORD = 0,
    dwXCountChars: DWORD = 0,
    dwYCountChars: DWORD = 0,
    dwFillAttribute: DWORD = 0,
    dwFlags: DWORD = 0,
    wShowWindow: u16 = 0,
    cbReserved2: u16 = 0,
    lpReserved2: ?*u8 = null,
    hStdInput: ?HANDLE = null,
    hStdOutput: ?HANDLE = null,
    hStdError: ?HANDLE = null,
};

pub const STARTUPINFOEXW = extern struct {
    StartupInfo: STARTUPINFOW,
    lpAttributeList: ?*anyopaque,
};

pub const PROCESS_INFORMATION = extern struct {
    hProcess: HANDLE,
    hThread: HANDLE,
    dwProcessId: DWORD,
    dwThreadId: DWORD,
};

pub const STARTF_USESTDHANDLES: DWORD = 0x100;
pub const CREATE_SUSPENDED: DWORD = 0x4;
pub const CREATE_UNICODE_ENVIRONMENT: DWORD = 0x400;
pub const CREATE_NO_WINDOW: DWORD = 0x08000000;
pub const EXTENDED_STARTUPINFO_PRESENT: DWORD = 0x00080000;
pub const PROC_THREAD_ATTRIBUTE_HANDLE_LIST: usize = 0x20002;
pub const PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE: usize = 0x20016;
pub const HANDLE_FLAG_INHERIT: DWORD = 0x1;
pub const WAIT_OBJECT_0: DWORD = 0;
pub const WAIT_TIMEOUT: DWORD = 258;
pub const STILL_ACTIVE: DWORD = 259;

pub extern "kernel32" fn CreatePipe(read: *HANDLE, write: *HANDLE, security: ?*const SECURITY_ATTRIBUTES, size: DWORD) callconv(.winapi) BOOL;
pub extern "kernel32" fn SetHandleInformation(handle: HANDLE, mask: DWORD, flags: DWORD) callconv(.winapi) BOOL;
pub extern "kernel32" fn CreateProcessW(app: ?LPCWSTR, command_line: ?[*:0]WCHAR, process_security: ?*anyopaque, thread_security: ?*anyopaque, inherit: BOOL, flags: DWORD, environment: ?*anyopaque, cwd: ?LPCWSTR, startup: *STARTUPINFOW, info: *PROCESS_INFORMATION) callconv(.winapi) BOOL;
pub extern "kernel32" fn InitializeProcThreadAttributeList(list: ?*anyopaque, count: DWORD, flags: DWORD, size: *usize) callconv(.winapi) BOOL;
pub extern "kernel32" fn UpdateProcThreadAttribute(list: *anyopaque, flags: DWORD, attribute: usize, value: *const anyopaque, size: usize, previous: ?*anyopaque, returned: ?*usize) callconv(.winapi) BOOL;
pub extern "kernel32" fn DeleteProcThreadAttributeList(list: *anyopaque) callconv(.winapi) void;
pub extern "kernel32" fn ResumeThread(thread: HANDLE) callconv(.winapi) DWORD;
pub extern "kernel32" fn WaitForSingleObject(handle: HANDLE, ms: DWORD) callconv(.winapi) DWORD;
pub extern "kernel32" fn GetExitCodeProcess(process: HANDLE, code: *DWORD) callconv(.winapi) BOOL;
pub extern "kernel32" fn TerminateProcess(process: HANDLE, code: c_uint) callconv(.winapi) BOOL;
pub extern "kernel32" fn CreateJobObjectW(security: ?*anyopaque, name: ?LPCWSTR) callconv(.winapi) ?HANDLE;
pub extern "kernel32" fn AssignProcessToJobObject(job: HANDLE, process: HANDLE) callconv(.winapi) BOOL;
pub extern "kernel32" fn TerminateJobObject(job: HANDLE, code: c_uint) callconv(.winapi) BOOL;
pub extern "kernel32" fn GetEnvironmentStringsW() callconv(.winapi) ?[*]WCHAR;
pub extern "kernel32" fn FreeEnvironmentStringsW(block: [*]WCHAR) callconv(.winapi) BOOL;

// ConPTY (features/terminal/pty_windows.zig).

pub const COORD = extern struct { X: i16, Y: i16 };
pub const HPCON = *anyopaque;
/// HRESULT; S_OK is 0.
pub const HRESULT = c_long;

pub const JOBOBJECT_BASIC_ACCOUNTING_INFORMATION = extern struct {
    TotalUserTime: i64,
    TotalKernelTime: i64,
    ThisPeriodTotalUserTime: i64,
    ThisPeriodTotalKernelTime: i64,
    TotalPageFaultCount: DWORD,
    TotalProcesses: DWORD,
    ActiveProcesses: DWORD,
    TotalTerminatedProcesses: DWORD,
};
pub const JobObjectBasicAccountingInformation: c_int = 1;

pub extern "kernel32" fn CreatePseudoConsole(size: COORD, input: HANDLE, output: HANDLE, flags: DWORD, console: *HPCON) callconv(.winapi) HRESULT;
pub extern "kernel32" fn ResizePseudoConsole(console: HPCON, size: COORD) callconv(.winapi) HRESULT;
pub extern "kernel32" fn ClosePseudoConsole(console: HPCON) callconv(.winapi) void;
pub extern "kernel32" fn QueryInformationJobObject(job: HANDLE, class: c_int, info: *anyopaque, len: DWORD, returned: ?*DWORD) callconv(.winapi) BOOL;
pub extern "kernel32" fn SearchPathW(path: ?LPCWSTR, name: LPCWSTR, extension: ?LPCWSTR, len: DWORD, buffer: [*]WCHAR, file_part: ?*?[*]WCHAR) callconv(.winapi) DWORD;
pub extern "kernel32" fn GetEnvironmentVariableW(name: LPCWSTR, buffer: [*]WCHAR, len: DWORD) callconv(.winapi) DWORD;

// Watching folders (features/explorer/watch_windows.zig).

pub const OVERLAPPED = extern struct {
    Internal: usize = 0,
    InternalHigh: usize = 0,
    Offset: DWORD = 0,
    OffsetHigh: DWORD = 0,
    hEvent: ?HANDLE = null,
};

/// The fixed part of one record; the name (UTF-16, relative to the
/// watched folder) follows it.
pub const FILE_NOTIFY_INFORMATION = extern struct {
    NextEntryOffset: DWORD,
    Action: DWORD,
    FileNameLength: DWORD,
};

pub const FILE_LIST_DIRECTORY: DWORD = 0x1;
pub const FILE_FLAG_OVERLAPPED: DWORD = 0x40000000;
pub const FILE_NOTIFY_CHANGE_FILE_NAME: DWORD = 0x1;
pub const FILE_NOTIFY_CHANGE_DIR_NAME: DWORD = 0x2;
pub const FILE_NOTIFY_CHANGE_SIZE: DWORD = 0x8;
pub const FILE_NOTIFY_CHANGE_LAST_WRITE: DWORD = 0x10;
pub const ERROR_OPERATION_ABORTED: DWORD = 995;

pub extern "kernel32" fn CreateEventW(security: ?*anyopaque, manual_reset: BOOL, initial: BOOL, name: ?LPCWSTR) callconv(.winapi) ?HANDLE;
pub extern "kernel32" fn SetEvent(event: HANDLE) callconv(.winapi) BOOL;
pub extern "kernel32" fn WaitForMultipleObjects(count: DWORD, handles: [*]const HANDLE, wait_all: BOOL, ms: DWORD) callconv(.winapi) DWORD;
pub extern "kernel32" fn ReadDirectoryChangesW(dir: HANDLE, buffer: *anyopaque, len: DWORD, subtree: BOOL, filter: DWORD, returned: ?*DWORD, overlapped: ?*OVERLAPPED, completion: ?*anyopaque) callconv(.winapi) BOOL;
pub extern "kernel32" fn GetOverlappedResult(file: HANDLE, overlapped: *OVERLAPPED, transferred: *DWORD, wait: BOOL) callconv(.winapi) BOOL;
pub extern "kernel32" fn CancelIoEx(file: HANDLE, overlapped: ?*OVERLAPPED) callconv(.winapi) BOOL;
