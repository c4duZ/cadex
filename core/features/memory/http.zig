//! A minimal HTTP/1.1 client over memory.sock: one request per connection
//! (`Connection: close`), the session token in `X-Cadex-Token`, and a
//! deadline on the whole exchange, because a hook must never hold the
//! session (200 ms for an event, 1 s for SessionStart; plan 22, phase C).

const std = @import("std");
const clock = @import("../../shared/clock.zig");
const c = std.c;

/// The engine's answers are a briefing or a short acknowledgement; more is
/// not something to hand to the agent.
const max_response = 4 * 1024 * 1024;

pub const Response = struct {
    status: u16,
    body: []u8,

    pub fn ok(self: Response) bool {
        return self.status >= 200 and self.status < 300;
    }

    pub fn deinit(self: Response, gpa: std.mem.Allocator) void {
        gpa.free(self.body);
    }
};

/// A connected socket to `path`, or null when nothing listens there.
pub fn connect(path: []const u8) ?c.fd_t {
    var address: c.sockaddr.un = .{ .family = c.AF.UNIX, .path = undefined };
    if (path.len >= address.path.len) return null;
    @memset(&address.path, 0);
    @memcpy(address.path[0..path.len], path);
    const fd = c.socket(c.AF.UNIX, c.SOCK.STREAM, 0);
    if (fd < 0) return null;
    if (c.connect(fd, @ptrCast(&address), @sizeOf(c.sockaddr.un)) != 0) {
        _ = c.close(fd);
        return null;
    }
    return fd;
}

/// Sends and receive time out at what is left until `deadline_ms`
/// (clock.monotonicMs); false when nothing is left.
fn setTimeouts(fd: c.fd_t, deadline_ms: i64) bool {
    const left = deadline_ms - clock.monotonicMs();
    if (left <= 0) return false;
    const timeout: c.timeval = .{ .sec = @intCast(@divTrunc(left, 1000)), .usec = @intCast(@mod(left, 1000) * 1000) };
    _ = c.setsockopt(fd, c.SOL.SOCKET, c.SO.RCVTIMEO, std.mem.asBytes(&timeout), @sizeOf(c.timeval));
    _ = c.setsockopt(fd, c.SOL.SOCKET, c.SO.SNDTIMEO, std.mem.asBytes(&timeout), @sizeOf(c.timeval));
    return true;
}

fn writeAll(fd: c.fd_t, data: []const u8, deadline_ms: i64) bool {
    var at: usize = 0;
    while (at < data.len) {
        if (!setTimeouts(fd, deadline_ms)) return false;
        const n = c.write(fd, data[at..].ptr, data.len - at);
        if (n <= 0) return false;
        at += @intCast(n);
    }
    return true;
}

/// The request's head. `body` goes after it as is.
pub fn head(gpa: std.mem.Allocator, method: []const u8, target: []const u8, token: []const u8, body_len: usize) ![]u8 {
    return std.fmt.allocPrint(gpa, "{s} {s} HTTP/1.1\r\nHost: localhost\r\nX-Cadex-Token: {s}\r\n" ++
        "Content-Type: application/json\r\nAccept: application/json, text/plain\r\n" ++
        "Content-Length: {d}\r\nConnection: close\r\n\r\n", .{ method, target, token, body_len });
}

/// One exchange; null when the engine is not there or the deadline passed.
pub fn send(gpa: std.mem.Allocator, socket: []const u8, method: []const u8, target: []const u8, token: []const u8, body: []const u8, deadline_ms: i64) !?Response {
    const fd = connect(socket) orelse return null;
    defer _ = c.close(fd);
    const h = try head(gpa, method, target, token, body.len);
    defer gpa.free(h);
    if (!writeAll(fd, h, deadline_ms) or !writeAll(fd, body, deadline_ms)) return null;
    var raw: std.ArrayList(u8) = .empty;
    defer raw.deinit(gpa);
    var buf: [16 * 1024]u8 = undefined;
    while (raw.items.len < max_response) {
        if (!setTimeouts(fd, deadline_ms)) return null;
        const n = c.read(fd, &buf, buf.len);
        if (n < 0) {
            if (c.errno(n) == .INTR) continue;
            return null;
        }
        if (n == 0) break;
        try raw.appendSlice(gpa, buf[0..@intCast(n)]);
    }
    return parse(gpa, raw.items) catch null;
}

/// The status and body of a whole response (the server closed after it).
pub fn parse(gpa: std.mem.Allocator, raw: []const u8) !Response {
    const end = std.mem.indexOf(u8, raw, "\r\n\r\n") orelse return error.Malformed;
    var lines = std.mem.splitSequence(u8, raw[0..end], "\r\n");
    const status_line = lines.first();
    if (!std.mem.startsWith(u8, status_line, "HTTP/1.")) return error.Malformed;
    var words = std.mem.tokenizeScalar(u8, status_line, ' ');
    _ = words.next();
    const status = std.fmt.parseInt(u16, words.next() orelse return error.Malformed, 10) catch return error.Malformed;
    var chunked = false;
    var length: ?usize = null;
    while (lines.next()) |line| {
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        const name = std.mem.trim(u8, line[0..colon], " \t");
        const value = std.mem.trim(u8, line[colon + 1 ..], " \t");
        if (std.ascii.eqlIgnoreCase(name, "transfer-encoding")) {
            chunked = std.ascii.indexOfIgnoreCase(value, "chunked") != null;
        } else if (std.ascii.eqlIgnoreCase(name, "content-length")) {
            length = std.fmt.parseInt(usize, value, 10) catch return error.Malformed;
        }
    }
    const rest = raw[end + 4 ..];
    if (chunked) return .{ .status = status, .body = try dechunk(gpa, rest) };
    if (length) |n| {
        if (rest.len < n) return error.Truncated;
        return .{ .status = status, .body = try gpa.dupe(u8, rest[0..n]) };
    }
    return .{ .status = status, .body = try gpa.dupe(u8, rest) };
}

/// The body of a chunked transfer, without its sizes, extensions or trailers.
fn dechunk(gpa: std.mem.Allocator, data: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    var rest = data;
    while (true) {
        const line_end = std.mem.indexOf(u8, rest, "\r\n") orelse return error.Truncated;
        const size_text = std.mem.trim(u8, rest[0..line_end], " \t");
        const hex = size_text[0 .. std.mem.indexOfScalar(u8, size_text, ';') orelse size_text.len];
        const size = std.fmt.parseInt(usize, std.mem.trim(u8, hex, " \t"), 16) catch return error.Malformed;
        rest = rest[line_end + 2 ..];
        if (size == 0) break;
        if (rest.len < size + 2) return error.Truncated;
        try out.appendSlice(gpa, rest[0..size]);
        rest = rest[size + 2 ..];
    }
    return out.toOwnedSlice(gpa);
}

const testing = std.testing;

test "a response with a length, chunked, or read to the close" {
    const a = try parse(testing.allocator, "HTTP/1.1 200 OK\r\ncontent-length: 5\r\ncontent-type: text/plain\r\n\r\nhello");
    defer a.deinit(testing.allocator);
    try testing.expect(a.ok());
    try testing.expectEqualStrings("hello", a.body);
    const b = try parse(testing.allocator, "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n4\r\nbrie\r\n6;x=1\r\nfing\r\n\r\n0\r\n\r\n");
    defer b.deinit(testing.allocator);
    try testing.expectEqualStrings("briefing\r\n", b.body);
    const c401 = try parse(testing.allocator, "HTTP/1.1 401 Unauthorized\r\n\r\nno");
    defer c401.deinit(testing.allocator);
    try testing.expect(!c401.ok() and c401.status == 401);
    try testing.expectEqualStrings("no", c401.body);
}

test "a cut or broken response is an error, not a body" {
    try testing.expectError(error.Truncated, parse(testing.allocator, "HTTP/1.1 200 OK\r\nContent-Length: 9\r\n\r\nshort"));
    try testing.expectError(error.Truncated, parse(testing.allocator, "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n9\r\nshort"));
    try testing.expectError(error.Malformed, parse(testing.allocator, "SSH-2.0\r\n\r\n"));
    try testing.expectError(error.Malformed, parse(testing.allocator, "no head at all"));
}

test "the head carries the token and the length; nothing listening is null at once" {
    const h = try head(testing.allocator, "POST", "/hook?event=stop", "tok", 12);
    defer testing.allocator.free(h);
    try testing.expect(std.mem.startsWith(u8, h, "POST /hook?event=stop HTTP/1.1\r\n"));
    try testing.expect(std.mem.indexOf(u8, h, "X-Cadex-Token: tok\r\n") != null);
    try testing.expect(std.mem.indexOf(u8, h, "Content-Length: 12\r\nConnection: close\r\n\r\n") != null);
    const start = clock.monotonicMs();
    try testing.expect(try send(testing.allocator, "/nonexistent/cadex/memory.sock", "GET", "/", "t", "", start + 200) == null);
    try testing.expect(clock.monotonicMs() - start < 100);
}
