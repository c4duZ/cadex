//! Keyboard input: turns a key the app reports (our own Key and Mods, see
//! CADEX_KEY_* and CADEX_MOD_* in include/cadex.h) into the bytes the program
//! expects, following the terminal's current modes: application cursor keys
//! (vim, less, htop), modifiers on special keys, the kitty keyboard protocol.
//! Touches libghostty-vt's key encoder, so it is one of the files allowed to
//! import it (ADR 0003).

const std = @import("std");
const vt = @import("ghostty-vt");

/// Physical keys that are not text. The values are the C API's CADEX_KEY_*.
pub const Key = enum(u16) {
    /// No special key: the event is text with Ctrl or Alt (Ctrl+C, Meta+B).
    none = 0,
    enter = 1,
    tab = 2,
    backspace = 3,
    escape = 4,
    delete = 5,
    insert = 6,
    home = 7,
    end = 8,
    page_up = 9,
    page_down = 10,
    arrow_up = 11,
    arrow_down = 12,
    arrow_left = 13,
    arrow_right = 14,
    f1 = 15,
    f2 = 16,
    f3 = 17,
    f4 = 18,
    f5 = 19,
    f6 = 20,
    f7 = 21,
    f8 = 22,
    f9 = 23,
    f10 = 24,
    f11 = 25,
    f12 = 26,
    _,

    fn toVt(self: Key) ?vt.input.Key {
        return switch (self) {
            .none => .unidentified,
            .enter => .enter,
            .tab => .tab,
            .backspace => .backspace,
            .escape => .escape,
            .delete => .delete,
            .insert => .insert,
            .home => .home,
            .end => .end,
            .page_up => .page_up,
            .page_down => .page_down,
            .arrow_up => .arrow_up,
            .arrow_down => .arrow_down,
            .arrow_left => .arrow_left,
            .arrow_right => .arrow_right,
            .f1 => .f1,
            .f2 => .f2,
            .f3 => .f3,
            .f4 => .f4,
            .f5 => .f5,
            .f6 => .f6,
            .f7 => .f7,
            .f8 => .f8,
            .f9 => .f9,
            .f10 => .f10,
            .f11 => .f11,
            .f12 => .f12,
            _ => null,
        };
    }
};

/// Modifier bits, the C API's CADEX_MOD_*. Alt is only set by the app when
/// Option should act as Meta; otherwise Option already composed the text.
pub const Mods = packed struct(u8) {
    shift: bool = false,
    ctrl: bool = false,
    alt: bool = false,
    super: bool = false,
    _padding: u4 = 0,
};

pub const Error = error{ InvalidKey, KeyTooLong };

/// Longest sequence a key produces: a kitty CSI u with every field filled,
/// or the text of one key with an ESC before it.
pub const max_sequence_len = 128;

/// Encodes one key press into `out` and returns the bytes to write to the
/// pty, which may be empty. `text` is what the key typed with Shift applied
/// but not Ctrl or Option ("A" for Ctrl+Shift+A); `unshifted` is the same key
/// without Shift ('a'), or 0. Call with the session locked: it reads modes.
pub fn encodeKey(
    out: *[max_sequence_len]u8,
    terminal: *const vt.Terminal,
    key: Key,
    mods: Mods,
    text: []const u8,
    unshifted: u21,
) Error![]const u8 {
    const vt_key = key.toVt() orelse return error.InvalidKey;
    const vt_mods: vt.input.KeyMods = .{
        .shift = mods.shift,
        .ctrl = mods.ctrl,
        .alt = mods.alt,
        .super = mods.super,
    };
    // Shift produced the text (macOS hands it over already shifted), so it is
    // consumed; Ctrl and Alt still have to be encoded.
    const event: vt.input.KeyEvent = .{
        .key = vt_key,
        .mods = vt_mods,
        .consumed_mods = .{ .shift = mods.shift and text.len > 0 },
        .utf8 = text,
        .unshifted_codepoint = unshifted,
    };

    var options: vt.input.KeyEncodeOptions = .fromTerminal(terminal);
    // The app only reports Alt when Option should be Meta, so honor it.
    options.macos_option_as_alt = .true;

    var writer: std.Io.Writer = .fixed(out);
    vt.input.encodeKey(&writer, event, options) catch return error.KeyTooLong;
    return writer.buffered();
}

const testing = std.testing;

fn expectKey(
    terminal: *const vt.Terminal,
    expected: []const u8,
    key: Key,
    mods: Mods,
    text: []const u8,
    unshifted: u21,
) !void {
    var buf: [max_sequence_len]u8 = undefined;
    try testing.expectEqualStrings(expected, try encodeKey(&buf, terminal, key, mods, text, unshifted));
}

const TestTerminal = struct {
    terminal: vt.Terminal,
    stream: vt.TerminalStream,

    fn init(self: *TestTerminal) !void {
        self.terminal = try .init(testing.io, testing.allocator, .{ .cols = 20, .rows = 4 });
        self.stream = .init(.{ .allocator = testing.allocator, .handler = .init(&self.terminal) });
    }

    fn deinit(self: *TestTerminal) void {
        self.stream.deinit();
        self.terminal.deinit(testing.allocator);
    }
};

test "arrow keys follow application cursor mode" {
    var t: TestTerminal = undefined;
    try t.init();
    defer t.deinit();

    try expectKey(&t.terminal, "\x1b[A", .arrow_up, .{}, "", 0);
    t.stream.nextSlice("\x1b[?1h");
    try expectKey(&t.terminal, "\x1bOA", .arrow_up, .{}, "", 0);
    t.stream.nextSlice("\x1b[?1l");
    try expectKey(&t.terminal, "\x1b[A", .arrow_up, .{}, "", 0);
}

test "special keys and modifiers" {
    var t: TestTerminal = undefined;
    try t.init();
    defer t.deinit();

    try expectKey(&t.terminal, "\r", .enter, .{}, "", 0);
    try expectKey(&t.terminal, "\x7f", .backspace, .{}, "", 0);
    try expectKey(&t.terminal, "\x1b", .escape, .{}, "", 0);
    try expectKey(&t.terminal, "\x1b[1;5C", .arrow_right, .{ .ctrl = true }, "", 0);
    try expectKey(&t.terminal, "\x1b[1;2H", .home, .{ .shift = true }, "", 0);
    try expectKey(&t.terminal, "\x1b[5;5~", .page_up, .{ .ctrl = true }, "", 0);
    try expectKey(&t.terminal, "\x1bOP", .f1, .{}, "", 0);
    try expectKey(&t.terminal, "\x1b[24~", .f12, .{}, "", 0);
    try expectKey(&t.terminal, "\x1b[Z", .tab, .{ .shift = true }, "", 0);
}

test "control and meta combinations on text" {
    var t: TestTerminal = undefined;
    try t.init();
    defer t.deinit();

    try expectKey(&t.terminal, "\x03", .none, .{ .ctrl = true }, "c", 'c');
    try expectKey(&t.terminal, "\x1bb", .none, .{ .alt = true }, "b", 'b');
    try expectKey(&t.terminal, "\x1bB", .none, .{ .alt = true, .shift = true }, "B", 'b');
}

test "kitty keyboard protocol when the program asks for it" {
    var t: TestTerminal = undefined;
    try t.init();
    defer t.deinit();

    // Push flag 1 (disambiguate escape codes), as neovim and fish do.
    t.stream.nextSlice("\x1b[>1u");
    try expectKey(&t.terminal, "\x1b[27u", .escape, .{}, "", 0);
    try expectKey(&t.terminal, "\x1b[99;5u", .none, .{ .ctrl = true }, "c", 'c');
}

test "rejects keys the core does not know" {
    var t: TestTerminal = undefined;
    try t.init();
    defer t.deinit();

    var buf: [max_sequence_len]u8 = undefined;
    try testing.expectError(error.InvalidKey, encodeKey(&buf, &t.terminal, @enumFromInt(999), .{}, "", 0));
}
