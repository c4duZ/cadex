//! Spots the addresses of local servers in a terminal's output
//! (docs/spec/preview.md): `http://localhost:5173`, `127.0.0.1:8000`,
//! `0.0.0.0:3000`, `[::1]:8080`, with or without `http://`. Each address is
//! reported once per session; the app offers to open it in the preview.

const std = @import("std");

const hosts = [_][]const u8{ "localhost:", "127.0.0.1:", "0.0.0.0:", "[::1]:" };
/// Longest address kept; also how much of the previous read is carried
/// over, so an address split between two reads is still found.
pub const max_url = 200;

pub const Detector = struct {
    gpa: std.mem.Allocator,
    seen: std.StringHashMapUnmanaged(void) = .empty,
    /// The end of the previous read.
    carry: [max_url]u8 = undefined,
    carry_len: usize = 0,

    pub fn deinit(self: *Detector) void {
        var it = self.seen.keyIterator();
        while (it.next()) |k| self.gpa.free(k.*);
        self.seen.deinit(self.gpa);
    }

    /// Scans a read of output; calls `report` with each new address,
    /// normalized to http://host:port/path (0.0.0.0 becomes localhost).
    pub fn scan(self: *Detector, bytes: []const u8, context: anytype, comptime report: fn (@TypeOf(context), []const u8) void) void {
        var window: [max_url * 2]u8 = undefined;
        var at: usize = 0;
        while (at < bytes.len) {
            // The end of the previous read + the next piece, without escape
            // sequences: Vite colors the port in the middle of the address.
            const take = @min(bytes.len - at, window.len - self.carry_len);
            @memcpy(window[0..self.carry_len], self.carry[0..self.carry_len]);
            const raw = bytes[at..][0..take];
            const text = window[0 .. self.carry_len + stripEscapes(raw, window[self.carry_len..])];
            self.scanText(text, context, report);
            const keep = @min(text.len, max_url);
            std.mem.copyForwards(u8, self.carry[0..keep], text[text.len - keep ..]);
            self.carry_len = keep;
            at += take;
        }
    }

    /// The carried part is scanned again; `seen` drops the repeats. An
    /// address touching the end of the text may go on in the next read.
    fn scanText(self: *Detector, text: []const u8, context: anytype, comptime report: fn (@TypeOf(context), []const u8) void) void {
        for (hosts) |host| {
            var from: usize = 0;
            while (std.mem.indexOfPos(u8, text, from, host)) |start| {
                from = start + host.len;
                const parsed = parse(text, start, host) orelse continue;
                if (parsed.end == text.len) continue;
                var buf: [max_url + 32]u8 = undefined;
                const url = normalized(&buf, host, parsed) orelse continue;
                if (self.seen.contains(url)) continue;
                const copy = self.gpa.dupe(u8, url) catch return;
                self.seen.put(self.gpa, copy, {}) catch {
                    self.gpa.free(copy);
                    return;
                };
                report(context, url);
            }
        }
    }
};

/// Copies `raw` into `out` without ESC sequences (CSI, OSC, two-byte).
/// Returns the length written.
fn stripEscapes(raw: []const u8, out: []u8) usize {
    var n: usize = 0;
    var i: usize = 0;
    while (i < raw.len and n < out.len) {
        if (raw[i] != 0x1b) {
            out[n] = raw[i];
            n += 1;
            i += 1;
            continue;
        }
        i += 1;
        if (i >= raw.len) break;
        switch (raw[i]) {
            '[' => {
                i += 1;
                while (i < raw.len and !(raw[i] >= 0x40 and raw[i] <= 0x7e)) i += 1;
                i += 1;
            },
            ']' => {
                while (i < raw.len and raw[i] != 0x07 and !(raw[i] == 0x1b and i + 1 < raw.len and raw[i + 1] == '\\')) i += 1;
                i += if (i < raw.len and raw[i] == 0x07) 1 else 2;
            },
            else => i += 1,
        }
    }
    return n;
}

const Parsed = struct { port: []const u8, path: []const u8, end: usize };

fn parse(text: []const u8, start: usize, host: []const u8) ?Parsed {
    // A longer host name ending in "localhost" (mylocalhost:1) is not local.
    if (start > 0 and (std.ascii.isAlphanumeric(text[start - 1]) or text[start - 1] == '.' or text[start - 1] == '-')) return null;
    var i = start + host.len;
    const port_start = i;
    while (i < text.len and std.ascii.isDigit(text[i]) and i - port_start < 5) i += 1;
    const port = text[port_start..i];
    if (port.len == 0 or (std.fmt.parseInt(u32, port, 10) catch return null) > 65535) return null;
    if (i < text.len and std.ascii.isDigit(text[i])) return null;
    const path_start = i;
    if (i < text.len and text[i] == '/') {
        while (i < text.len and i - path_start < max_url and isPathChar(text[i])) i += 1;
    }
    // Sentence punctuation after an address is not part of it.
    var path_end = i;
    while (path_end > path_start and std.mem.indexOfScalar(u8, ".,;:)", text[path_end - 1]) != null) path_end -= 1;
    return .{ .port = port, .path = text[path_start..path_end], .end = i };
}

fn isPathChar(ch: u8) bool {
    return std.ascii.isAlphanumeric(ch) or std.mem.indexOfScalar(u8, "/-._~%?=&#+:@!$,;()", ch) != null;
}

fn normalized(buf: []u8, host: []const u8, p: Parsed) ?[]const u8 {
    const name = if (std.mem.eql(u8, host, "0.0.0.0:")) "localhost" else host[0 .. host.len - 1];
    return std.fmt.bufPrint(buf, "http://{s}:{s}{s}", .{ name, p.port, if (p.path.len == 0) "/" else p.path }) catch null;
}

const testing = std.testing;

const Found = struct {
    list: std.ArrayList([]u8) = .empty,
    fn add(self: *Found, url: []const u8) void {
        self.list.append(testing.allocator, testing.allocator.dupe(u8, url) catch return) catch {};
    }
    fn deinit(self: *Found) void {
        for (self.list.items) |u| testing.allocator.free(u);
        self.list.deinit(testing.allocator);
    }
};

test "finds local addresses in server output, once each" {
    var d: Detector = .{ .gpa = testing.allocator };
    defer d.deinit();
    var found: Found = .{};
    defer found.deinit();
    d.scan("  VITE ready\n  ➜  Local:   \x1b[36mhttp://localhost:\x1b[1m5173\x1b[22m/\x1b[39m\n", &found, Found.add);
    d.scan("Serving HTTP on 0.0.0.0 port 8000 (http://0.0.0.0:8000/) ...\n", &found, Found.add);
    d.scan("listening on 127.0.0.1:3000.\nagain http://localhost:8000/\n", &found, Found.add);
    d.scan("[::1]:8080/app?x=1 and https://example.com:443 and mylocalhost:9\n", &found, Found.add);
    const want = [_][]const u8{ "http://localhost:5173/", "http://localhost:8000/", "http://127.0.0.1:3000/", "http://[::1]:8080/app?x=1" };
    try testing.expectEqual(want.len, found.list.items.len);
    for (want, found.list.items) |w, got| try testing.expectEqualStrings(w, got);
}

test "an address split between two reads is found" {
    var d: Detector = .{ .gpa = testing.allocator };
    defer d.deinit();
    var found: Found = .{};
    defer found.deinit();
    d.scan("ready at http://local", &found, Found.add);
    d.scan("host:4321/docs\n", &found, Found.add);
    try testing.expectEqual(@as(usize, 1), found.list.items.len);
    try testing.expectEqualStrings("http://localhost:4321/docs", found.list.items[0]);
}
