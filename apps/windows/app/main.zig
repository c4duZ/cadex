//! The entry of the Windows app: makes the app and opens its window in the
//! folder given on the command line (`Cadex.exe C:\code\x`), else in the
//! user's folder (docs/spec/workspace.md).

const std = @import("std");
const w = @import("win32");
const App = @import("app.zig").App;

pub fn main() !void {
    const gpa = std.heap.c_allocator;
    const app = try App.create(gpa);
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const folder = launchFolder(arena.allocator());
    // CADEX_BACKGROUND=1 shows the window without taking the focus (tests).
    var flag: [4]u16 = undefined;
    const background = w.c.GetEnvironmentVariableW(w.L("CADEX_BACKGROUND"), &flag, flag.len) > 0;
    app.start(folder, background);
    // "Reopen now" after the language changed: the window closed as usual.
    @import("relaunch.zig").openAgainIfAsked();
}

/// The first argument, when it is a folder.
fn launchFolder(a: std.mem.Allocator) ?[]const u8 {
    const line = w.c.GetCommandLineW();
    var count: c_int = 0;
    const args = w.c.CommandLineToArgvW(line, &count);
    if (args == null or count < 2) return null;
    defer _ = w.c.LocalFree(@ptrCast(args));
    const first = std.unicode.wtf16LeToWtf8Alloc(a, std.mem.span(args[1])) catch return null;
    const wide = std.unicode.wtf8ToWtf16LeAllocZ(a, first) catch return null;
    const attrs = w.c.GetFileAttributesW(wide.ptr);
    if (attrs == w.c.INVALID_FILE_ATTRIBUTES or attrs & w.c.FILE_ATTRIBUTE_DIRECTORY == 0) return null;
    return first;
}

test {
    w.refAllDeep(@This());
    _ = @import("app.zig");
    _ = @import("window.zig");
    _ = @import("window_messages.zig");
    _ = @import("chrome.zig");
    _ = @import("wiring.zig");
    _ = @import("app_commands.zig");
    _ = @import("settings_page.zig");
    _ = @import("settings_rows.zig");
    _ = @import("relaunch.zig");
    _ = @import("sidebar.zig");
    _ = @import("git_page.zig");
    _ = @import("opener.zig");
    _ = @import("environments.zig");
    _ = @import("space_ui.zig");
    _ = @import("places_source.zig");
    _ = @import("themes_page.zig");
    _ = @import("theme_commands.zig");
    _ = @import("theme_looks.zig");
    _ = @import("looks.zig");
    _ = @import("work_colors.zig");
    _ = @import("interface_rows.zig");
    _ = @import("terminal_text_rows.zig");
}
