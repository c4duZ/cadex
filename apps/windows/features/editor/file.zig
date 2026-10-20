//! Reading and saving a file through the core's explorer feature, which
//! checks the workspace (docs/spec/editor.md, "Limites"), with the Mac's
//! limits and messages (apps/macos/features/editor/EditorFile.swift).

const std = @import("std");
const cadex = @import("cadex");

/// Above this the view shows the start only, read-only.
pub const max_bytes: u64 = 10 * 1024 * 1024;
/// Above this, no colors or folds (the core's limit too).
pub const max_highlight_bytes = 1024 * 1024;

pub const Loaded = union(enum) {
    text: Text,
    binary,
    /// Why it could not be read, in Portuguese.
    failed: []const u8,
};

pub const Text = struct {
    /// Owned by the caller. Bad UTF-8 bytes are U+FFFD in it.
    bytes: []u8,
    /// Of the bytes as on disk, to tell our own saves and unchanged files
    /// from real changes.
    disk_hash: u64,
    disk_len: usize,
    /// Only the first max_bytes.
    truncated: bool,
    /// The bytes were UTF-8 (otherwise saving would spoil the file).
    valid: bool,
};

pub fn hash(bytes: []const u8) u64 {
    return std.hash.Wyhash.hash(0x6564, bytes);
}

pub fn read(gpa: std.mem.Allocator, path: []const u8) Loaded {
    const z = gpa.dupeZ(u8, path) catch return .{ .failed = "Memória insuficiente para ler o arquivo" };
    defer gpa.free(z);
    var out: [*c]u8 = null;
    var len: usize = 0;
    var truncated = false;
    const status = cadex.cadex_explorer_read_text_head(z.ptr, max_bytes, &out, &len, &truncated);
    switch (status) {
        cadex.CADEX_OK => {},
        cadex.CADEX_BINARY => return .binary,
        cadex.CADEX_NOT_FOUND => return .{ .failed = "O arquivo não existe mais" },
        cadex.CADEX_NOT_AUTHORIZED => return .{ .failed = "O arquivo está fora da pasta aberta" },
        cadex.CADEX_PERMISSION_DENIED => return .{ .failed = "Sem permissão para ler o arquivo" },
        else => return .{ .failed = "Não foi possível ler o arquivo" },
    }
    defer cadex.cadex_free(out);
    const raw: []const u8 = if (out == null) "" else out[0..len];
    const valid = std.unicode.utf8ValidateSlice(raw);
    const bytes = (if (valid) gpa.dupe(u8, raw) else replaceInvalid(gpa, raw)) catch return .{ .failed = "Memória insuficiente para ler o arquivo" };
    return .{ .text = .{ .bytes = bytes, .disk_hash = hash(raw), .disk_len = raw.len, .truncated = truncated, .valid = valid } };
}

/// Null when saved, otherwise why not.
pub fn write(gpa: std.mem.Allocator, path: []const u8, bytes: []const u8) ?[]const u8 {
    const z = gpa.dupeZ(u8, path) catch return "Memória insuficiente para salvar";
    defer gpa.free(z);
    return switch (cadex.cadex_explorer_write_text(z.ptr, bytes.ptr, bytes.len)) {
        cadex.CADEX_OK => null,
        cadex.CADEX_NOT_AUTHORIZED => "O arquivo está fora da pasta aberta",
        cadex.CADEX_PERMISSION_DENIED => "Sem permissão para gravar o arquivo",
        else => "Não foi possível salvar o arquivo",
    };
}

/// Each byte that is not part of valid UTF-8 becomes U+FFFD.
pub fn replaceInvalid(gpa: std.mem.Allocator, raw: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    var i: usize = 0;
    while (i < raw.len) {
        const len = std.unicode.utf8ByteSequenceLength(raw[i]) catch 0;
        if (len > 0 and i + len <= raw.len and std.unicode.utf8ValidateSlice(raw[i..][0..len])) {
            try out.appendSlice(gpa, raw[i..][0..len]);
            i += len;
        } else {
            try out.appendSlice(gpa, "\u{FFFD}");
            i += 1;
        }
    }
    return out.toOwnedSlice(gpa);
}

test "bad bytes become the replacement character" {
    const got = try replaceInvalid(std.testing.allocator, "a\xffé\xc3");
    defer std.testing.allocator.free(got);
    try std.testing.expectEqualStrings("a\u{FFFD}é\u{FFFD}", got);
}

test {
    @import("win32").refAllDeep(@This());
}
