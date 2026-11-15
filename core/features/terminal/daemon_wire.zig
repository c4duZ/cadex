//! The terminal daemon's protocol on terminal.sock (docs/adr/0022-terminal-daemon.md):
//! frames of [u32 length, little endian][u8 kind][payload], the length
//! counting kind and payload. Only the app connects; the daemon checks the
//! peer is the same user. The pty's master goes to the app with the "ready"
//! frame (SCM_RIGHTS): the app writes, resizes and asks the foreground
//! program on it directly, and the daemon only reads, keeps and forwards.

const std = @import("std");
const c = std.c;

/// Bumped when a frame changes; a daemon of another version refuses the
/// hello and the app starts its own (the socket name carries it too).
pub const version: u16 = 1;

pub const Kind = enum(u8) {
    // App to daemon.
    hello = 1,
    open = 2,
    attach = 3,
    list = 4,
    close = 5,
    // Daemon to app.
    hello_ok = 101,
    refused = 102,
    ready = 103,
    output = 104,
    exited = 105,
    sessions = 106,
    _,
};

/// Frames from the app stay small (an open with its paths); the daemon's
/// output goes in pieces of at most `chunk`.
pub const max_frame = 1024 * 1024;
pub const chunk = 64 * 1024;

pub const Frame = struct { kind: Kind, payload: []const u8 };

/// Appends one frame to `out`.
pub fn frame(gpa: std.mem.Allocator, out: *std.ArrayList(u8), kind: Kind, payload: []const u8) !void {
    var len: [4]u8 = undefined;
    std.mem.writeInt(u32, &len, @intCast(payload.len + 1), .little);
    try out.appendSlice(gpa, &len);
    try out.append(gpa, @intFromEnum(kind));
    try out.appendSlice(gpa, payload);
}

/// Builds a payload: integers little endian, strings with a u16 length.
pub const Payload = struct {
    bytes: std.ArrayList(u8) = .empty,
    gpa: std.mem.Allocator,

    pub fn deinit(self: *Payload) void {
        self.bytes.deinit(self.gpa);
    }
    pub fn int(self: *Payload, comptime T: type, value: T) !void {
        var buf: [@sizeOf(T)]u8 = undefined;
        std.mem.writeInt(T, &buf, value, .little);
        try self.bytes.appendSlice(self.gpa, &buf);
    }
    pub fn string(self: *Payload, s: []const u8) !void {
        try self.int(u16, @intCast(@min(s.len, std.math.maxInt(u16))));
        try self.bytes.appendSlice(self.gpa, s[0..@min(s.len, std.math.maxInt(u16))]);
    }
};

/// Reads a payload in the order it was built; error.Short past its end.
pub const Reader = struct {
    rest: []const u8,

    pub fn int(self: *Reader, comptime T: type) !T {
        if (self.rest.len < @sizeOf(T)) return error.Short;
        const value = std.mem.readInt(T, self.rest[0..@sizeOf(T)], .little);
        self.rest = self.rest[@sizeOf(T)..];
        return value;
    }
    pub fn string(self: *Reader) ![]const u8 {
        const len = try self.int(u16);
        if (self.rest.len < len) return error.Short;
        const s = self.rest[0..len];
        self.rest = self.rest[len..];
        return s;
    }
};

/// Bytes read from a socket, cut into frames as they complete.
pub const Inbox = struct {
    bytes: std.ArrayList(u8) = .empty,
    /// Where the next frame starts; compacted before each read.
    start: usize = 0,

    pub fn deinit(self: *Inbox, gpa: std.mem.Allocator) void {
        self.bytes.deinit(gpa);
    }

    /// The next whole frame, valid until the next fill; error.TooBig for a
    /// length no frame of this protocol has.
    pub fn next(self: *Inbox) !?Frame {
        const have = self.bytes.items[self.start..];
        if (have.len < 5) return null;
        const len = std.mem.readInt(u32, have[0..4], .little);
        if (len == 0 or len > max_frame) return error.TooBig;
        if (have.len < 4 + len) return null;
        self.start += 4 + len;
        return .{ .kind = @enumFromInt(have[4]), .payload = have[5 .. 4 + len] };
    }

    /// Room to read into, after dropping the frames already taken.
    pub fn room(self: *Inbox, gpa: std.mem.Allocator, want: usize) ![]u8 {
        if (self.start > 0) {
            const left = self.bytes.items.len - self.start;
            std.mem.copyForwards(u8, self.bytes.items[0..left], self.bytes.items[self.start..]);
            self.bytes.shrinkRetainingCapacity(left);
            self.start = 0;
        }
        try self.bytes.ensureUnusedCapacity(gpa, want);
        return self.bytes.unusedCapacitySlice();
    }

    pub fn filled(self: *Inbox, n: usize) void {
        self.bytes.items.len += n;
    }
};

// Sockets and descriptor passing, with the Mac's values (<sys/socket.h>):
// Zig's std does not define SCM_RIGHTS nor getpeereid for macOS.
const SOL_SOCKET: c_int = 0xffff;
const SCM_RIGHTS: c_int = 1;
const SO_NOSIGPIPE: c_int = 0x1022;
const Iovec = extern struct { base: ?*anyopaque, len: usize };
const Msghdr = extern struct {
    name: ?*anyopaque = null,
    namelen: u32 = 0,
    iov: *Iovec,
    iovlen: c_int,
    control: ?*anyopaque,
    controllen: u32,
    flags: c_int = 0,
};
const Cmsghdr = extern struct { len: u32, level: c_int, type: c_int };
/// CMSG_SPACE(sizeof(int)) on the Mac: a 12-byte header and the fd, 4-aligned.
const control_size = 16;
extern "c" fn sendmsg(fd: c_int, msg: *const Msghdr, flags: c_int) isize;
extern "c" fn recvmsg(fd: c_int, msg: *Msghdr, flags: c_int) isize;
extern "c" fn getpeereid(fd: c_int, uid: *c.uid_t, gid: *c.gid_t) c_int;
extern "c" fn fcntl(fd: c_int, cmd: c_int, ...) c_int;

pub fn address(path: []const u8) !c.sockaddr.un {
    var addr: c.sockaddr.un = .{ .family = c.AF.UNIX, .path = undefined };
    if (path.len >= addr.path.len) return error.PathTooLong;
    @memset(&addr.path, 0);
    @memcpy(addr.path[0..path.len], path);
    return addr;
}

/// A connected stream socket to `path`, or null when nobody listens.
pub fn connect(path: []const u8) ?c_int {
    var addr = address(path) catch return null;
    const fd = c.socket(c.AF.UNIX, c.SOCK.STREAM, 0);
    if (fd < 0) return null;
    noSigpipe(fd);
    if (c.connect(fd, @ptrCast(&addr), @sizeOf(c.sockaddr.un)) != 0) {
        _ = c.close(fd);
        return null;
    }
    return fd;
}

/// A write to a closed peer gives EPIPE instead of killing the process.
pub fn noSigpipe(fd: c_int) void {
    const on: c_int = 1;
    _ = c.setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, std.mem.asBytes(&on), @sizeOf(c_int));
}

pub fn setNonblocking(fd: c_int) void {
    const flags = fcntl(fd, c.F.GETFL);
    _ = fcntl(fd, c.F.SETFL, flags | @as(c_int, @bitCast(c.O{ .NONBLOCK = true })));
}

pub fn setCloexec(fd: c_int) void {
    _ = fcntl(fd, c.F.SETFD, @as(c_int, c.FD_CLOEXEC));
}

/// True when the other end of `fd` runs as this process's user.
pub fn sameUser(fd: c_int) bool {
    var uid: c.uid_t = undefined;
    var gid: c.gid_t = undefined;
    return getpeereid(fd, &uid, &gid) == 0 and uid == c.getuid();
}

/// Sends `bytes` with `pass` attached; the whole frame or an error.
pub fn sendWithFd(sock: c_int, bytes: []const u8, pass: c_int) !void {
    var control: [control_size]u8 align(4) = @splat(0);
    const header: *Cmsghdr = @ptrCast(&control);
    header.* = .{ .len = 12 + 4, .level = SOL_SOCKET, .type = SCM_RIGHTS };
    std.mem.writeInt(c_int, control[12..16], pass, .little);
    var iov: Iovec = .{ .base = @constCast(bytes.ptr), .len = bytes.len };
    const msg: Msghdr = .{ .iov = &iov, .iovlen = 1, .control = &control, .controllen = control_size };
    const n = sendmsg(sock, &msg, 0);
    if (n < 0) return error.SendFailed;
    if (@as(usize, @intCast(n)) < bytes.len) try writeAll(sock, bytes[@intCast(n)..]);
}

/// Reads into `buf`; a descriptor that came along lands in `fd_out`.
/// 0 is the end of the stream; null is "try again" on a nonblocking socket.
pub fn receive(sock: c_int, buf: []u8, fd_out: *?c_int) !?usize {
    var control: [control_size]u8 align(4) = @splat(0);
    var iov: Iovec = .{ .base = buf.ptr, .len = buf.len };
    var msg: Msghdr = .{ .iov = &iov, .iovlen = 1, .control = &control, .controllen = control_size };
    const n = recvmsg(sock, &msg, 0);
    if (n < 0) return switch (c.errno(n)) {
        .AGAIN, .INTR => null,
        else => error.ReadFailed,
    };
    const header: *const Cmsghdr = @ptrCast(&control);
    if (msg.controllen >= 16 and header.level == SOL_SOCKET and header.type == SCM_RIGHTS) {
        const got = std.mem.readInt(c_int, control[12..16], .little);
        setCloexec(got);
        if (fd_out.*) |old| _ = c.close(old);
        fd_out.* = got;
    }
    return @intCast(n);
}

/// All of `bytes`, waiting up to a second at a time on a full nonblocking socket.
pub fn writeAll(fd: c_int, bytes: []const u8) !void {
    var rest = bytes;
    while (rest.len > 0) {
        const n = c.write(fd, rest.ptr, rest.len);
        if (n < 0) switch (c.errno(n)) {
            .INTR => continue,
            .AGAIN => {
                if (!waitWritable(fd, 1000)) return error.WriteFailed;
                continue;
            },
            else => return error.WriteFailed,
        };
        rest = rest[@intCast(n)..];
    }
}

/// True when `fd` can take more bytes within `ms`.
pub fn waitWritable(fd: c_int, ms: i32) bool {
    var fds = [_]c.pollfd{.{ .fd = fd, .events = c.POLL.OUT, .revents = 0 }};
    return c.poll(&fds, 1, ms) > 0 and fds[0].revents & c.POLL.OUT != 0;
}

test "frames come out whole, also when they arrive in pieces" {
    const gpa = std.testing.allocator;
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(gpa);
    var p: Payload = .{ .gpa = gpa };
    defer p.deinit();
    try p.int(u16, 7);
    try p.string("abc");
    try frame(gpa, &out, .open, p.bytes.items);
    try frame(gpa, &out, .list, "");
    var inbox: Inbox = .{};
    defer inbox.deinit(gpa);
    for (out.items, 0..) |byte, i| {
        (try inbox.room(gpa, 1))[0] = byte;
        inbox.filled(1);
        if (i < 9) try std.testing.expect(try inbox.next() == null);
    }
    const first = (try inbox.next()).?;
    try std.testing.expectEqual(Kind.open, first.kind);
    var r: Reader = .{ .rest = first.payload };
    try std.testing.expectEqual(@as(u16, 7), try r.int(u16));
    try std.testing.expectEqualStrings("abc", try r.string());
    try std.testing.expectError(error.Short, r.int(u8));
    try std.testing.expectEqual(Kind.list, (try inbox.next()).?.kind);
}
