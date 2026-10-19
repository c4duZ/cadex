//! The terminal model: libghostty-vt's Terminal plus the stream that parses
//! shell output into it. This is the only file in Cadex that talks to
//! libghostty-vt (ADR 0003).

const std = @import("std");
const vt = @import("ghostty-vt");

const selection = @import("selection.zig");

const Stream = vt.TerminalStream;
const Handler = @FieldType(Stream, "handler");

/// Called with bytes the terminal must send back to the shell, such as the
/// reply to a cursor position or device attributes query. The slice is only
/// valid during the call.
pub const ReplyFn = *const fn (context: ?*anyopaque, bytes: []const u8) void;

pub const Size = struct { cols: u16, rows: u16 };

/// Lines of history kept above the screen, at least (docs/spec/terminal.md).
/// Counted in lines, not bytes: libghostty-vt's default is 10 KB, a few
/// screens.
pub const scrollback_lines = 10_000;
/// libghostty-vt drops history a whole page at a time, so with a limit of
/// exactly 10 000 only ~9 700 lines were left (measured 2026-10-19, 20
/// columns). The headroom covers one page.
const scrollback_headroom = 1_000;

/// Where the viewport sits in the history, in rows. offset + rows == total
/// when it shows the bottom.
pub const Scrollbar = struct { total: usize, offset: usize, rows: usize };

pub const Model = struct {
    /// libghostty-vt's blocking Io, sized for an embedded library: no thread
    /// pool and no 256 KB of thread-local storage, unlike std.Io.Threaded.
    pub fn defaultIo() std.Io {
        return vt.TinyIo.init.io();
    }

    gpa: std.mem.Allocator,
    terminal: vt.Terminal,
    stream: Stream,
    reply: ?ReplyFn = null,
    reply_context: ?*anyopaque = null,
    selector: selection.Selector = .{},

    /// Heap-allocated because the stream's handler keeps a pointer to the
    /// terminal; the model must not move after init.
    pub fn create(io: std.Io, gpa: std.mem.Allocator, size: Size) !*Model {
        const self = try gpa.create(Model);
        errdefer gpa.destroy(self);
        self.* = .{
            .gpa = gpa,
            .terminal = try .init(io, gpa, .{
                .cols = size.cols,
                .rows = size.rows,
                .max_scrollback_bytes = null,
                .max_scrollback_lines = scrollback_lines + scrollback_headroom,
            }),
            .stream = undefined,
        };
        errdefer self.terminal.deinit(gpa);
        // Keep emoji sequences (skin tones, ZWJ families) and combining
        // accents in one cell, as Ghostty does by default (mode 2027).
        // Without it a thumbs-up with a skin tone splits into two glyphs.
        self.terminal.modes.set(.grapheme_cluster, true);

        var handler: Handler = .init(&self.terminal);
        handler.effects.write_pty = &writePty;
        self.stream = .init(.{ .allocator = gpa, .handler = handler });
        return self;
    }

    pub fn destroy(self: *Model) void {
        const gpa = self.gpa;
        self.selector.deinit(&self.terminal);
        self.stream.deinit();
        self.terminal.deinit(gpa);
        gpa.destroy(self);
    }

    pub fn setReply(self: *Model, reply: ReplyFn, context: ?*anyopaque) void {
        self.reply = reply;
        self.reply_context = context;
    }

    /// Feeds shell output into the model.
    pub fn feed(self: *Model, bytes: []const u8) void {
        self.stream.nextSlice(bytes);
    }

    pub fn resize(self: *Model, size: Size) !void {
        try self.stream.handler.resize(.{ .cols = size.cols, .rows = size.rows });
    }

    /// Moves the viewport through the history; negative goes up.
    pub fn scroll(self: *Model, rows: isize) void {
        self.terminal.scrollViewport(.{ .delta = rows });
    }

    pub fn scrollToTop(self: *Model) void {
        self.terminal.scrollViewport(.top);
    }

    pub fn scrollToBottom(self: *Model) void {
        self.terminal.scrollViewport(.bottom);
    }

    pub fn scrollbar(self: *Model) Scrollbar {
        const bar = self.terminal.screens.active.pages.scrollbar();
        return .{ .total = bar.total, .offset = bar.offset, .rows = bar.len };
    }

    /// Current directory reported by the shell through OSC 7, if any.
    pub fn workingDirectory(self: *Model) ?[]const u8 {
        return self.terminal.getPwd();
    }

    pub fn title(self: *Model) ?[]const u8 {
        return self.terminal.getTitle();
    }

    /// Visible text (the viewport), one line per row. Caller frees.
    pub fn plainText(self: *Model, gpa: std.mem.Allocator) ![]const u8 {
        return self.terminal.plainString(gpa);
    }

    fn writePty(handler: *Handler, bytes: []const u8) void {
        const stream: *Stream = @fieldParentPtr("handler", handler);
        const self: *Model = @alignCast(@fieldParentPtr("stream", stream));
        const reply = self.reply orelse return;
        reply(self.reply_context, bytes);
    }
};

const testing = std.testing;

test "renders text and colors into the grid" {
    const model = try Model.create(testing.io, testing.allocator, .{ .cols = 20, .rows = 4 });
    defer model.destroy();

    model.feed("hello\r\n\x1b[1;32mgreen\x1b[0m");

    const text = try model.plainText(testing.allocator);
    defer testing.allocator.free(text);
    try testing.expectEqualStrings("hello\ngreen", text);
}

test "answers a cursor position query through the reply callback" {
    const Capture = struct {
        var buf: [32]u8 = undefined;
        var len: usize = 0;
        fn reply(_: ?*anyopaque, bytes: []const u8) void {
            @memcpy(buf[0..bytes.len], bytes);
            len = bytes.len;
        }
    };
    Capture.len = 0;

    const model = try Model.create(testing.io, testing.allocator, .{ .cols = 20, .rows = 4 });
    defer model.destroy();
    model.setReply(&Capture.reply, null);

    model.feed("ab\x1b[6n");
    try testing.expectEqualStrings("\x1b[1;3R", Capture.buf[0..Capture.len]);
}

test "tracks the working directory reported by the shell (OSC 7)" {
    const model = try Model.create(testing.io, testing.allocator, .{ .cols = 20, .rows = 4 });
    defer model.destroy();

    model.feed("\x1b]7;file://localhost/Users/cadu/projeto\x07");
    try testing.expectEqualStrings(
        "file://localhost/Users/cadu/projeto",
        model.workingDirectory() orelse "",
    );
}

test "scrolls through the history and back to the bottom" {
    const model = try Model.create(testing.io, testing.allocator, .{ .cols = 20, .rows = 4 });
    defer model.destroy();

    for (1..101) |i| {
        var buf: [16]u8 = undefined;
        model.feed(try std.fmt.bufPrint(&buf, "{d}\r\n", .{i}));
    }
    // 100 lines and an empty prompt line: the screen shows 98..100 and "".
    model.scroll(-50);
    const scrolled = try model.plainText(testing.allocator);
    defer testing.allocator.free(scrolled);
    try testing.expectEqualStrings("48\n49\n50\n51", scrolled);

    const bar = model.scrollbar();
    try testing.expectEqual(@as(usize, 101), bar.total);
    try testing.expectEqual(@as(usize, 47), bar.offset);

    model.scrollToTop();
    const top = try model.plainText(testing.allocator);
    defer testing.allocator.free(top);
    try testing.expectEqualStrings("1\n2\n3\n4", top);

    model.scrollToBottom();
    try testing.expectEqual(model.scrollbar().total, model.scrollbar().offset + model.scrollbar().rows);
}

test "keeps ten thousand lines of history" {
    // Just past the limit with headroom, so a page gets dropped. Slow in
    // Debug (~0.7 ms per line in libghostty-vt's checks), so one width only.
    const model = try Model.create(testing.io, testing.allocator, .{ .cols = 80, .rows = 4 });
    defer model.destroy();

    model.feed("line\r\n" ** 12_000);
    const bar = model.scrollbar();
    try testing.expect(bar.total >= scrollback_lines);
    try testing.expect(bar.total < 12_000);
}
