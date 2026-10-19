//! The mouse for programs that ask for it (vim, htop, tmux): clicks, drags,
//! motion and the wheel encoded in the format the program set, the wheel as
//! arrow keys on the alternate screen, and focus in/out reports. Uses
//! libghostty-vt's encoders, so it is one of the files allowed to import it
//! (ADR 0003). Call with the session locked: it reads modes.

const std = @import("std");
const vt = @import("ghostty-vt");
const input = @import("input.zig");

/// A mouse event from the app. Mirrors cadex_terminal_mouse_event in
/// include/cadex.h.
pub const Event = extern struct {
    /// Pixels from the view's top-left corner.
    x: f64,
    y: f64,
    view_width: u32,
    view_height: u32,
    cell_width: u16,
    cell_height: u16,
    /// Space around the grid, in pixels, the same on every side.
    padding: u16,
    action: Action,
    button: Button,
    /// CADEX_MOD_* (input.Mods).
    mods: u8,
};

pub const Action = enum(u8) { press = 0, release = 1, motion = 2 };
pub const Button = enum(u8) { none = 0, left = 1, right = 2, middle = 3 };

/// What the program asked to receive. The app sends clicks to the program
/// instead of selecting while this is not none (Shift still selects).
pub const Tracking = enum(u8) {
    none = 0,
    /// Presses (and releases): X10 and normal modes.
    clicks = 1,
    /// Clicks and motion while a button is down.
    drag = 2,
    /// Clicks and every motion.
    motion = 3,
};

/// Room for the longest report (SGR with large coordinates) several times,
/// for a fast wheel turn sent as many events.
pub const max_encoded_len = 256;

pub fn tracking(terminal: *const vt.Terminal) Tracking {
    return switch (terminal.flags.mouse_event) {
        .none => .none,
        .x10, .normal => .clicks,
        .button => .drag,
        .any => .motion,
    };
}

/// Encodes a click, release or motion. `last_cell` drops motion that stays
/// in the same cell. Returns the bytes for the pty, possibly empty.
pub fn encode(out: []u8, terminal: *const vt.Terminal, e: Event, last_cell: *?vt.Coordinate) []const u8 {
    var writer: std.Io.Writer = .fixed(out);
    encodeOne(&writer, terminal, e, buttonOf(e.button), last_cell) catch {};
    return writer.buffered();
}

/// What the wheel does in this terminal, `rows` steps (negative is up):
/// wheel reports for a program tracking the mouse, arrow keys on the
/// alternate screen (less, vim without mouse: mode 1007), or null to scroll
/// the history.
pub fn encodeWheel(out: []u8, terminal: *const vt.Terminal, e: Event, rows: i32, last_cell: *?vt.Coordinate) ?[]const u8 {
    var writer: std.Io.Writer = .fixed(out);
    const steps = @min(@abs(rows), 10);
    if (tracking(terminal) != .none) {
        const button: vt.input.MouseButton = if (rows < 0) .four else .five;
        var press = e;
        press.action = .press;
        for (0..steps) |_| encodeOne(&writer, terminal, press, button, last_cell) catch break;
        return writer.buffered();
    }
    const alternate = terminal.screens.active_key == .alternate;
    if (alternate and terminal.modes.get(.mouse_alternate_scroll)) {
        const key: input.Key = if (rows < 0) .arrow_up else .arrow_down;
        var buf: [input.max_sequence_len]u8 = undefined;
        for (0..steps) |_| {
            const bytes = input.encodeKey(&buf, terminal, key, .{}, "", 0) catch break;
            writer.writeAll(bytes) catch break;
        }
        return writer.buffered();
    }
    return null;
}

/// CSI I or CSI O when the program asked for focus reports (mode 1004).
pub fn encodeFocus(out: []u8, terminal: *const vt.Terminal, focused: bool) []const u8 {
    if (!terminal.modes.get(.focus_event)) return out[0..0];
    var writer: std.Io.Writer = .fixed(out);
    vt.input.encodeFocus(&writer, if (focused) .gained else .lost) catch {};
    return writer.buffered();
}

fn encodeOne(
    writer: *std.Io.Writer,
    terminal: *const vt.Terminal,
    e: Event,
    button: ?vt.input.MouseButton,
    last_cell: *?vt.Coordinate,
) !void {
    const Size = @FieldType(vt.input.MouseEncodeOptions, "size");
    const Mods = input.Mods;
    const mods: Mods = @bitCast(e.mods);
    var options: vt.input.MouseEncodeOptions = .fromTerminal(terminal, Size{
        .screen = .{ .width = e.view_width, .height = e.view_height },
        .cell = .{ .width = e.cell_width, .height = e.cell_height },
        .padding = .{ .top = e.padding, .bottom = e.padding, .left = e.padding, .right = e.padding },
    });
    options.any_button_pressed = e.action == .press or (e.action == .motion and button != null);
    options.last_cell = last_cell;
    try vt.input.encodeMouse(writer, .{
        .action = switch (e.action) {
            .press => .press,
            .release => .release,
            .motion => .motion,
        },
        .button = button,
        .mods = .{ .shift = mods.shift, .ctrl = mods.ctrl, .alt = mods.alt, .super = mods.super },
        .pos = .{ .x = @floatCast(e.x), .y = @floatCast(e.y) },
    }, options);
}

fn buttonOf(button: Button) ?vt.input.MouseButton {
    return switch (button) {
        .none => null,
        .left => .left,
        .right => .right,
        .middle => .middle,
    };
}

comptime {
    // Layout shared with include/cadex.h, which asserts the same size.
    std.debug.assert(@sizeOf(Event) == 40);
}

const testing = std.testing;

const TestTerminal = struct {
    terminal: vt.Terminal,
    stream: vt.TerminalStream,

    fn init(self: *TestTerminal) !void {
        self.terminal = try .init(testing.io, testing.allocator, .{ .cols = 80, .rows = 24 });
        self.stream = .init(.{ .allocator = testing.allocator, .handler = .init(&self.terminal) });
    }

    fn deinit(self: *TestTerminal) void {
        self.stream.deinit();
        self.terminal.deinit(testing.allocator);
    }
};

/// Cell (col, row) with 10x20 px cells and 5 px padding.
fn at(col: u32, row: u32, action: Action, button: Button) Event {
    return .{
        .x = @floatFromInt(5 + col * 10 + 5),
        .y = @floatFromInt(5 + row * 20 + 10),
        .view_width = 810,
        .view_height = 490,
        .cell_width = 10,
        .cell_height = 20,
        .padding = 5,
        .action = action,
        .button = button,
        .mods = 0,
    };
}

test "clicks reach the program in SGR format once it asks" {
    var t: TestTerminal = undefined;
    try t.init();
    defer t.deinit();
    var buf: [max_encoded_len]u8 = undefined;
    var last: ?vt.Coordinate = null;

    try testing.expectEqual(Tracking.none, tracking(&t.terminal));
    try testing.expectEqualStrings("", encode(&buf, &t.terminal, at(2, 3, .press, .left), &last));

    // Button-event tracking with SGR coordinates, as vim and htop set.
    t.stream.nextSlice("\x1b[?1002h\x1b[?1006h");
    try testing.expectEqual(Tracking.drag, tracking(&t.terminal));
    try testing.expectEqualStrings("\x1b[<0;3;4M", encode(&buf, &t.terminal, at(2, 3, .press, .left), &last));
    try testing.expectEqualStrings("\x1b[<32;4;4M", encode(&buf, &t.terminal, at(3, 3, .motion, .left), &last));
    try testing.expectEqualStrings("\x1b[<0;4;4m", encode(&buf, &t.terminal, at(3, 3, .release, .left), &last));
}

test "the wheel scrolls, sends arrows or reports, depending on the program" {
    var t: TestTerminal = undefined;
    try t.init();
    defer t.deinit();
    var buf: [max_encoded_len]u8 = undefined;
    var last: ?vt.Coordinate = null;
    const e = at(0, 0, .press, .none);

    // Shell on the main screen: scroll the history.
    try testing.expect(encodeWheel(&buf, &t.terminal, e, -1, &last) == null);

    // less on the alternate screen: arrows.
    t.stream.nextSlice("\x1b[?1049h");
    try testing.expectEqualStrings("\x1b[A\x1b[A", encodeWheel(&buf, &t.terminal, e, -2, &last).?);

    // A program tracking the mouse gets wheel buttons.
    t.stream.nextSlice("\x1b[?1000h\x1b[?1006h");
    try testing.expectEqualStrings("\x1b[<65;1;1M", encodeWheel(&buf, &t.terminal, e, 1, &last).?);
}

test "focus reports only when asked" {
    var t: TestTerminal = undefined;
    try t.init();
    defer t.deinit();
    var buf: [8]u8 = undefined;

    try testing.expectEqualStrings("", encodeFocus(&buf, &t.terminal, true));
    t.stream.nextSlice("\x1b[?1004h");
    try testing.expectEqualStrings("\x1b[I", encodeFocus(&buf, &t.terminal, true));
    try testing.expectEqualStrings("\x1b[O", encodeFocus(&buf, &t.terminal, false));
}
