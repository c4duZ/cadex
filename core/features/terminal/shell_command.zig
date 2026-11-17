//! The command the shell runs in a terminal, from its semantic prompt marks (OSC 133, which
//! libghostty-vt parses: `C;cmdline_url=` when a command starts, `D;<exit>` when it ends; Cadex's
//! zsh integration sends them, plan 29's review against the mockups). The app shows it: the tab's
//! name ("npm run dev"), the pane's header with "running 38 s", and the last result ("make check
//! passed"). No time here: the app stamps each change when it is told. No libghostty here.

const std = @import("std");

pub const max_text = 512;

pub const ShellCommand = struct {
    /// A command runs now (started, not ended).
    running: bool = false,
    /// Each start and end adds one, so the app sees a change even with the same text.
    seq: u32 = 0,
    text: [max_text]u8 = undefined,
    text_len: usize = 0,
    /// The last command that ended, and its exit code when the shell said it.
    last: [max_text]u8 = undefined,
    last_len: usize = 0,
    last_exit: ?i32 = null,

    pub fn current(self: *const ShellCommand) []const u8 {
        return self.text[0..self.text_len];
    }

    pub fn previous(self: *const ShellCommand) []const u8 {
        return self.last[0..self.last_len];
    }

    /// A command started: its line (cut on a character, at most max_text bytes).
    pub fn start(self: *ShellCommand, line: []const u8) void {
        self.text_len = cut(&self.text, line);
        self.running = true;
        self.seq +%= 1;
    }

    /// The command ended: it becomes the last one, with its exit code.
    pub fn end(self: *ShellCommand, exit_code: ?i32) void {
        if (!self.running) return;
        @memcpy(self.last[0..self.text_len], self.text[0..self.text_len]);
        self.last_len = self.text_len;
        self.last_exit = exit_code;
        self.running = false;
        self.seq +%= 1;
    }

    fn cut(buf: *[max_text]u8, line: []const u8) usize {
        var n = @min(line.len, buf.len);
        // Back off a cut inside a multibyte character.
        while (n > 0 and n < line.len and (line[n] & 0xC0) == 0x80) n -= 1;
        @memcpy(buf[0..n], line[0..n]);
        return n;
    }
};

test "a command starts and ends; the last one keeps its exit code" {
    var c: ShellCommand = .{};
    try std.testing.expect(!c.running);
    c.start("make macos-test");
    try std.testing.expect(c.running);
    try std.testing.expectEqualStrings("make macos-test", c.current());
    c.end(2);
    try std.testing.expect(!c.running);
    try std.testing.expectEqualStrings("make macos-test", c.previous());
    try std.testing.expectEqual(@as(?i32, 2), c.last_exit);
    try std.testing.expectEqual(@as(u32, 2), c.seq);
    // An end with nothing running (a prompt drawn again) changes nothing.
    c.end(0);
    try std.testing.expectEqual(@as(u32, 2), c.seq);
}

test "a long line is cut on a character" {
    var c: ShellCommand = .{};
    var long: [max_text + 10]u8 = undefined;
    @memset(&long, 'a');
    // "é" (two bytes) right on the limit.
    long[max_text - 1] = 0xC3;
    long[max_text] = 0xA9;
    c.start(&long);
    try std.testing.expectEqual(@as(usize, max_text - 1), c.current().len);
}
