//! The file system on the Mac, through libc. The interface is `fs.zig`;
//! `fs_windows.zig` is the same on Win32.

const std = @import("std");
const builtin = @import("builtin");
const c = std.c;
const fs = @import("fs.zig");

/// Zig 0.16's std.c.Stat (and std.posix.Stat) is void on Linux, so the
/// libc `struct stat` is written out here. These are the glibc/musl layouts
/// for the architectures Cadex builds; fstat/fstatat write into it, so the
/// size and the field offsets must match the C header exactly.
const Stat = if (builtin.os.tag == .linux) LinuxStat else c.Stat;

const LinuxStat = switch (builtin.cpu.arch) {
    .x86_64 => extern struct {
        dev: u64,
        ino: u64,
        nlink: u64,
        mode: u32,
        uid: u32,
        gid: u32,
        __pad0: u32,
        rdev: u64,
        size: i64,
        blksize: i64,
        blocks: i64,
        atim: [2]i64,
        mtim: [2]i64,
        ctim: [2]i64,
        __reserved: [3]i64,
    },
    .aarch64 => extern struct {
        dev: u64,
        ino: u64,
        mode: u32,
        nlink: u32,
        uid: u32,
        gid: u32,
        rdev: u64,
        __pad1: u64,
        size: i64,
        blksize: i32,
        __pad2: i32,
        blocks: i64,
        atim: [2]i64,
        mtim: [2]i64,
        ctim: [2]i64,
        __reserved: [2]i32,
    },
    else => @compileError("no libc struct stat layout for this Linux architecture"),
};

const Error = fs.Error;
const Kind = fs.Kind;
const Info = fs.Info;

pub const max_path = c.PATH_MAX;

// Not in Zig's libc bindings for macOS: <dirent.h>, <unistd.h>, <sys/stat.h>,
// <sys/stdio.h> and <copyfile.h>.
extern "c" fn dirfd(dir: *c.DIR) c.fd_t;
extern "c" fn fchmod(fd: c.fd_t, mode: c.mode_t) c_int;
extern "c" fn fsync(fd: c.fd_t) c_int;
// Zig 0.16's std.c does not declare these for Linux; the names are libc's.
extern "c" fn fstat(fd: c.fd_t, st: *Stat) c_int;
extern "c" fn fstatat(dirfd: c.fd_t, path: [*:0]const u8, st: *Stat, flags: c_int) c_int;
extern "c" fn renameat2(olddirfd: c_int, oldpath: [*:0]const u8, newdirfd: c_int, newpath: [*:0]const u8, flags: c_uint) c_int;
extern "c" fn link(oldpath: [*:0]const u8, newpath: [*:0]const u8) c_int;
extern "c" fn readlink(path: [*:0]const u8, buf: [*]u8, len: usize) isize;
extern "c" fn symlink(target: [*:0]const u8, linkpath: [*:0]const u8) c_int;
extern "c" fn renamex_np(from: [*:0]const u8, to: [*:0]const u8, flags: c_uint) c_int;
extern "c" fn copyfile(from: [*:0]const u8, to: [*:0]const u8, state: ?*anyopaque, flags: u32) c_int;
const RENAME_EXCL: c_uint = 0x4;
const RENAME_NOREPLACE: c_uint = 1;
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

fn infoOf(st: Stat) Info {
    const kind = kindOf(st.mode);
    return .{ .kind = kind, .size = if (kind == .file) @intCast(st.size) else 0, .mode = st.mode & 0o7777 };
}

/// `dirent` carries the name length on macOS; on Linux the name is NUL
/// terminated inside `d_name`.
fn entryName(ent: anytype) []const u8 {
    if (builtin.os.tag == .linux) return std.mem.sliceTo(ent.name[0..], 0);
    return ent.name[0..ent.namlen];
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
    var st: Stat = undefined;
    if (fstatat(c.AT.FDCWD, p.ptr, &st, if (follow) 0 else c.AT.SYMLINK_NOFOLLOW) != 0) return null;
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
        var st: Stat = undefined;
        if (fstat(self.fd, &st) != 0) return lastError();
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
    const from_ptr = (try terminate(from, &from_z)).ptr;
    const to_ptr = (try terminate(to, &to_z)).ptr;
    if (builtin.os.tag == .linux) {
        if (!exclusive) {
            if (c.rename(from_ptr, to_ptr) != 0) return lastError();
            return;
        }
        if (renameat2(c.AT.FDCWD, from_ptr, c.AT.FDCWD, to_ptr, RENAME_NOREPLACE) == 0) return;
        const err = c._errno().*;
        // Kernel before 3.15 or a filesystem without the flag: the link +
        // unlink fallback keeps the same "refuse a taken name" contract for
        // files. Folders would need a non-atomic check, so they are refused.
        if (err == @intFromEnum(c.E.NOSYS) or err == @intFromEnum(c.E.INVAL)) return renameFallback(from_ptr, to_ptr);
        return lastError();
    }
    const rc = renamex_np(from_ptr, to_ptr, if (exclusive) RENAME_EXCL else 0);
    if (rc != 0) return lastError();
}

/// The old-kernel fallback: link() refuses a taken name, then unlink the old.
fn renameFallback(from: [*:0]const u8, to: [*:0]const u8) Error!void {
    if (link(from, to) != 0) return lastError();
    if (c.unlink(from) != 0) {
        _ = c.unlink(to);
        return lastError();
    }
}

pub fn copyTree(from: []const u8, to: []const u8) Error!void {
    if (builtin.os.tag != .linux) {
        var from_z: fs.Buffer = undefined;
        var to_z: fs.Buffer = undefined;
        const flags = COPYFILE_ALL | COPYFILE_RECURSIVE | COPYFILE_EXCL | COPYFILE_NOFOLLOW_SRC | COPYFILE_CLONE;
        if (copyfile((try terminate(from, &from_z)).ptr, (try terminate(to, &to_z)).ptr, null, flags) != 0)
            return lastError();
        return;
    }
    try copyEntry(from, to);
}

/// Copies one entry and everything below it; `to` must not exist. Links are
/// copied as links, never followed, like copyfile(COPYFILE_NOFOLLOW_SRC).
fn copyEntry(from: []const u8, to: []const u8) Error!void {
    const found = info(from, false) orelse return error.NotFound;
    switch (found.kind) {
        .symlink => try copySymlink(from, to),
        .file => try copyFileExclusive(from, to, found.mode),
        .directory => try copyDirectory(from, to),
        else => return error.Unexpected,
    }
}

fn copySymlink(from: []const u8, to: []const u8) Error!void {
    var from_z: fs.Buffer = undefined;
    var to_z: fs.Buffer = undefined;
    var target: fs.Buffer = undefined;
    var target_z: fs.Buffer = undefined;
    const src = (try terminate(from, &from_z)).ptr;
    const dst = (try terminate(to, &to_z)).ptr;
    const n = readlink(src, &target, target.len);
    if (n < 0) return lastError();
    const link_target = (try terminate(target[0..@intCast(n)], &target_z)).ptr;
    if (symlink(link_target, dst) != 0) return lastError();
}

fn copyFileExclusive(from: []const u8, to: []const u8, mode: u32) Error!void {
    var to_z: fs.Buffer = undefined;
    const dst = try terminate(to, &to_z);
    const in = try File.openRead(from, .{});
    defer in.close();
    const out_fd = c.open(dst.ptr, .{ .ACCMODE = .WRONLY, .CREAT = true, .EXCL = true, .CLOEXEC = true }, @as(c.mode_t, @intCast(mode & 0o777)));
    if (out_fd < 0) return lastError();
    var ok = false;
    defer if (!ok) {
        _ = c.unlink(dst.ptr);
    };
    {
        defer _ = c.close(out_fd);
        var buf: [64 * 1024]u8 = undefined;
        while (true) {
            const n = try in.read(&buf);
            if (n == 0) break;
            var at: usize = 0;
            while (at < n) {
                const w = c.write(out_fd, buf[at..].ptr, n - at);
                if (w < 0) {
                    if (c.errno(w) == .INTR) continue;
                    return lastError();
                }
                at += @intCast(w);
            }
        }
        if (fchmod(out_fd, @intCast(mode & 0o777)) != 0) return lastError();
    }
    ok = true;
}

fn copyDirectory(from: []const u8, to: []const u8) Error!void {
    try makeDirectory(to);
    var reader = try DirReader.open(from);
    defer reader.close();
    var name_buf: fs.Buffer = undefined;
    var from_child: fs.Buffer = undefined;
    var to_child: fs.Buffer = undefined;
    while (reader.next()) |entry| {
        // `entry.name` lives until the next next(); copy it before recursing.
        const name = std.fmt.bufPrint(&name_buf, "{s}", .{entry.name}) catch return error.NameTooLong;
        const src = try fs.join(&from_child, from, name);
        const dst = try fs.join(&to_child, to, name);
        try copyEntry(src, dst);
    }
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
            const name = entryName(ent);
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

    fn statAt(self: *DirReader, name: []const u8, follow: bool) ?Stat {
        var z: fs.Buffer = undefined;
        const p = terminate(name, &z) catch return null;
        var st: Stat = undefined;
        if (fstatat(self.fd, p.ptr, &st, if (follow) 0 else c.AT.SYMLINK_NOFOLLOW) != 0) return null;
        return st;
    }
};
