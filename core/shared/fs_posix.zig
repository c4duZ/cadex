//! The file system on the Mac, through libc. The interface is `fs.zig`;
//! `fs_windows.zig` is the same on Win32.

const std = @import("std");
const c = std.c;
const fs = @import("fs.zig");

const Error = fs.Error;
const Kind = fs.Kind;
const Info = fs.Info;

pub const max_path = c.PATH_MAX;

// Not in Zig's libc bindings for macOS: <dirent.h>, <unistd.h>, <sys/stat.h>,
// <sys/stdio.h> and <copyfile.h>.
extern "c" fn dirfd(dir: *c.DIR) c.fd_t;
extern "c" fn fchmod(fd: c.fd_t, mode: c.mode_t) c_int;
extern "c" fn fsync(fd: c.fd_t) c_int;
extern "c" fn renamex_np(from: [*:0]const u8, to: [*:0]const u8, flags: c_uint) c_int;
extern "c" fn copyfile(from: [*:0]const u8, to: [*:0]const u8, state: ?*anyopaque, flags: u32) c_int;
const RENAME_EXCL: c_uint = 0x4;
const COPYFILE_ALL: u32 = 0xF;
const COPYFILE_RECURSIVE: u32 = 1 << 15;
const COPYFILE_EXCL: u32 = 1 << 17;
const COPYFILE_NOFOLLOW_SRC: u32 = 1 << 18;
/// APFS clones the file instead of copying the bytes when it can.
const COPYFILE_CLONE: u32 = 1 << 24;

/// The error for the errno the last failed libc call left.
fn lastError() Error {
    const e: c.E = @enumFromInt(c._errno().*);
    return switch (e) {
        .NOENT => error.NotFound,
        .ACCES, .PERM => error.PermissionDenied,
        .EXIST, .NOTEMPTY => error.AlreadyExists,
        .NOTDIR => error.NotDirectory,
        .ISDIR => error.IsDirectory,
        .XDEV => error.CrossDevice,
        .NAMETOOLONG => error.NameTooLong,
        .NOMEM => error.OutOfMemory,
        else => error.Unexpected,
    };
}

fn terminate(path: []const u8, out: *fs.Buffer) Error![:0]const u8 {
    if (path.len >= max_path) return error.NameTooLong;
    @memcpy(out[0..path.len], path);
    out[path.len] = 0;
    return out[0..path.len :0];
}

fn kindOf(mode: c.mode_t) Kind {
    return switch (mode & c.S.IFMT) {
        c.S.IFREG => .file,
        c.S.IFDIR => .directory,
        c.S.IFLNK => .symlink,
        else => .other,
    };
}

fn infoOf(st: c.Stat) Info {
    const kind = kindOf(st.mode);
    return .{ .kind = kind, .size = if (kind == .file) @intCast(st.size) else 0, .mode = st.mode & 0o7777 };
}

pub fn realPath(path: []const u8, out: *fs.Buffer) ?[]const u8 {
    var z: fs.Buffer = undefined;
    const p = terminate(path, &z) catch return null;
    const real = c.realpath(p.ptr, out) orelse return null;
    return std.mem.span(real);
}

pub fn info(path: []const u8, follow: bool) ?Info {
    var z: fs.Buffer = undefined;
    const p = terminate(path, &z) catch return null;
    var st: c.Stat = undefined;
    if (c.fstatat(c.AT.FDCWD, p.ptr, &st, if (follow) 0 else c.AT.SYMLINK_NOFOLLOW) != 0) return null;
    return infoOf(st);
}

pub const File = struct {
    fd: c.fd_t,

    pub fn openRead(path: []const u8, options: fs.OpenOptions) Error!File {
        var z: fs.Buffer = undefined;
        const p = try terminate(path, &z);
        const fd = c.open(p.ptr, .{ .ACCMODE = .RDONLY, .CLOEXEC = true, .NOFOLLOW = !options.follow });
        if (fd < 0) return lastError();
        return .{ .fd = fd };
    }

    pub fn close(self: File) void {
        _ = c.close(self.fd);
    }

    pub fn info(self: File) Error!Info {
        var st: c.Stat = undefined;
        if (c.fstat(self.fd, &st) != 0) return lastError();
        return infoOf(st);
    }

    /// Up to out.len bytes; 0 at the end of the file.
    pub fn read(self: File, out: []u8) Error!usize {
        while (true) {
            const n = c.read(self.fd, out.ptr, out.len);
            if (n >= 0) return @intCast(n);
            if (c.errno(n) == .INTR) continue;
            return lastError();
        }
    }
};

pub fn createNew(path: []const u8) Error!void {
    var z: fs.Buffer = undefined;
    const fd = c.open((try terminate(path, &z)).ptr, .{ .ACCMODE = .WRONLY, .CREAT = true, .EXCL = true, .CLOEXEC = true }, @as(c.mode_t, 0o644));
    if (fd < 0) return lastError();
    _ = c.close(fd);
}

pub fn makeDirectory(path: []const u8) Error!void {
    var z: fs.Buffer = undefined;
    if (c.mkdir((try terminate(path, &z)).ptr, 0o755) != 0) return lastError();
}

pub fn rename(from: []const u8, to: []const u8, exclusive: bool) Error!void {
    var from_z: fs.Buffer = undefined;
    var to_z: fs.Buffer = undefined;
    const rc = renamex_np((try terminate(from, &from_z)).ptr, (try terminate(to, &to_z)).ptr, if (exclusive) RENAME_EXCL else 0);
    if (rc != 0) return lastError();
}

pub fn copyTree(from: []const u8, to: []const u8) Error!void {
    var from_z: fs.Buffer = undefined;
    var to_z: fs.Buffer = undefined;
    const flags = COPYFILE_ALL | COPYFILE_RECURSIVE | COPYFILE_EXCL | COPYFILE_NOFOLLOW_SRC | COPYFILE_CLONE;
    if (copyfile((try terminate(from, &from_z)).ptr, (try terminate(to, &to_z)).ptr, null, flags) != 0)
        return lastError();
}

/// Writes `data` to the new file `tmp` with `mode`, flushed to the disk,
/// then renames it over `path`.
pub fn writeThenRename(tmp: []const u8, path: []const u8, data: []const u8, mode: u32) Error!void {
    var tmp_z: fs.Buffer = undefined;
    var path_z: fs.Buffer = undefined;
    const t = try terminate(tmp, &tmp_z);
    const p = try terminate(path, &path_z);
    const fd = c.open(t.ptr, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true, .CLOEXEC = true }, @as(c.mode_t, 0o600));
    if (fd < 0) return lastError();
    var ok = false;
    defer if (!ok) {
        _ = c.unlink(t.ptr);
    };
    {
        defer _ = c.close(fd);
        var at: usize = 0;
        while (at < data.len) {
            const n = c.write(fd, data[at..].ptr, data.len - at);
            if (n < 0) {
                if (c.errno(n) == .INTR) continue;
                return lastError();
            }
            at += @intCast(n);
        }
        if (fchmod(fd, @intCast(mode)) != 0 or fsync(fd) != 0) return lastError();
    }
    if (c.rename(t.ptr, p.ptr) != 0) return lastError();
    ok = true;
}

pub fn processId() u32 {
    return @intCast(c.getpid());
}

pub const DirReader = struct {
    dir: *c.DIR,
    fd: c.fd_t,

    pub fn open(path: []const u8) Error!DirReader {
        var z: fs.Buffer = undefined;
        const dir = c.opendir((try terminate(path, &z)).ptr) orelse return lastError();
        return .{ .dir = dir, .fd = dirfd(dir) };
    }

    pub fn close(self: *DirReader) void {
        _ = c.closedir(self.dir);
    }

    /// The next entry, without following links, skipping `.` and `..` and
    /// entries gone before they could be looked at. The name lives until
    /// the next call.
    pub fn next(self: *DirReader) ?fs.DirEntry {
        while (c.readdir(self.dir)) |ent| {
            const name = ent.name[0..ent.namlen];
            if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) continue;
            const st = self.statAt(name, false) orelse continue;
            const entry = infoOf(st);
            return .{ .name = name, .kind = entry.kind, .size = entry.size };
        }
        return null;
    }

    /// Whether the entry `name`, a link, points to a folder.
    pub fn linksToDirectory(self: *DirReader, name: []const u8) bool {
        const st = self.statAt(name, true) orelse return false;
        return kindOf(st.mode) == .directory;
    }

    fn statAt(self: *DirReader, name: []const u8, follow: bool) ?c.Stat {
        var z: fs.Buffer = undefined;
        const p = terminate(name, &z) catch return null;
        var st: c.Stat = undefined;
        if (c.fstatat(self.fd, p.ptr, &st, if (follow) 0 else c.AT.SYMLINK_NOFOLLOW) != 0) return null;
        return st;
    }
};
