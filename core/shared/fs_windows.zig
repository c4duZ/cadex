//! The file system on Windows, through Win32's wide-character functions.
//! The interface is `fs.zig`; `fs_posix.zig` is the same on the Mac. Paths
//! come in and go out as UTF-8 (WTF-8, so any name NTFS allows survives).

const std = @import("std");
const w = @import("win32.zig");
const fs = @import("fs.zig");

const Error = fs.Error;
const Kind = fs.Kind;
const Info = fs.Info;

/// Bytes of UTF-8. Windows 11 takes paths past the old 260 characters
/// when the app's manifest opts in (plan 10, phase A).
pub const max_path = 4096;
const WidePath = [max_path:0]u16;

const share_all = w.FILE_SHARE_READ | w.FILE_SHARE_WRITE | w.FILE_SHARE_DELETE;

fn lastError() Error {
    return switch (w.GetLastError()) {
        w.ERROR_FILE_NOT_FOUND, w.ERROR_PATH_NOT_FOUND, w.ERROR_INVALID_NAME => error.NotFound,
        w.ERROR_ACCESS_DENIED, w.ERROR_SHARING_VIOLATION => error.PermissionDenied,
        w.ERROR_FILE_EXISTS, w.ERROR_ALREADY_EXISTS, w.ERROR_DIR_NOT_EMPTY => error.AlreadyExists,
        w.ERROR_DIRECTORY => error.NotDirectory,
        w.ERROR_NOT_SAME_DEVICE => error.CrossDevice,
        w.ERROR_FILENAME_EXCED_RANGE => error.NameTooLong,
        w.ERROR_NOT_ENOUGH_MEMORY, w.ERROR_OUTOFMEMORY => error.OutOfMemory,
        else => error.Unexpected,
    };
}

fn wide(path: []const u8, out: *WidePath) Error![:0]const u16 {
    if (path.len >= max_path) return error.NameTooLong;
    const n = std.unicode.wtf8ToWtf16Le(out, path) catch return error.NotFound;
    out[n] = 0;
    return out[0..n :0];
}

/// A Win32 name back to UTF-8 in `out`.
fn narrow(name: []const u16, out: []u8) ?[]const u8 {
    // Each UTF-16 unit is at most 3 bytes of WTF-8.
    if (name.len * 3 > out.len) return null;
    return out[0..std.unicode.wtf16LeToWtf8(out, name)];
}

fn kindOf(attributes: w.DWORD, reparse_tag: w.DWORD) Kind {
    // Only real links count: OneDrive and dedup files are reparse points
    // too, and they are plain files to the user.
    if (attributes & w.FILE_ATTRIBUTE_REPARSE_POINT != 0 and
        (reparse_tag == w.IO_REPARSE_TAG_SYMLINK or reparse_tag == w.IO_REPARSE_TAG_MOUNT_POINT)) return .symlink;
    return if (attributes & w.FILE_ATTRIBUTE_DIRECTORY != 0) .directory else .file;
}

fn sizeOf(kind: Kind, high: w.DWORD, low: w.DWORD) u64 {
    return if (kind == .file) (@as(u64, high) << 32) | low else 0;
}

/// Opens for reading attributes or bytes; folders too (backup semantics).
fn openHandle(path: []const u8, access: w.DWORD, follow: bool) Error!w.HANDLE {
    var buf: WidePath = undefined;
    const flags = w.FILE_FLAG_BACKUP_SEMANTICS | if (follow) 0 else w.FILE_FLAG_OPEN_REPARSE_POINT;
    const h = w.CreateFileW((try wide(path, &buf)).ptr, access, share_all, null, w.OPEN_EXISTING, flags, null);
    if (h == w.INVALID_HANDLE_VALUE) return lastError();
    return h;
}

pub fn realPath(path: []const u8, out: *fs.Buffer) ?[]const u8 {
    const h = openHandle(path, 0, true) catch return null;
    defer _ = w.CloseHandle(h);
    var buf: WidePath = undefined;
    // 0: FILE_NAME_NORMALIZED and VOLUME_NAME_DOS, the "\\?\C:\..." form,
    // with the case the disk has.
    const n = w.GetFinalPathNameByHandleW(h, &buf, buf.len, 0);
    if (n == 0 or n >= buf.len) return null;
    var name: []const u16 = buf[0..n];
    const unc = std.unicode.wtf8ToWtf16LeStringLiteral("\\\\?\\UNC\\");
    const local = std.unicode.wtf8ToWtf16LeStringLiteral("\\\\?\\");
    if (std.mem.startsWith(u16, name, unc)) {
        // \\?\UNC\server\share -> \\server\share
        name = name[unc.len - 2 ..];
        const text = narrow(name, out[1..]) orelse return null;
        out[0] = '\\';
        out[1] = '\\';
        return out[0 .. text.len + 1];
    }
    if (std.mem.startsWith(u16, name, local)) name = name[local.len..];
    return narrow(name, out);
}

pub const info = pathInfo;

fn pathInfo(path: []const u8, follow: bool) ?Info {
    if (follow) {
        const h = openHandle(path, 0, true) catch return null;
        defer _ = w.CloseHandle(h);
        return handleInfo(h) catch null;
    }
    // FindFirstFileExW is the one call that tells the link's own kind
    // and reparse tag; it fails on a drive root, which is a folder.
    var buf: WidePath = undefined;
    const p = wide(path, &buf) catch return null;
    var data: w.WIN32_FIND_DATAW = undefined;
    const find = w.FindFirstFileExW(p.ptr, w.FindExInfoBasic, &data, w.FindExSearchNameMatch, null, 0);
    if (find == w.INVALID_HANDLE_VALUE) {
        var attrs: w.WIN32_FILE_ATTRIBUTE_DATA = undefined;
        if (w.GetFileAttributesExW(p.ptr, w.GetFileExInfoStandard, &attrs) == 0) return null;
        const kind = kindOf(attrs.dwFileAttributes, 0);
        return .{ .kind = kind, .size = sizeOf(kind, attrs.nFileSizeHigh, attrs.nFileSizeLow), .mode = 0 };
    }
    _ = w.FindClose(find);
    const kind = kindOf(data.dwFileAttributes, data.dwReserved0);
    return .{ .kind = kind, .size = sizeOf(kind, data.nFileSizeHigh, data.nFileSizeLow), .mode = 0 };
}

fn handleInfo(h: w.HANDLE) Error!Info {
    var data: w.BY_HANDLE_FILE_INFORMATION = undefined;
    if (w.GetFileInformationByHandle(h, &data) == 0) return lastError();
    // Opened following links, so what is here is never a link itself.
    const kind: Kind = if (data.dwFileAttributes & w.FILE_ATTRIBUTE_DIRECTORY != 0) .directory else .file;
    return .{ .kind = kind, .size = sizeOf(kind, data.nFileSizeHigh, data.nFileSizeLow), .mode = 0 };
}

pub const File = struct {
    handle: w.HANDLE,

    pub fn openRead(path: []const u8, options: fs.OpenOptions) Error!File {
        if (!options.follow) {
            const found = pathInfo(path, false) orelse return error.NotFound;
            if (found.kind == .symlink) return error.NotFound;
        }
        return .{ .handle = try openHandle(path, w.GENERIC_READ, true) };
    }

    pub fn close(self: File) void {
        _ = w.CloseHandle(self.handle);
    }

    pub fn info(self: File) Error!Info {
        return handleInfo(self.handle);
    }

    /// Up to out.len bytes; 0 at the end of the file. A folder, which
    /// opens here, reads as a directory error like on the Mac.
    pub fn read(self: File, out: []u8) Error!usize {
        var n: w.DWORD = 0;
        const len: w.DWORD = @intCast(@min(out.len, std.math.maxInt(w.DWORD)));
        if (w.ReadFile(self.handle, out.ptr, len, &n, null) != 0) return n;
        return switch (w.GetLastError()) {
            w.ERROR_HANDLE_EOF, w.ERROR_BROKEN_PIPE => 0,
            w.ERROR_ACCESS_DENIED => if ((self.info() catch return error.PermissionDenied).kind == .directory) error.IsDirectory else error.PermissionDenied,
            else => lastError(),
        };
    }
};

pub fn createNew(path: []const u8) Error!void {
    var buf: WidePath = undefined;
    const h = w.CreateFileW((try wide(path, &buf)).ptr, w.GENERIC_WRITE, share_all, null, w.CREATE_NEW, w.FILE_ATTRIBUTE_NORMAL, null);
    if (h == w.INVALID_HANDLE_VALUE) return lastError();
    _ = w.CloseHandle(h);
}

pub fn makeDirectory(path: []const u8) Error!void {
    var buf: WidePath = undefined;
    if (w.CreateDirectoryW((try wide(path, &buf)).ptr, null) == 0) return lastError();
}

pub fn rename(from: []const u8, to: []const u8, exclusive: bool) Error!void {
    var from_w: WidePath = undefined;
    var to_w: WidePath = undefined;
    // Without MOVEFILE_COPY_ALLOWED, another volume fails with
    // ERROR_NOT_SAME_DEVICE (CrossDevice), as rename(2) does on the Mac.
    const flags: w.DWORD = if (exclusive) 0 else w.MOVEFILE_REPLACE_EXISTING;
    if (w.MoveFileExW((try wide(from, &from_w)).ptr, (try wide(to, &to_w)).ptr, flags) == 0) return lastError();
}

pub fn copyTree(from: []const u8, to: []const u8) Error!void {
    const found = pathInfo(from, false) orelse return error.NotFound;
    if (found.kind != .directory) return copyOne(from, to);
    try makeDirectory(to);
    var reader = try DirReader.open(from);
    defer reader.close();
    var from_child: fs.Buffer = undefined;
    var to_child: fs.Buffer = undefined;
    while (reader.next()) |entry| {
        const src = try fs.join(&from_child, from, entry.name);
        const dst = try fs.join(&to_child, to, entry.name);
        if (entry.kind == .directory) try copyTree(src, dst) else try copyOne(src, dst);
    }
}

/// A file, or a link as a link.
fn copyOne(from: []const u8, to: []const u8) Error!void {
    var from_w: WidePath = undefined;
    var to_w: WidePath = undefined;
    const flags = w.COPY_FILE_FAIL_IF_EXISTS | w.COPY_FILE_COPY_SYMLINK;
    if (w.CopyFileExW((try wide(from, &from_w)).ptr, (try wide(to, &to_w)).ptr, null, null, null, flags) == 0) return lastError();
}

/// Writes `data` to the new file `tmp`, flushed to the disk, then moves it
/// over `path`. `mode` means nothing on Windows.
pub fn writeThenRename(tmp: []const u8, path: []const u8, data: []const u8, mode: u32) Error!void {
    _ = mode;
    var tmp_w: WidePath = undefined;
    const t = try wide(tmp, &tmp_w);
    const h = w.CreateFileW(t.ptr, w.GENERIC_WRITE, 0, null, w.CREATE_ALWAYS, w.FILE_ATTRIBUTE_NORMAL, null);
    if (h == w.INVALID_HANDLE_VALUE) return lastError();
    var ok = false;
    defer if (!ok) {
        _ = w.DeleteFileW(t.ptr);
    };
    {
        defer _ = w.CloseHandle(h);
        var at: usize = 0;
        while (at < data.len) {
            var n: w.DWORD = 0;
            const len: w.DWORD = @intCast(@min(data.len - at, 1 << 30));
            if (w.WriteFile(h, data[at..].ptr, len, &n, null) == 0) return lastError();
            at += n;
        }
        if (w.FlushFileBuffers(h) == 0) return lastError();
    }
    var path_w: WidePath = undefined;
    if (w.MoveFileExW(t.ptr, (try wide(path, &path_w)).ptr, w.MOVEFILE_REPLACE_EXISTING | w.MOVEFILE_WRITE_THROUGH) == 0) return lastError();
    ok = true;
}

pub fn processId() u32 {
    return w.GetCurrentProcessId();
}

pub const DirReader = struct {
    find: w.HANDLE,
    data: w.WIN32_FIND_DATAW,
    /// The first entry comes with FindFirstFileExW, before any next().
    pending: bool,
    folder: fs.Buffer,
    folder_len: usize,
    name: [260 * 3]u8,

    pub fn open(path: []const u8) Error!DirReader {
        var self: DirReader = undefined;
        if (path.len >= self.folder.len) return error.NameTooLong;
        @memcpy(self.folder[0..path.len], path);
        self.folder_len = path.len;
        var pattern: fs.Buffer = undefined;
        var buf: WidePath = undefined;
        const p = try wide(try fs.join(&pattern, path, "*"), &buf);
        self.find = w.FindFirstFileExW(p.ptr, w.FindExInfoBasic, &self.data, w.FindExSearchNameMatch, null, w.FIND_FIRST_EX_LARGE_FETCH);
        if (self.find == w.INVALID_HANDLE_VALUE) {
            if (w.GetLastError() == w.ERROR_FILE_NOT_FOUND and fs.isDirectory(path)) {
                self.pending = false;
                return self;
            }
            return lastError();
        }
        self.pending = true;
        return self;
    }

    pub fn close(self: *DirReader) void {
        if (self.find != w.INVALID_HANDLE_VALUE) _ = w.FindClose(self.find);
    }

    /// The next entry, without following links, skipping `.` and `..`.
    /// The name lives until the next call.
    pub fn next(self: *DirReader) ?fs.DirEntry {
        if (self.find == w.INVALID_HANDLE_VALUE) return null;
        while (true) {
            if (!self.pending and w.FindNextFileW(self.find, &self.data) == 0) return null;
            self.pending = false;
            const wide_name = std.mem.sliceTo(&self.data.cFileName, 0);
            const name = narrow(wide_name, &self.name) orelse continue;
            if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) continue;
            const kind = kindOf(self.data.dwFileAttributes, self.data.dwReserved0);
            return .{ .name = name, .kind = kind, .size = sizeOf(kind, self.data.nFileSizeHigh, self.data.nFileSizeLow) };
        }
    }

    /// Whether the entry `name`, a link, points to a folder.
    pub fn linksToDirectory(self: *DirReader, name: []const u8) bool {
        var buf: fs.Buffer = undefined;
        return fs.isDirectory(fs.join(&buf, self.folder[0..self.folder_len], name) catch return false);
    }
};
