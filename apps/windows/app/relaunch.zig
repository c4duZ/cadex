//! "Reopen now" after the language changed (docs/adr/0015-english-default-
//! two-languages.md): the window closes as usual (asking over running
//! programs, saving the spaces), and once the app has left its loop, main
//! starts Cadex.exe again. A refused close leaves the request off.

const w = @import("win32");
const App = @import("app.zig").App;

const c = w.c;

var requested = false;

pub fn request(app: *App) void {
    requested = true;
    _ = c.PostMessageW(app.window.hwnd, c.WM_CLOSE, 0, 0);
}

/// The close was cancelled (the quit question answered no).
pub fn cancel() void {
    requested = false;
}

/// From main, after the window's loop ended.
pub fn openAgainIfAsked() void {
    if (!requested) return;
    var path: [c.MAX_PATH + 1]u16 = undefined;
    const n = c.GetModuleFileNameW(null, &path, path.len);
    if (n == 0) return;
    path[n] = 0;
    _ = c.ShellExecuteW(null, w.L("open"), &path, null, null, c.SW_SHOWNORMAL);
}

test {
    @import("win32").refAllDeep(@This());
}
