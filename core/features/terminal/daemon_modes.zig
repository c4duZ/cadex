//! The modes a program set, read from its raw output, for the daemon's
//! replay (docs/adr/0022-terminal-daemon.md). The ring keeps only the last
//! output: a TUI that switched to the alternate screen, bracketed paste or
//! the kitty keyboard long ago may have lost those bytes, and the app's model
//! would type and draw as if they were off. The daemon keeps the modes of the
//! whole output and, on attach, adds after the replay what the replay alone
//! would leave different. No model, no libghostty: a small scanner of
//! `CSI ? Pm h/l` and of the kitty keyboard's `CSI > / < / = … u`.

const std = @import("std");

const max_modes = 48;
const max_kitty = 16;
const max_params = 32;

const Mode = struct { number: u16, set: bool };

pub const Modes = struct {
    modes: [max_modes]Mode = undefined,
    count: usize = 0,
    kitty: [max_kitty]u32 = undefined,
    kitty_len: usize = 0,
    // Scanner state, kept across chunks.
    state: enum { ground, esc, csi, string, string_esc } = .ground,
    marker: u8 = 0,
    params: [max_params]u8 = undefined,
    params_len: usize = 0,
    ignore: bool = false,

    pub fn feed(self: *Modes, data: []const u8) void {
        for (data) |byte| self.step(byte);
    }

    fn step(self: *Modes, b: u8) void {
        switch (self.state) {
            .ground => if (b == 0x1b) {
                self.state = .esc;
            },
            .esc => switch (b) {
                '[' => {
                    self.state = .csi;
                    self.marker = 0;
                    self.params_len = 0;
                    self.ignore = false;
                },
                ']', 'P', '_', '^', 'X' => self.state = .string,
                0x1b => {},
                else => self.state = .ground,
            },
            .csi => self.csiByte(b),
            .string => switch (b) {
                0x07 => self.state = .ground,
                0x1b => self.state = .string_esc,
                else => {},
            },
            .string_esc => self.state = if (b == '\\') .ground else .string,
        }
    }

    fn csiByte(self: *Modes, b: u8) void {
        if (b == 0x1b) return {
            self.state = .esc;
        };
        if (b >= 0x40 and b <= 0x7e) {
            self.state = .ground;
            if (!self.ignore) self.finish(b);
            return;
        }
        if (self.params_len == 0 and self.marker == 0 and (b == '?' or b == '>' or b == '<' or b == '=')) {
            self.marker = b;
        } else if ((b >= '0' and b <= '9') or b == ';') {
            if (self.params_len < max_params) {
                self.params[self.params_len] = b;
                self.params_len += 1;
            } else self.ignore = true;
        } else self.ignore = true;
    }

    fn finish(self: *Modes, final: u8) void {
        const params = self.params[0..self.params_len];
        if (self.marker == '?' and (final == 'h' or final == 'l')) {
            var it = std.mem.splitScalar(u8, params, ';');
            while (it.next()) |p| {
                const n = std.fmt.parseInt(u16, p, 10) catch continue;
                self.setMode(n, final == 'h');
            }
        } else if (final == 'u') switch (self.marker) {
            '>' => self.kittyPush(firstParam(params, 0)),
            '<' => self.kittyPop(firstParam(params, 1)),
            '=' => self.kittySet(params),
            else => {},
        };
    }

    fn setMode(self: *Modes, number: u16, set: bool) void {
        for (self.modes[0..self.count]) |*m| if (m.number == number) {
            m.set = set;
            return;
        };
        if (self.count == max_modes) return;
        self.modes[self.count] = .{ .number = number, .set = set };
        self.count += 1;
    }

    fn kittyPush(self: *Modes, flags: u32) void {
        if (self.kitty_len == max_kitty) {
            std.mem.copyForwards(u32, self.kitty[0 .. max_kitty - 1], self.kitty[1..]);
            self.kitty_len -= 1;
        }
        self.kitty[self.kitty_len] = flags;
        self.kitty_len += 1;
    }

    fn kittyPop(self: *Modes, count: u32) void {
        self.kitty_len -|= @min(count, max_kitty);
    }

    /// `CSI = flags ; how u`: 1 sets, 2 adds, 3 takes away, on the top entry.
    fn kittySet(self: *Modes, params: []const u8) void {
        var it = std.mem.splitScalar(u8, params, ';');
        const flags = std.fmt.parseInt(u32, it.next() orelse "0", 10) catch 0;
        const how = std.fmt.parseInt(u32, it.next() orelse "1", 10) catch 1;
        if (self.kitty_len == 0) self.kittyPush(0);
        const top = &self.kitty[self.kitty_len - 1];
        top.* = switch (how) {
            2 => top.* | flags,
            3 => top.* & ~flags,
            else => flags,
        };
    }

    pub fn mode(self: *const Modes, number: u16) ?bool {
        for (self.modes[0..self.count]) |m| if (m.number == number) return m.set;
        return null;
    }

    /// What to send after the replay so the app ends with these modes, when
    /// the replay alone (`replayed`, the modes of the ring's bytes) left
    /// other ones. Modes the replay never touched count as their default.
    pub fn suffix(self: *const Modes, replayed: *const Modes, out: *std.ArrayList(u8), gpa: std.mem.Allocator) !void {
        for (self.modes[0..self.count]) |m| {
            const before = replayed.mode(m.number) orelse defaultOn(m.number);
            if (before == m.set) continue;
            try out.print(gpa, "\x1b[?{d}{c}", .{ m.number, @as(u8, if (m.set) 'h' else 'l') });
        }
        const live = self.kitty[0..self.kitty_len];
        if (!std.mem.eql(u32, live, replayed.kitty[0..replayed.kitty_len])) {
            try out.print(gpa, "\x1b[<{d}u", .{max_kitty});
            for (live) |flags| try out.print(gpa, "\x1b[>{d}u", .{flags});
        }
    }
};

/// DEC modes on when a terminal starts: autowrap (7) and the cursor (25).
fn defaultOn(number: u16) bool {
    return number == 7 or number == 25;
}

fn firstParam(params: []const u8, default: u32) u32 {
    const end = std.mem.indexOfScalar(u8, params, ';') orelse params.len;
    if (end == 0) return default;
    return std.fmt.parseInt(u32, params[0..end], 10) catch default;
}

const testing = std.testing;

fn suffixOf(live: []const u8, ring: []const u8) ![]u8 {
    var a: Modes = .{};
    a.feed(live);
    var r: Modes = .{};
    r.feed(ring);
    var out: std.ArrayList(u8) = .empty;
    try a.suffix(&r, &out, testing.allocator);
    return out.toOwnedSlice(testing.allocator);
}

test "modes lost from the ring come back after the replay" {
    // top entered the alternate screen and bracketed paste long ago; the ring
    // kept only its last redraw.
    const s = try suffixOf("\x1b[?1049h\x1b[?2004h\x1b[?25lframe", "frame");
    defer testing.allocator.free(s);
    try testing.expectEqualStrings("\x1b[?1049h\x1b[?2004h\x1b[?25l", s);
}

test "modes the ring still has add nothing, split across chunks too" {
    var live: Modes = .{};
    live.feed("\x1b[?10");
    live.feed("49h x \x1b]0;title \x1b[?1l\x07");
    try testing.expectEqual(true, live.mode(1049).?);
    // The CSI inside the OSC title is text, not a mode.
    try testing.expectEqual(@as(?bool, null), live.mode(1));
    const s = try suffixOf("\x1b[?1049h\x1b[?1049l", "\x1b[?1049h\x1b[?1049l");
    defer testing.allocator.free(s);
    try testing.expectEqualStrings("", s);
}

test "the kitty keyboard's stack is rebuilt when the ring lost it" {
    const s = try suffixOf("\x1b[>1u\x1b[>3u\x1b[=1;2u", "");
    defer testing.allocator.free(s);
    try testing.expectEqualStrings("\x1b[<16u\x1b[>1u\x1b[>3u", s);
    const none = try suffixOf("\x1b[>1u\x1b[<u", "");
    defer testing.allocator.free(none);
    try testing.expectEqualStrings("", none);
}
