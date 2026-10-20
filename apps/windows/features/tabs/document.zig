//! What a non-terminal pane shows: code, Markdown, an image, a web page, a
//! diff, the git history. The feature that owns it implements this; the
//! tabs only place, title, focus and close it (the Mac's TabDocument).

const std = @import("std");
const gfx = @import("gfx");
const ui = @import("ui");

pub const Document = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        /// The tab's title ("render.zig").
        title: *const fn (ptr: *anyopaque) []const u8,
        /// What makes two documents the same (the file path, "history:<repo>"):
        /// opening it again goes to the pane that shows it.
        identity: *const fn (ptr: *anyopaque) []const u8,
        icon: *const fn (ptr: *anyopaque) u21,
        icon_color: ?*const fn (ptr: *anyopaque) ?gfx.Color = null,
        /// A dot in the title, and closing asks first.
        unsaved: *const fn (ptr: *anyopaque) bool,
        /// Draws in `area` and handles the input of this frame there.
        draw: *const fn (ptr: *anyopaque, u: *ui.Ui, area: gfx.Rect, focused: bool) void,
        /// The id the window gives the keyboard to when the pane has the focus.
        focus_id: *const fn (ptr: *anyopaque) ui.Id,
        /// Saves; false when it could not (the close then stops).
        save: ?*const fn (ptr: *anyopaque) bool = null,
        /// The folder a terminal opened beside it starts in (the file's).
        folder: ?*const fn (ptr: *anyopaque) ?[]const u8 = null,
        /// Copy, paste, select all, find, undo, redo from the edit.* commands;
        /// false when the document has nothing to do with it.
        edit: ?*const fn (ptr: *anyopaque, u: *ui.Ui, action: EditAction) bool = null,
        /// The pane is gone: stop watching, free everything.
        destroy: *const fn (ptr: *anyopaque) void,
    };

    pub const EditAction = enum { copy, cut, paste, select_all, find, undo, redo };

    pub fn title(self: Document) []const u8 {
        return self.vtable.title(self.ptr);
    }
    pub fn identity(self: Document) []const u8 {
        return self.vtable.identity(self.ptr);
    }
    pub fn icon(self: Document) u21 {
        return self.vtable.icon(self.ptr);
    }
    pub fn iconColor(self: Document) ?gfx.Color {
        return if (self.vtable.icon_color) |f| f(self.ptr) else null;
    }
    pub fn unsaved(self: Document) bool {
        return self.vtable.unsaved(self.ptr);
    }
    pub fn draw(self: Document, u: *ui.Ui, area: gfx.Rect, focused: bool) void {
        self.vtable.draw(self.ptr, u, area, focused);
    }
    pub fn focusId(self: Document) ui.Id {
        return self.vtable.focus_id(self.ptr);
    }
    pub fn save(self: Document) bool {
        return if (self.vtable.save) |f| f(self.ptr) else true;
    }
    pub fn folder(self: Document) ?[]const u8 {
        return if (self.vtable.folder) |f| f(self.ptr) else null;
    }
    pub fn edit(self: Document, u: *ui.Ui, action: EditAction) bool {
        return if (self.vtable.edit) |f| f(self.ptr, u, action) else false;
    }
    pub fn destroy(self: Document) void {
        self.vtable.destroy(self.ptr);
    }
};

test {
    std.testing.refAllDecls(@This());
}
