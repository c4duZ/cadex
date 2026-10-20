//! What the history needs from the app, and nothing more. It does not
//! import source control (the Mac's rule): the Git page's repository and
//! the commit's diff come through here.

const tabs = @import("tabs");
const palette = @import("command-palette");

pub const Host = struct {
    context: *anyopaque,
    /// Called on a worker thread when git finished something: wake the
    /// window (PostMessage) so the next frame draws the history. Must only
    /// post; it may come shortly after a document was destroyed.
    post_redraw: *const fn (context: *anyopaque) void,
    /// Shows a document (the history). `how`: .normal where the settings
    /// say, .beside or .new_tab. The tabs own it then.
    open_document: *const fn (context: *anyopaque, doc: tabs.Document, how: palette.How) void,
    /// The document in the focused pane, if any (the history.* commands).
    focused_document: *const fn (context: *anyopaque) ?tabs.Document,
    /// The Git page's repository (SourceControl.repositoryRoot), or null;
    /// valid during the call.
    repository: *const fn (context: *anyopaque) ?[]const u8,
    /// A file of a commit was clicked: open source control's diff of it
    /// (DiffDocument.create with .commit = sha). Valid during the call.
    open_commit_diff: *const fn (context: *anyopaque, repo: []const u8, sha: []const u8, path: []const u8, orig: []const u8) void,
};

test {
    @import("win32").refAllDeep(@This());
}
