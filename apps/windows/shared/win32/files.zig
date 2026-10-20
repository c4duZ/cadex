//! The app's own files (settings.json, spaces.json, pasted images): read
//! whole, written by replacing atomically, under %APPDATA%\Cadex. Files of
//! the workspace go through the core instead (the explorer feature), which
//! checks they are inside an authorized folder.

const std = @import("std");
const c = @import("sdk");

fn wide(gpa: std.mem.Allocator, path: []const u8) ![:0]u16 {
    return std.unicode.wtf8ToWtf16LeAllocZ(gpa, path);
}

/// The whole file, owned by the caller; null when it cannot be read.
pub fn read(gpa: std.mem.Allocator, path: []const u8, max_bytes: usize) ?[]u8 {
    const p = wide(gpa, path) catch return null;
    defer gpa.free(p);
    const h = c.CreateFileW(p.ptr, c.GENERIC_READ, c.FILE_SHARE_READ | c.FILE_SHARE_WRITE | c.FILE_SHARE_DELETE, null, c.OPEN_EXISTING, c.FILE_ATTRIBUTE_NORMAL, null);
    if (h == c.INVALID_HANDLE_VALUE) return null;
    defer _ = c.CloseHandle(h);
    var size: c.LARGE_INTEGER = undefined;
    if (c.GetFileSizeEx(h, &size) == 0 or size.QuadPart < 0 or @as(u64, @intCast(size.QuadPart)) > max_bytes) return null;
    const bytes = gpa.alloc(u8, @intCast(size.QuadPart)) catch return null;
    var at: usize = 0;
    while (at < bytes.len) {
        var n: c.DWORD = 0;
        if (c.ReadFile(h, bytes[at..].ptr, @intCast(bytes.len - at), &n, null) == 0 or n == 0) break;
        at += n;
    }
    return bytes[0..at];
}

/// Writes `data` next to `path` and moves it over, so a crash never
/// leaves half a file. Creates the folder if needed.
pub fn writeAtomic(gpa: std.mem.Allocator, path: []const u8, data: []const u8) !void {
    if (std.fs.path.dirname(path)) |dir| makeFolder(gpa, dir);
    const tmp = try std.fmt.allocPrint(gpa, "{s}.cadex-tmp", .{path});
    defer gpa.free(tmp);
    const t = try wide(gpa, tmp);
    defer gpa.free(t);
    const h = c.CreateFileW(t.ptr, c.GENERIC_WRITE, 0, null, c.CREATE_ALWAYS, c.FILE_ATTRIBUTE_NORMAL, null);
    if (h == c.INVALID_HANDLE_VALUE) return error.WriteFailed;
    var ok = false;
    {
        defer _ = c.CloseHandle(h);
        var at: usize = 0;
        while (at < data.len) {
            var n: c.DWORD = 0;
            if (c.WriteFile(h, data[at..].ptr, @intCast(@min(data.len - at, 1 << 30)), &n, null) == 0) break;
            at += n;
        }
        ok = at == data.len and c.FlushFileBuffers(h) != 0;
    }
    const p = try wide(gpa, path);
    defer gpa.free(p);
    if (!ok or c.MoveFileExW(t.ptr, p.ptr, c.MOVEFILE_REPLACE_EXISTING | c.MOVEFILE_WRITE_THROUGH) == 0) {
        _ = c.DeleteFileW(t.ptr);
        return error.WriteFailed;
    }
}

pub fn makeFolder(gpa: std.mem.Allocator, path: []const u8) void {
    const p = wide(gpa, path) catch return;
    defer gpa.free(p);
    _ = c.SHCreateDirectoryExW(null, p.ptr, null);
}

/// When the file last changed (100 ns ticks), or 0 when it is not there:
/// the settings are polled with it to follow edits by hand.
pub fn modified(gpa: std.mem.Allocator, path: []const u8) u64 {
    const p = wide(gpa, path) catch return 0;
    defer gpa.free(p);
    var data: c.WIN32_FILE_ATTRIBUTE_DATA = undefined;
    if (c.GetFileAttributesExW(p.ptr, c.GetFileExInfoStandard, &data) == 0) return 0;
    return (@as(u64, data.ftLastWriteTime.dwHighDateTime) << 32) | data.ftLastWriteTime.dwLowDateTime;
}

/// %APPDATA%\Cadex\<name>, the Windows place of Application Support/Cadex.
pub fn appData(gpa: std.mem.Allocator, name: []const u8) ![]u8 {
    var raw: [*c]u16 = null;
    const folder_id = comptime guidOf("3eb685db-65f9-4cf6-a03a-e3ef65729f3d"); // FOLDERID_RoamingAppData
    if (c.SHGetKnownFolderPath(&folder_id, 0, null, &raw) < 0) return error.NoAppData;
    defer c.CoTaskMemFree(raw);
    const base = try std.unicode.wtf16LeToWtf8Alloc(gpa, std.mem.span(@as([*:0]u16, @ptrCast(raw))));
    defer gpa.free(base);
    return std.fmt.allocPrint(gpa, "{s}\\Cadex\\{s}", .{ base, name });
}

fn guidOf(comptime text: []const u8) c.GUID {
    return @import("win32.zig").guid(text);
}

test {
    std.testing.refAllDecls(@This());
}
