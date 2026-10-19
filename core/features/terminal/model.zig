//! The terminal model: libghostty-vt's Terminal plus the stream that parses
//! shell output into it. This is the only file in Cadex that talks to
//! libghostty-vt (ADR 0003).

const std = @import("std");
const vt = @import("ghostty-vt");

const Stream = vt.TerminalStream;
const Handler = @FieldType(Stream, "handler");

/// Called with bytes the terminal must send back to the shell, such as the
/// reply to a cursor position or device attributes query. The slice is only
/// valid during the call.
pub const ReplyFn = *const fn (context: ?*anyopaque, bytes: []const u8) void;

pub const Size = struct { cols: u16, rows: u16 };

pub const Model = struct {
    gpa: std.mem.Allocator,
    terminal: vt.Terminal,
    stream: Stream,
    reply: ?ReplyFn = null,
    reply_context: ?*anyopaque = null,

    /// Heap-allocated because the stream's handler keeps a pointer to the
    /// terminal; the model must not move after init.
    pub fn create(io: std.Io, gpa: std.mem.Allocator, size: Size) !*Model {
        const self = try gpa.create(Model);
        errdefer gpa.destroy(self);
        self.* = .{
            .gpa = gpa,
            .terminal = try .init(io, gpa, .{ .cols = size.cols, .rows = size.rows }),
            .stream = undefined,
        };
        errdefer self.terminal.deinit(gpa);

        var handler: Handler = .init(&self.terminal);
        handler.effects.write_pty = &writePty;
        self.stream = .init(.{ .allocator = gpa, .handler = handler });
        return self;
    }

    pub fn destroy(self: *Model) void {
        const gpa = self.gpa;
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

    /// Current directory reported by the shell through OSC 7, if any.
    pub fn workingDirectory(self: *Model) ?[]const u8 {
        return self.terminal.getPwd();
    }

    pub fn title(self: *Model) ?[]const u8 {
        return self.terminal.getTitle();
    }

    /// Visible text, one line per row. Caller frees.
    pub fn plainText(self: *Model, gpa: std.mem.Allocator) ![]const u8 {
        return self.terminal.plainString(gpa);
    }

    fn writePty(handler: *Handler, bytes: []const u8) void {
        const stream: *Stream = @fieldParentPtr("handler", handler);
        const self: *Model = @fieldParentPtr("stream", stream);
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
