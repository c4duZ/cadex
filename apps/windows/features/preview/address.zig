//! The address rules of the preview (docs/spec/preview.md), the Mac's
//! (apps/macos/features/preview/PreviewDocument.swift): without a scheme,
//! http:// for local servers and https:// for the rest; only http and https
//! load; the same address opens the same tab.

const std = @import("std");

/// The address to load for what was typed, or null when it is not a web
/// address (file:, javascript:, empty). Owned by `gpa`.
pub fn normalize(gpa: std.mem.Allocator, typed: []const u8) !?[]u8 {
    const trimmed = std.mem.trim(u8, typed, " \t\r\n");
    if (trimmed.len == 0) return null;
    const full = if (std.mem.indexOf(u8, trimmed, "://") != null)
        try gpa.dupe(u8, trimmed)
    else
        try std.mem.concat(gpa, u8, &.{ if (isLocal(trimmed)) "http://" else "https://", trimmed });
    if (!valid(full)) {
        gpa.free(full);
        return null;
    }
    return full;
}

/// http or https, a host, digits after the host's colon, nothing blank.
fn valid(url: []const u8) bool {
    for (url) |b| if (b <= ' ' or b == 0x7f) return false;
    const sep = std.mem.indexOf(u8, url, "://") orelse return false;
    const scheme = url[0..sep];
    if (!std.ascii.eqlIgnoreCase(scheme, "http") and !std.ascii.eqlIgnoreCase(scheme, "https")) return false;
    const authority = authorityOf(url[sep + 3 ..]);
    const host_port = if (std.mem.lastIndexOfScalar(u8, authority, '@')) |at| authority[at + 1 ..] else authority;
    if (host_port.len == 0) return false;
    if (host_port[0] == '[') {
        const close = std.mem.indexOfScalar(u8, host_port, ']') orelse return false;
        return portOk(host_port[close + 1 ..]);
    }
    const colon = std.mem.indexOfScalar(u8, host_port, ':') orelse return true;
    if (colon == 0) return false;
    return portOk(host_port[colon..]);
}

fn portOk(rest: []const u8) bool {
    if (rest.len == 0) return true;
    if (rest[0] != ':') return false;
    for (rest[1..]) |b| if (!std.ascii.isDigit(b)) return false;
    return true;
}

fn authorityOf(after_scheme: []const u8) []const u8 {
    const end = std.mem.indexOfAny(u8, after_scheme, "/?#") orelse after_scheme.len;
    return after_scheme[0..end];
}

/// The host of "localhost:3000/x" or "http://[::1]:8080", lowercase in `buf`.
fn hostOf(buf: []u8, address: []const u8) []const u8 {
    const start = if (std.mem.indexOf(u8, address, "://")) |s| s + 3 else 0;
    var authority = authorityOf(address[start..]);
    if (std.mem.lastIndexOfScalar(u8, authority, '@')) |at| authority = authority[at + 1 ..];
    var host = authority;
    if (host.len > 0 and host[0] == '[') {
        const close = std.mem.indexOfScalar(u8, host, ']') orelse host.len;
        host = host[1..close];
    } else if (std.mem.indexOfScalar(u8, host, ':')) |colon| {
        host = host[0..colon];
    }
    const n = @min(host.len, buf.len);
    return std.ascii.lowerString(buf[0..n], host[0..n]);
}

/// localhost, 127.x, 0.0.0.0, [::1], *.local and private IPs: dev servers,
/// which rarely speak https. "bkdg.center" went out as http and the
/// system refused it (owner, 2026-10-19, on the Mac).
pub fn isLocal(address: []const u8) bool {
    var buf: [256]u8 = undefined;
    const host = hostOf(&buf, address);
    for ([_][]const u8{ "localhost", "0.0.0.0", "::1" }) |h| if (std.mem.eql(u8, host, h)) return true;
    if (std.mem.endsWith(u8, host, ".local")) return true;
    for ([_][]const u8{ "127.", "10.", "192.168." }) |p| if (std.mem.startsWith(u8, host, p)) return true;
    return false;
}

/// "localhost:5173" for the tab of a page with no title yet, as the Mac
/// shows host and port; "Preview" with no address.
pub fn fallbackTitle(buf: []u8, url: []const u8) []const u8 {
    if (url.len == 0) return "Preview";
    const sep = std.mem.indexOf(u8, url, "://") orelse return "Preview";
    const authority = authorityOf(url[sep + 3 ..]);
    var host_buf: [256]u8 = undefined;
    const host = hostOf(&host_buf, url);
    if (host.len == 0) return "Preview";
    const https = std.ascii.eqlIgnoreCase(url[0..sep], "https");
    const port = portOf(authority) orelse (if (https) "443" else "80");
    return std.fmt.bufPrint(buf, "{s}:{s}", .{ host, port }) catch "Preview";
}

fn portOf(authority: []const u8) ?[]const u8 {
    const after = if (std.mem.lastIndexOfScalar(u8, authority, ']')) |close| authority[close + 1 ..] else authority;
    const colon = std.mem.lastIndexOfScalar(u8, after, ':') orelse return null;
    const port = after[colon + 1 ..];
    return if (port.len > 0) port else null;
}

var blank_count: u32 = 0;

/// What makes two previews the same tab: the address; blank previews never
/// match each other (each is a new tab).
pub fn identity(gpa: std.mem.Allocator, url: []const u8) ![]u8 {
    if (url.len > 0) return std.mem.concat(gpa, u8, &.{ "preview:", url });
    blank_count += 1;
    return std.fmt.allocPrint(gpa, "preview:blank-{d}", .{blank_count});
}

const testing = std.testing;

fn expectNormalized(typed: []const u8, want: ?[]const u8) !void {
    const got = try normalize(testing.allocator, typed);
    defer if (got) |g| testing.allocator.free(g);
    if (want) |wanted| {
        try testing.expect(got != null);
        try testing.expectEqualStrings(wanted, got.?);
    } else try testing.expect(got == null);
}

test "addresses: http for local servers, https for the rest, only web schemes" {
    try expectNormalized("localhost:5173", "http://localhost:5173");
    try expectNormalized("127.0.0.1:8000/x", "http://127.0.0.1:8000/x");
    try expectNormalized("bkdg.center", "https://bkdg.center");
    try expectNormalized("http://bkdg.center", "http://bkdg.center");
    try expectNormalized(" https://example.com/x ", "https://example.com/x");
    try expectNormalized("[::1]:8080", "http://[::1]:8080");
    try expectNormalized("file:///etc/hosts", null);
    try expectNormalized("javascript:alert(1)", null);
    try expectNormalized("", null);
    try expectNormalized("a b.com", null);
}

test "local hosts" {
    try testing.expect(isLocal("0.0.0.0:3000"));
    try testing.expect(isLocal("mac.local"));
    try testing.expect(isLocal("192.168.0.10:80"));
    try testing.expect(!isLocal("example.com"));
    try testing.expect(!isLocal("10x.com"));
}

test "the same server opens the same tab; blank tabs are each new" {
    const a = try identity(testing.allocator, "http://localhost:8000/");
    defer testing.allocator.free(a);
    const b = try identity(testing.allocator, "http://localhost:8000/");
    defer testing.allocator.free(b);
    try testing.expectEqualStrings(a, b);
    const x = try identity(testing.allocator, "");
    defer testing.allocator.free(x);
    const y = try identity(testing.allocator, "");
    defer testing.allocator.free(y);
    try testing.expect(!std.mem.eql(u8, x, y));
}

test "a page without a title shows host and port" {
    var buf: [64]u8 = undefined;
    try testing.expectEqualStrings("localhost:5173", fallbackTitle(&buf, "http://localhost:5173/app"));
    try testing.expectEqualStrings("example.com:443", fallbackTitle(&buf, "https://example.com"));
    try testing.expectEqualStrings("Preview", fallbackTitle(&buf, ""));
}

test {
    @import("win32").refAllDeep(@This());
}
