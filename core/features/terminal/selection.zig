//! Text selection with the mouse: press, drag (with autoscroll past the top
//! or bottom), release, Shift+click to extend, select all, and the selected
//! text for copying. Wraps libghostty-vt's SelectionGesture, so it is one of
//! the files allowed to import it (ADR 0003). Call everything with the session
//! locked: it reads and changes the terminal's screen.

const std = @import("std");
const vt = @import("ghostty-vt");

/// Where the pointer is. Mirrors cadex_terminal_pointer in include/cadex.h.
pub const Pointer = extern struct {
    /// Pixels from the view's top-left corner (padding included).
    x: f64,
    y: f64,
    /// The viewport cell under the pointer, clamped to the grid.
    col: u16,
    row: u16,
    /// Cell width and left padding in pixels: a drag that crosses the middle
    /// of a cell selects it, as in Terminal.app.
    cell_width: u16,
    padding_left: u16,
    /// Height of the view in pixels: dragging past it scrolls.
    view_height: u32,
};

/// Where a drag wants the viewport to move. The app keeps a timer calling
/// autoscroll() while this is not none and the button is down.
pub const Autoscroll = enum(i8) { up = -1, none = 0, down = 1 };

/// What ends a word on double-click: whitespace, quotes, brackets and shell
/// punctuation, so a path or URL inside parentheses selects without them.
/// Not '/', '.', '-' or '~': those are part of paths. libghostty-vt keeps
/// its own default list private to the library.
const word_boundaries = [_]u21{
    0, ' ', '\t', '\'', '"', '`', '│', '|', ':', ';', ',',
    '(', ')', '[', ']', '{', '}', '<', '>', '$',
};

pub const Selector = struct {
    gesture: vt.SelectionGesture = .init,

    pub fn deinit(self: *Selector, terminal: *vt.Terminal) void {
        self.gesture.deinit(terminal);
    }

    /// clicks: 1 selects by cell (a plain click clears), 2 by word, 3 by line.
    /// The app counts clicks (NSEvent.clickCount follows the system's
    /// double-click speed), so the gesture never counts on its own.
    /// extend: Shift+click moves the far end of the current selection here.
    pub fn press(self: *Selector, terminal: *vt.Terminal, p: Pointer, clicks: u8, extend: bool) !void {
        const pin = viewportPin(terminal, p) orelse return;
        const screen = terminal.screens.active;
        if (extend) {
            if (screen.selection) |current| {
                try screen.select(vt.Selection.init(current.start(), pin, false));
                return;
            }
        }
        const behavior: vt.SelectionGesture.Behavior = switch (clicks) {
            0, 1 => .cell,
            2 => .word,
            else => .line,
        };
        const behaviors = [3]vt.SelectionGesture.Behavior{ behavior, behavior, behavior };
        const selection = try self.gesture.press(terminal, .{
            .time = null,
            .pin = pin,
            .xpos = p.x,
            .ypos = p.y,
            .max_distance = @floatFromInt(p.cell_width),
            .repeat_interval = 0,
            .word_boundary_codepoints = &word_boundaries,
            .behaviors = &behaviors,
        });
        try screen.select(selection);
    }

    pub fn drag(self: *Selector, terminal: *vt.Terminal, p: Pointer) !Autoscroll {
        const pin = viewportPin(terminal, p) orelse return .none;
        const selection = self.gesture.drag(terminal, .{
            .pin = pin,
            .xpos = p.x,
            .ypos = p.y,
            .rectangle = false,
            .word_boundary_codepoints = &word_boundaries,
            .geometry = geometry(terminal, p),
        });
        if (selection) |s| try terminal.screens.active.select(s);
        return self.autoscrollDirection();
    }

    /// One autoscroll step: scrolls a row and extends the selection to the
    /// row now under the pointer.
    pub fn autoscroll(self: *Selector, terminal: *vt.Terminal, p: Pointer) !Autoscroll {
        const selection = self.gesture.autoscrollTick(terminal, .{
            .viewport = .{ .x = p.col, .y = p.row },
            .xpos = p.x,
            .ypos = p.y,
            .rectangle = false,
            .word_boundary_codepoints = &word_boundaries,
            .geometry = geometry(terminal, p),
        });
        if (selection) |s| try terminal.screens.active.select(s);
        return self.autoscrollDirection();
    }

    pub fn release(self: *Selector, terminal: *vt.Terminal, p: Pointer) void {
        self.gesture.release(terminal, .{ .pin = viewportPin(terminal, p) });
    }

    fn autoscrollDirection(self: *const Selector) Autoscroll {
        return switch (self.gesture.left_drag_autoscroll) {
            .up => .up,
            .down => .down,
            else => .none,
        };
    }
};

pub fn selectAll(terminal: *vt.Terminal) !void {
    const screen = terminal.screens.active;
    try screen.select(screen.selectAll());
}

pub fn clear(terminal: *vt.Terminal) void {
    terminal.screens.active.clearSelection();
}

pub fn hasSelection(terminal: *const vt.Terminal) bool {
    return terminal.screens.active.selection != null;
}

/// The selected text, or null without a selection. Soft-wrapped lines come
/// back joined and trailing spaces are trimmed, so a long command copied
/// from the screen pastes as one line. Caller frees with `gpa`.
pub fn selectedText(terminal: *vt.Terminal, gpa: std.mem.Allocator) !?[:0]const u8 {
    const screen = terminal.screens.active;
    const selection = screen.selection orelse return null;
    return try screen.selectionString(gpa, .{ .sel = selection, .trim = true });
}

fn viewportPin(terminal: *const vt.Terminal, p: Pointer) ?vt.Pin {
    return terminal.screens.active.pages.pin(.{ .viewport = .{ .x = p.col, .y = p.row } });
}

fn geometry(terminal: *const vt.Terminal, p: Pointer) vt.SelectionGesture.Drag.Geometry {
    return .{
        .columns = terminal.cols,
        .cell_width = p.cell_width,
        .padding_left = p.padding_left,
        .screen_height = p.view_height,
    };
}

comptime {
    // Layout shared with include/cadex.h, which asserts the same size.
    std.debug.assert(@sizeOf(Pointer) == 32);
}
