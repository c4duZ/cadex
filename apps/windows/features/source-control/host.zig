//! What source control needs from the app, and nothing more. The app owns
//! the window, the tabs, the palette and the shell's file operations; this
//! feature only asks.

const tabs = @import("tabs");
const palette = @import("command-palette");

pub const Host = struct {
    context: *anyopaque,
    /// Called on a worker thread when git finished something: wake the
    /// window (PostMessage) so the next frame calls SourceControl.frame or
    /// draws the diff. Must only post; it may come shortly after the
    /// owner was destroyed.
    post_redraw: *const fn (context: *anyopaque) void,
    /// Shows a document (a diff). `how`: .normal where the settings say
    /// (the Mac's FileOpener), .beside or .new_tab. The tabs own it then.
    open_document: *const fn (context: *anyopaque, doc: tabs.Document, how: palette.How) void,
    /// Opens a file in the app (the editor, or the viewer of its kind).
    /// Absolute, with Windows separators. `how` as for open_document.
    open_file: *const fn (context: *anyopaque, path: []const u8, how: palette.How) void,
    /// Sends a new, untracked file to the Recycle Bin (IFileOperation with
    /// FOFX_RECYCLEONDELETE, or SHFileOperationW with FOF_ALLOWUNDO), as
    /// "discard" does on the Mac with the Trash. False when it could not.
    trash: *const fn (context: *anyopaque, path: []const u8) bool,
    /// Shows the files selected in File Explorer (SHOpenFolderAndSelectItems).
    reveal: *const fn (context: *anyopaque, paths: []const []const u8) void,
    /// Opens the palette on a list (the branches): the app calls
    /// palette.toggle with it.
    open_palette: *const fn (context: *anyopaque, source: palette.Source) void,
    /// The document in the focused pane, if any (diff.toggle-layout).
    focused_document: *const fn (context: *anyopaque) ?tabs.Document,
};

/// A file's diff to show: the working copy (staged or not) or, with
/// `commit`, the file as that commit changed it (the history asks for it
/// through the app).
pub const DiffRequest = struct {
    /// The repository's top folder, as the core gives it.
    repo: []const u8,
    /// Relative to the repository, as git writes it.
    path: []const u8,
    /// The old name of a rename, or "".
    orig: []const u8 = "",
    staged: bool = false,
    commit: ?[]const u8 = null,
};

test {
    @import("win32").refAllDeep(@This());
}
