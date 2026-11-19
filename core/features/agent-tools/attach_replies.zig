//! What the phone's terminal answers by itself (plan 39 B): a program asks
//! the terminal things (the device attributes, the colors, the cursor's
//! place, the keyboard protocol) and the app's terminal answers already. The
//! guest's terminal answers too, from the replay or the live output, and
//! those answers would reach the program as typing (junk in the prompt).
//! They are dropped here; keys never look like them.

const std = @import("std");

const esc = 0x1b;
const bel = 0x07;

/// `input` without the terminal's answers, into `out` (at least as long).
pub fn strip(input: []const u8, out: []u8) []const u8 {
    var n: usize = 0;
    var i: usize = 0;
    while (i < input.len) {
        const len = replyLength(input[i..]);
        if (len > 0) {
            i += len;
            continue;
        }
        out[n] = input[i];
        n += 1;
        i += 1;
    }
    return out[0..n];
}

/// The length of the answer at the start of `s`, 0 when it is not one.
fn replyLength(s: []const u8) usize {
    if (s.len < 3 or s[0] != esc) return 0;
    return switch (s[1]) {
        '[' => csiReply(s),
        // OSC (colors: 10, 11, 4…) and DCS (XTVERSION, DECRQSS) answers.
        ']', 'P' => stringEnd(s),
        else => 0,
    };
}

/// CSI answers: device attributes (`?…c`, `>…c`), the cursor's place
/// (`row;colR`), the keyboard protocol (`?flagsu`) and modes (`?…$y`).
fn csiReply(s: []const u8) usize {
    var i: usize = 2;
    const private = s[i] == '?' or s[i] == '>';
    if (private) i += 1;
    while (i < s.len and (std.ascii.isDigit(s[i]) or s[i] == ';')) : (i += 1) {}
    if (i >= s.len) return 0;
    const final = s[i];
    if (final == 'c' and private) return i + 1;
    if (final == 'u' and s[2] == '?') return i + 1;
    if (final == 'R' and !private and std.mem.indexOfScalar(u8, s[2..i], ';') != null) return i + 1;
    if (final == '$' and i + 1 < s.len and s[i + 1] == 'y') return i + 2;
    return 0;
}

/// Up to BEL or ESC \ (whole, in this read), 0 when it does not end.
fn stringEnd(s: []const u8) usize {
    var i: usize = 2;
    while (i < s.len) : (i += 1) {
        if (s[i] == bel) return i + 1;
        if (s[i] == esc and i + 1 < s.len and s[i + 1] == '\\') return i + 2;
    }
    return 0;
}

test "the terminal's answers go, keys stay" {
    var out: [128]u8 = undefined;
    const t = std.testing;
    try t.expectEqualStrings("ab", strip("a\x1b[?62;22cb", &out));
    try t.expectEqualStrings("x", strip("\x1b]11;rgb:0000/0000/0000\x1b\\x", &out));
    try t.expectEqualStrings("", strip("\x1b]10;rgb:ffff/ffff/ffff\x07\x1b[12;40R\x1b[?1u\x1b[?2004;1$y", &out));
    try t.expectEqualStrings("", strip("\x1bP>|iTerm2 3.5\x1b\\\x1b[>0;95;0c", &out));
    // Arrows, Home, F5, a pasted escape, Alt+x and Esc alone are typing.
    const keys = "\x1b[A\x1b[1;5C\x1b[15~\x1b[H\x1bx\x1b";
    try t.expectEqualStrings(keys, strip(keys, &out));
}
