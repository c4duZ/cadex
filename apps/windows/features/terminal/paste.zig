//! Paste and drop into a terminal (docs/spec/terminal.md, "Colar"): the
//! clipboard's first of files (their paths, escaped for the shell), an
//! image (saved as a PNG in %TEMP%\cadex-paste, its path pasted), text
//! (through the core, bracketed when the program asked). Several lines
//! without bracketed paste ask first, unless the settings turned it off.

const std = @import("std");
const gfx = @import("gfx");
const ui_mod = @import("ui");
const w = @import("win32");
const cadex = @import("cadex");
const Session = @import("session.zig").Session;

const c = w.c;

/// What a paste will send, decided before sending: text that could run
/// commands unseen waits for the user's answer.
pub const Plan = struct {
    bytes: []u8,
    /// Typed into the shell as is (paths) or encoded as a paste (text).
    as_paste: bool,
    needs_confirmation: bool,

    pub fn deinit(self: Plan, gpa: std.mem.Allocator) void {
        gpa.free(self.bytes);
    }
};

/// The paths escaped for the shell, separated by spaces.
pub fn quotePaths(gpa: std.mem.Allocator, paths: []const []const u8) ?[]u8 {
    var z: std.ArrayList([*:0]const u8) = .empty;
    defer {
        for (z.items) |p| gpa.free(std.mem.span(p));
        z.deinit(gpa);
    }
    for (paths) |p| z.append(gpa, gpa.dupeZ(u8, p) catch return null) catch return null;
    var out: [*c]u8 = null;
    var len: usize = 0;
    if (cadex.cadex_terminal_quote_paths(@ptrCast(z.items.ptr), z.items.len, &out, &len) != cadex.CADEX_OK or out == null) return null;
    defer cadex.cadex_free(out);
    return gpa.dupe(u8, out[0..len]) catch null;
}

pub fn plan(gpa: std.mem.Allocator, hwnd: c.HWND, session: *Session, confirm_multiline: bool) ?Plan {
    const files = ui_mod.clipboard.readFiles(gpa, hwnd);
    defer {
        for (files) |f| gpa.free(f);
        gpa.free(files);
    }
    if (files.len > 0) {
        const bytes = quotePaths(gpa, files) orelse return null;
        return .{ .bytes = bytes, .as_paste = false, .needs_confirmation = false };
    }
    if (saveClipboardImage(gpa, hwnd)) |path| {
        defer gpa.free(path);
        const bytes = quotePaths(gpa, &.{path}) orelse return null;
        return .{ .bytes = bytes, .as_paste = false, .needs_confirmation = false };
    }
    const text = ui_mod.clipboard.readText(gpa, hwnd) orelse return null;
    if (text.len == 0) {
        gpa.free(text);
        return null;
    }
    const safe = cadex.cadex_terminal_paste_is_safe(session.terminal, text.ptr, text.len);
    return .{ .bytes = text, .as_paste = true, .needs_confirmation = confirm_multiline and !safe };
}

pub fn send(session: *Session, p: Plan) void {
    if (p.as_paste) {
        _ = cadex.cadex_terminal_paste(session.terminal, p.bytes.ptr, p.bytes.len);
    } else {
        session.write(p.bytes);
    }
}

/// A screenshot on the clipboard, written as %TEMP%\cadex-paste\<time>.png;
/// its path, or null when there is no image (or it could not be saved).
fn saveClipboardImage(gpa: std.mem.Allocator, hwnd: c.HWND) ?[]u8 {
    if (c.IsClipboardFormatAvailable(c.CF_BITMAP) == 0) return null;
    if (c.OpenClipboard(hwnd) == 0) return null;
    defer _ = c.CloseClipboard();
    const bitmap = c.GetClipboardData(c.CF_BITMAP) orelse return null;
    const folder = folderPath(gpa) orelse return null;
    defer gpa.free(folder);
    w.files.makeFolder(gpa, folder);
    var now: c.SYSTEMTIME = undefined;
    c.GetLocalTime(&now);
    const path = std.fmt.allocPrint(gpa, "{s}\\cadex-paste-{d:0>4}{d:0>2}{d:0>2}-{d:0>2}{d:0>2}{d:0>2}-{d:0>3}.png", .{
        folder, now.wYear, now.wMonth, now.wDay, now.wHour, now.wMinute, now.wSecond, now.wMilliseconds,
    }) catch return null;
    gfx.wic.savePng(@ptrCast(@alignCast(bitmap)), path, gpa) catch |err| {
        std.log.warn("a imagem colada não foi salva: {s}", .{@errorName(err)});
        gpa.free(path);
        return null;
    };
    return path;
}

fn folderPath(gpa: std.mem.Allocator) ?[]u8 {
    var buf: [c.MAX_PATH + 1]u16 = undefined;
    const n = c.GetTempPathW(buf.len, &buf);
    if (n == 0 or n > buf.len) return null;
    const temp = std.unicode.wtf16LeToWtf8Alloc(gpa, buf[0..n]) catch return null;
    defer gpa.free(temp);
    return std.fmt.allocPrint(gpa, "{s}cadex-paste", .{temp}) catch null;
}

/// Removes pasted images older than 7 days (at app start, as on the Mac).
pub fn cleanOld(gpa: std.mem.Allocator) void {
    const folder = folderPath(gpa) orelse return;
    defer gpa.free(folder);
    const pattern = std.fmt.allocPrint(gpa, "{s}\\*.png", .{folder}) catch return;
    defer gpa.free(pattern);
    const wide = std.unicode.wtf8ToWtf16LeAllocZ(gpa, pattern) catch return;
    defer gpa.free(wide);
    var data: c.WIN32_FIND_DATAW = undefined;
    const find = c.FindFirstFileW(wide.ptr, &data);
    if (find == c.INVALID_HANDLE_VALUE) return;
    defer _ = c.FindClose(find);
    var now: c.FILETIME = undefined;
    c.GetSystemTimeAsFileTime(&now);
    const now_ticks = (@as(u64, now.dwHighDateTime) << 32) | now.dwLowDateTime;
    const week: u64 = 7 * 24 * 3600 * 10_000_000;
    while (true) {
        const t = (@as(u64, data.ftLastWriteTime.dwHighDateTime) << 32) | data.ftLastWriteTime.dwLowDateTime;
        if (now_ticks > t and now_ticks - t > week) {
            const name = std.unicode.wtf16LeToWtf8Alloc(gpa, std.mem.sliceTo(&data.cFileName, 0)) catch break;
            defer gpa.free(name);
            const full = std.fmt.allocPrint(gpa, "{s}\\{s}", .{ folder, name }) catch break;
            defer gpa.free(full);
            const full_w = std.unicode.wtf8ToWtf16LeAllocZ(gpa, full) catch break;
            defer gpa.free(full_w);
            _ = c.DeleteFileW(full_w.ptr);
        }
        if (c.FindNextFileW(find, &data) == 0) break;
    }
}

test {
    @import("win32").refAllDeep(@This());
}
