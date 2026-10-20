//! The editor feature (docs/spec/editor.md): reading code in a pane, with
//! line numbers, fold arrows, the core's colors and the current line
//! (ADR 0006). The markdown feature builds its note editor on the same
//! view, with editing on and its help in Hooks.

const std = @import("std");
const tabs = @import("tabs");

pub const Editor = @import("document.zig").Editor;
pub const Host = @import("document.zig").Host;
pub const View = @import("view.zig").View;
pub const Hooks = @import("view.zig").Hooks;
pub const Underline = @import("view.zig").Underline;
pub const Options = @import("view.zig").Options;
pub const Buffer = @import("buffer.zig").Buffer;
pub const Appearance = @import("appearance.zig").Appearance;
pub const Palette = @import("appearance.zig").Palette;
pub const appearance = @import("appearance.zig");
pub const commands = @import("commands.zig");
pub const file = @import("file.zig");
pub const newline = @import("view_input.zig").newline;

/// A code file in a read-only pane (the tabs' Document).
pub fn open(gpa: std.mem.Allocator, host: Host, path: []const u8) !tabs.Document {
    const e = try Editor.create(gpa, host, path, .{});
    return e.document();
}

/// The file changed on disk: reloads `doc` if it is an editor (also a
/// note), asking first when it has unsaved changes. False for other documents.
pub fn reload(doc: tabs.Document) bool {
    const e = Editor.of(doc) orelse return false;
    e.reload();
    return true;
}

/// Puts the caret on 1-based `line` of `doc`, centered (a search result).
pub fn goToLine(doc: tabs.Document, line: usize) void {
    const e = Editor.of(doc) orelse return;
    if (e.view()) |v| v.goToLine(line);
}

/// The file `doc` shows, when it is an editor.
pub fn pathOf(doc: tabs.Document) ?[]const u8 {
    const e = Editor.of(doc) orelse return null;
    return e.path;
}

test {
    _ = @import("buffer.zig");
    _ = @import("history.zig");
    _ = @import("wrap.zig");
    _ = @import("folding.zig");
    _ = @import("rows.zig");
    _ = @import("syntax.zig");
    _ = @import("file.zig");
    _ = @import("appearance.zig");
    _ = @import("view.zig");
    _ = @import("view_draw.zig");
    _ = @import("view_input.zig");
    _ = @import("find.zig");
    _ = @import("banner.zig");
    _ = @import("document.zig");
    _ = @import("commands.zig");
}

test {
    @import("win32").refAllDeep(@This());
}
