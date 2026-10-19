//! The terminal model: libghostty-vt's Terminal plus the stream that parses
//! shell output into it. This is the only file in Cadex that talks to
//! libghostty-vt (ADR 0003).

const std = @import("std");
const vt = @import("ghostty-vt");

const selection = @import("selection.zig");
const search = @import("search.zig");

const Stream = vt.TerminalStream;
const Handler = @FieldType(Stream, "handler");

/// Called with bytes the terminal must send back to the shell, such as the
/// reply to a cursor position or device attributes query. The slice is only
/// valid during the call.
pub const ReplyFn = *const fn (context: ?*anyopaque, bytes: []const u8) void;

/// Something the app shows outside the grid: the title changed (OSC 0/2),
/// or the program rang the bell. Called on the thread that feeds output.
pub const Notice = enum { title, bell };
pub const NoticeFn = *const fn (context: ?*anyopaque, notice: Notice) void;

pub const Size = struct { cols: u16, rows: u16 };

/// The theme's colors for the terminal (docs/spec/themes.md), 0xRRGGBB.
/// Mirrors cadex_terminal_colors in include/cadex.h.
pub const Colors = extern struct {
    background: u32,
    foreground: u32,
    cursor: u32,
    /// The 16 ANSI colors: 8 normal, then 8 bright.
    ansi: [16]u32,
};

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
    notice: ?NoticeFn = null,
    /// Last cell a mouse motion was reported for (mouse.zig drops repeats).
    last_mouse_cell: ?vt.Coordinate = null,
    selector: selection.Selector = .{},
    search: search.Search = .{},

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
        handler.effects.title_changed = &titleChanged;
        handler.effects.bell = &bellRang;
        self.stream = .init(.{ .allocator = gpa, .handler = handler });
        return self;
    }

    pub fn destroy(self: *Model) void {
        const gpa = self.gpa;
        self.selector.deinit(&self.terminal);
        self.search.deinit(&self.terminal);
        self.stream.deinit();
        self.terminal.deinit(gpa);
        gpa.destroy(self);
    }

    pub fn setReply(self: *Model, reply: ReplyFn, context: ?*anyopaque) void {
        self.reply = reply;
        self.reply_context = context;
    }

    /// Notices go to the same context as replies.
    pub fn setNotice(self: *Model, notice: NoticeFn) void {
        self.notice = notice;
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

    /// Sets the theme's colors as the terminal's defaults. What a program
    /// changed with OSC 4/10/11 stays changed, as in other terminals; the
    /// theme only replaces the defaults those reset to. Programs asking for
    /// the colors (OSC 10/11/4) get these.
    pub fn setColors(self: *Model, colors: Colors) !void {
        const t = &self.terminal;
        t.colors.background.default = rgbOf(colors.background);
        t.colors.foreground.default = rgbOf(colors.foreground);
        t.colors.cursor.default = rgbOf(colors.cursor);
        var palette = t.colors.palette.original.*;
        for (colors.ansi, 0..) |c, i| palette[i] = rgbOf(c);
        try t.colors.palette.changeDefault(self.gpa, palette);
        // A palette change forces the next frame to rebuild every cell.
        t.flags.dirty.palette = true;
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

    fn rgbOf(value: u32) vt.color.RGB {
        return .{ .r = @truncate(value >> 16), .g = @truncate(value >> 8), .b = @truncate(value) };
    }

    fn fromHandler(handler: *Handler) *Model {
        const stream: *Stream = @fieldParentPtr("handler", handler);
        return @alignCast(@fieldParentPtr("stream", stream));
    }

    fn writePty(handler: *Handler, bytes: []const u8) void {
        const self = fromHandler(handler);
        const reply = self.reply orelse return;
        reply(self.reply_context, bytes);
    }

    fn titleChanged(handler: *Handler) void {
        const self = fromHandler(handler);
        if (self.notice) |notify| notify(self.reply_context, .title);
    }

    fn bellRang(handler: *Handler) void {
        const self = fromHandler(handler);
        if (self.notice) |notify| notify(self.reply_context, .bell);
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

test "the theme's colors become the terminal's and answer color queries" {
    const Capture = struct {
        var buf: [64]u8 = undefined;
        var len: usize = 0;
        fn reply(_: ?*anyopaque, bytes: []const u8) void {
            @memcpy(buf[len..][0..bytes.len], bytes);
            len += bytes.len;
        }
    };
    Capture.len = 0;
    const model = try Model.create(testing.io, testing.allocator, .{ .cols = 20, .rows = 4 });
    defer model.destroy();
    model.setReply(&Capture.reply, null);

    var ansi: [16]u32 = undefined;
    for (&ansi, 0..) |*c, i| c.* = @intCast(0x101010 * i);
    try model.setColors(.{ .background = 0x161616, .foreground = 0xD6D6D6, .cursor = 0xE6E6E6, .ansi = ansi });
    try testing.expectEqual(@as(u8, 0x16), model.terminal.colors.background.get().?.r);
    try testing.expectEqual(@as(u8, 0x50), model.terminal.colors.palette.current[5].g);

    // vim asks for the background to choose between its light and dark look.
    model.feed("\x1b]11;?\x07");
    try testing.expect(std.mem.indexOf(u8, Capture.buf[0..Capture.len], "1616/1616/1616") != null);

    // A program's own change survives a theme change.
    model.feed("\x1b]4;1;rgb:ff/00/00\x07");
    try model.setColors(.{ .background = 0xFFFFFF, .foreground = 0, .cursor = 0, .ansi = ansi });
    try testing.expectEqual(@as(u8, 0xFF), model.terminal.colors.palette.current[1].r);
    try testing.expectEqual(@as(u8, 0xFF), model.terminal.colors.background.get().?.r);
}

test "the title and the bell reach the notice callback" {
    const Capture = struct {
        var titles: u32 = 0;
        var bells: u32 = 0;
        fn notice(_: ?*anyopaque, n: Notice) void {
            switch (n) {
                .title => titles += 1,
                .bell => bells += 1,
            }
        }
    };
    const model = try Model.create(testing.io, testing.allocator, .{ .cols = 20, .rows = 4 });
    defer model.destroy();
    model.setNotice(&Capture.notice);

    model.feed("\x1b]2;vim notas.md\x07\x07");
    try testing.expectEqualStrings("vim notas.md", model.title() orelse "");
    try testing.expectEqual(@as(u32, 1), Capture.titles);
    try testing.expectEqual(@as(u32, 1), Capture.bells);
}

test "long lines reflow when the width changes" {
    const model = try Model.create(testing.io, testing.allocator, .{ .cols = 10, .rows = 4 });
    defer model.destroy();
    model.feed("0123456789abcde");

    try model.resize(.{ .cols = 20, .rows = 4 });
    const wide = try model.plainText(testing.allocator);
    defer testing.allocator.free(wide);
    try testing.expectEqualStrings("0123456789abcde", wide);

    try model.resize(.{ .cols = 5, .rows = 4 });
    const narrow = try model.plainText(testing.allocator);
    defer testing.allocator.free(narrow);
    try testing.expectEqualStrings("01234\n56789\nabcde", narrow);
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
