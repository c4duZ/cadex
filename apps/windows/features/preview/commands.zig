//! The preview's commands (ADR 0005), the Mac's ids, titles and keys
//! (apps/macos/features/preview/PreviewCommands.swift). Reload, back and
//! forward act on the preview of the focused pane; without one, Ctrl+R
//! goes on to the focused view.

const palette = @import("command-palette");
const tabs = @import("tabs");
const Preview = @import("document.zig").Preview;

/// Where the commands find the preview and open a new one.
pub const Current = struct {
    context: *anyopaque,
    /// The document of the focused pane, if it is not a terminal.
    focused: *const fn (context: *anyopaque) ?tabs.Document,
    /// A preview tab for `url` ("" for a blank one with the address ready),
    /// where the settings say (.normal), beside or in a new tab.
    open: *const fn (context: *anyopaque, url: []const u8, how: palette.How) void,
};

var current: Current = undefined;

fn active() ?*Preview {
    const doc = current.focused(current.context) orelse return null;
    return Preview.of(doc);
}

fn hasPreview(_: ?*anyopaque) bool {
    return active() != null;
}

fn open(_: ?*anyopaque) void {
    current.open(current.context, "", .normal);
}
fn openInTab(_: ?*anyopaque) void {
    current.open(current.context, "", .new_tab);
}
fn reload(_: ?*anyopaque) void {
    if (active()) |p| p.reload();
}
fn back(_: ?*anyopaque) void {
    if (active()) |p| p.goBack();
}
fn forward(_: ?*anyopaque) void {
    if (active()) |p| p.goForward();
}

pub fn register(registry: *palette.Registry, where: Current) void {
    current = where;
    registry.add(.{ .id = "preview.open", .title = "Abrir preview web", .keywords = &.{ "browser", "navegador", "localhost", "site" }, .run = open });
    registry.add(.{ .id = "preview.open-in-tab", .title = "Abrir preview web em nova aba", .keywords = &.{ "browser", "navegador", "localhost", "site", "aba" }, .run = openInTab });
    registry.add(.{ .id = "preview.reload", .title = "Recarregar o preview", .keywords = &.{ "reload", "atualizar" }, .shortcut = "cmd+r", .run = reload, .available = hasPreview });
    registry.add(.{ .id = "preview.back", .title = "Voltar no preview", .keywords = &.{ "back", "anterior" }, .run = back, .available = hasPreview });
    registry.add(.{ .id = "preview.forward", .title = "Avançar no preview", .keywords = &.{ "forward", "próxima" }, .run = forward, .available = hasPreview });
}

test {
    @import("win32").refAllDeep(@This());
}
