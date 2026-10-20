//! The entry of the Windows app: opens the window and runs the message
//! loop. Features plug in here in the next phases (docs/plans/10-windows-terminal.md).

const std = @import("std");
const w = @import("win32");
const cadex = @import("cadex");
const window = @import("window.zig");

pub fn main() !void {
    // Proves the core is linked and callable through its C API.
    if (!cadex.cadex_git_available()) w.kernel32.OutputDebugStringW(w.L("Cadex: git not found\n"));
    const hwnd = try window.open();
    _ = w.user32.ShowWindow(hwnd, w.user32.SW_SHOWDEFAULT);
    window.run();
}
