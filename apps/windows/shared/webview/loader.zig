//! Finding WebView2 (docs/adr/0014-webview2-on-windows.md): Microsoft's
//! WebView2Loader.dll, shipped next to Cadex.exe, finds the Evergreen
//! runtime every Windows 11 has. It is loaded on the first web pane, not
//! linked: without it the terminal still opens, and the pane says why.
//! The static loader needs the MSVC runtime (thread-safe statics, /GS,
//! CFG), and the runtime's own DLL exports only undocumented entry points.

const std = @import("std");
const w = @import("win32");
const c = w.c;

pub const CreateEnvironment = *const fn (
    browser_folder: ?[*:0]const u16,
    user_data_folder: ?[*:0]const u16,
    options: ?*anyopaque,
    handler: *c.ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler,
) callconv(.winapi) c.HRESULT;

pub const Error = error{ LoaderMissing, NoEntryPoint };

extern "kernel32" fn LoadLibraryExW(name: [*:0]const u16, file: ?*anyopaque, flags: c.DWORD) callconv(.winapi) c.HMODULE;
extern "kernel32" fn GetProcAddress(module: c.HMODULE, name: [*:0]const u8) callconv(.winapi) ?*const anyopaque;

/// Only the exe's own folder: a WebView2Loader.dll planted in the current
/// folder or on the PATH is never picked (DLL search order hijacking).
const LOAD_LIBRARY_SEARCH_APPLICATION_DIR: c.DWORD = 0x200;

var cached: ?CreateEnvironment = null;

pub fn load() Error!CreateEnvironment {
    if (cached) |f| return f;
    const module = LoadLibraryExW(w.L("WebView2Loader.dll"), null, LOAD_LIBRARY_SEARCH_APPLICATION_DIR) orelse return error.LoaderMissing;
    const f = GetProcAddress(module, "CreateCoreWebView2EnvironmentWithOptions") orelse return error.NoEntryPoint;
    cached = @ptrCast(@alignCast(f));
    return cached.?;
}

/// %LOCALAPPDATA%\Cadex\WebView2: the runtime keeps its profile there
/// (cache, and the cookies of pages outside private mode). Without it,
/// WebView2 would write next to the exe, which may be read-only.
pub fn userDataFolder(gpa: std.mem.Allocator) ![:0]u16 {
    var buf: [1024]u16 = undefined;
    const n = c.GetEnvironmentVariableW(w.L("LOCALAPPDATA"), &buf, buf.len);
    if (n == 0 or n >= buf.len) return error.NoLocalAppData;
    const tail = std.unicode.utf8ToUtf16LeStringLiteral("\\Cadex\\WebView2");
    const out = try gpa.allocSentinel(u16, n + tail.len, 0);
    @memcpy(out[0..n], buf[0..n]);
    @memcpy(out[n..], tail);
    return out;
}

/// What the pane says when WebView2 does not start, in Portuguese.
pub fn failureMessage(err: anyerror, hr: c.HRESULT) []const u8 {
    if (err == error.LoaderMissing or err == error.NoEntryPoint) return "WebView2Loader.dll não está ao lado do Cadex.exe";
    const code: u32 = @bitCast(hr);
    return switch (code) {
        // HRESULT_FROM_WIN32(ERROR_FILE_NOT_FOUND): no runtime installed.
        0x80070002 => "O WebView2 Runtime não está instalado (baixe em go.microsoft.com/fwlink/p/?LinkId=2124703)",
        // E_ACCESSDENIED: the profile folder cannot be written.
        0x80070005 => "Sem permissão na pasta do WebView2 em %LOCALAPPDATA%\\Cadex",
        // HRESULT_FROM_WIN32(ERROR_INVALID_STATE): another app's settings on the same profile.
        0x8007139f => "O WebView2 já está aberto com outras opções",
        else => "Não foi possível iniciar o WebView2",
    };
}

test "messages for the known failures" {
    try std.testing.expectEqualStrings("WebView2Loader.dll não está ao lado do Cadex.exe", failureMessage(error.LoaderMissing, 0));
    const missing: c.HRESULT = @bitCast(@as(u32, 0x80070002));
    try std.testing.expect(std.mem.indexOf(u8, failureMessage(error.ComFailed, missing), "Runtime") != null);
}

test {
    @import("win32").refAllDeep(@This());
}
