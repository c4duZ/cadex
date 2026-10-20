//! The editor's commands (ADR 0005), the Mac's ids, titles and keys
//! (apps/macos/features/editor/EditorCommands.swift), acting on the editor
//! with the keyboard. edit.find (find in the file) is the app's, which
//! calls the document's edit(.find).

const palette = @import("command-palette");
const strings = @import("strings");
const document = @import("document.zig");

const Editor = document.Editor;

var host: document.Host = undefined;

fn focused() ?*Editor {
    const doc = host.focused_document(host.context) orelse return null;
    return Editor.of(doc);
}

fn hasEditor(_: ?*anyopaque) bool {
    return focused() != null;
}

fn hasEditable(_: ?*anyopaque) bool {
    const e = focused() orelse return false;
    return e.editable;
}

fn save(_: ?*anyopaque) void {
    if (focused()) |e| _ = e.save();
}

fn foldAll(_: ?*anyopaque) void {
    if (focused()) |e| if (e.view()) |v| v.foldAll();
}

fn unfoldAll(_: ?*anyopaque) void {
    if (focused()) |e| if (e.view()) |v| v.unfoldAll();
}

pub fn register(registry: *palette.Registry, where: document.Host) void {
    host = where;
    // Code is read-only here (ADR 0006): saving is for the notes.
    registry.add(.{ .id = "editor.save", .title = strings.t("Save File", "Salvar arquivo"), .keywords = &.{ "save", "gravar" }, .shortcut = "cmd+s", .run = save, .available = hasEditable });
    registry.add(.{ .id = "editor.fold-all", .title = strings.t("Fold All Blocks", "Dobrar todos os blocos"), .keywords = &.{ "fold", "recolher" }, .run = foldAll, .available = hasEditor });
    registry.add(.{ .id = "editor.unfold-all", .title = strings.t("Unfold All Blocks", "Desdobrar todos os blocos"), .keywords = &.{ "unfold", "expandir" }, .run = unfoldAll, .available = hasEditor });
}

test {
    @import("win32").refAllDeep(@This());
}
