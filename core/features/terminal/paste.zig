//! Pasting: the text the app takes from the clipboard (or file paths it
//! dropped) encoded for the program, plus the paths escaped for the shell.
//! Uses libghostty-vt's paste encoder, so it is one of the files allowed to
//! import it (ADR 0003). The app decides what to paste (files, image, text:
//! docs/spec/terminal.md); this file only encodes.

const std = @import("std");
const vt = @import("ghostty-vt");

/// The bytes to write to the pty for a paste: wrapped in ESC [ 200 ~ and
/// ESC [ 201 ~ when the program turned on bracketed paste, otherwise with
/// newlines sent as Enter. Control bytes that could inject commands become
/// spaces, as xterm does. Caller frees. Call with the session locked.
pub fn encode(gpa: std.mem.Allocator, terminal: *const vt.Terminal, text: []const u8) ![]u8 {
    var out: std.Io.Writer.Allocating = try .initCapacity(gpa, text.len + vt.input.max_paste_frame_size);
    defer out.deinit();
    vt.input.encodePasteWriter(&out.writer, text, .fromTerminal(terminal)) catch return error.OutOfMemory;
    return out.toOwnedSlice();
}

/// False when pasting could run commands the user did not see: several
/// lines into a program without bracketed paste (a shell would run each),
/// or text that closes the bracketed frame early. The app asks first.
pub fn isSafe(terminal: *const vt.Terminal, text: []const u8) bool {
    return vt.input.isSafePasteWith(text, .fromTerminal(terminal));
}

/// Paths joined by spaces, each escaped for POSIX shells: left as is when
/// made only of characters no shell treats specially, otherwise inside
/// single quotes, with a quote in the name written as '\''. Caller frees.
pub fn quotePaths(gpa: std.mem.Allocator, paths: []const []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    for (paths, 0..) |path, i| {
        if (i > 0) try out.append(gpa, ' ');
        try appendQuoted(gpa, &out, path);
    }
    return out.toOwnedSlice(gpa);
}

fn appendQuoted(gpa: std.mem.Allocator, out: *std.ArrayList(u8), path: []const u8) !void {
    if (path.len > 0 and isPlain(path)) return out.appendSlice(gpa, path);
    try out.append(gpa, '\'');
    for (path) |byte| {
        if (byte == '\'') {
            try out.appendSlice(gpa, "'\\''");
        } else {
            try out.append(gpa, byte);
        }
    }
    try out.append(gpa, '\'');
}

/// ASCII letters, digits and punctuation that no common shell (sh, bash,
/// zsh, fish) expands or splits on. Anything else, accents and emoji
/// included, gets quoted: zsh treats some bytes of UTF-8 specially.
fn isPlain(path: []const u8) bool {
    for (path) |byte| {
        const ok = std.ascii.isAlphanumeric(byte) or std.mem.indexOfScalar(u8, "/._-+,@%:=", byte) != null;
        if (!ok) return false;
    }
    return true;
}

const testing = std.testing;

fn expectQuoted(expected: []const u8, paths: []const []const u8) !void {
    const quoted = try quotePaths(testing.allocator, paths);
    defer testing.allocator.free(quoted);
    try testing.expectEqualStrings(expected, quoted);
}

test "paths are escaped for the shell" {
    try expectQuoted("/Users/cadu/notas.md", &.{"/Users/cadu/notas.md"});
    try expectQuoted("'/Users/cadu/Meus Arquivos/a b.txt'", &.{"/Users/cadu/Meus Arquivos/a b.txt"});
    try expectQuoted("'/tmp/it'\\''s.txt'", &.{"/tmp/it's.txt"});
    try expectQuoted("'/tmp/relatório.pdf'", &.{"/tmp/relatório.pdf"});
    try expectQuoted("'/tmp/foto 📷.png'", &.{"/tmp/foto 📷.png"});
    try expectQuoted("'/tmp/$HOME'", &.{"/tmp/$HOME"});
    try expectQuoted("/a 'b c' /d", &.{ "/a", "b c", "/d" });
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

test "bracketed paste wraps the text when the program asks for it" {
    var t: TestTerminal = undefined;
    try t.init();
    defer t.deinit();

    const plain = try encode(testing.allocator, &t.terminal, "ls\nls");
    defer testing.allocator.free(plain);
    try testing.expectEqualStrings("ls\rls", plain);
    try testing.expect(!isSafe(&t.terminal, "ls\nls"));
    try testing.expect(isSafe(&t.terminal, "one line"));

    t.stream.nextSlice("\x1b[?2004h");
    const bracketed = try encode(testing.allocator, &t.terminal, "ls\nls");
    defer testing.allocator.free(bracketed);
    try testing.expectEqualStrings("\x1b[200~ls\nls\x1b[201~", bracketed);
    try testing.expect(isSafe(&t.terminal, "ls\nls"));
    try testing.expect(!isSafe(&t.terminal, "a\x1b[201~rm -rf ~\n"));
}

test "control bytes in pasted text become spaces" {
    var t: TestTerminal = undefined;
    try t.init();
    defer t.deinit();

    const encoded = try encode(testing.allocator, &t.terminal, "a\x03b\x1bc");
    defer testing.allocator.free(encoded);
    try testing.expectEqualStrings("a b c", encoded);
}
