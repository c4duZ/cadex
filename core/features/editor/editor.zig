//! Entry point of the editor feature: syntax highlighting and folds with
//! tree-sitter (docs/spec/editor.md, docs/adr/0006-editor-reads-code-edits-markdown.md).

pub const ts = @import("ts.zig").c;
pub const languages = @import("languages.zig");
pub const highlight = @import("highlight.zig");
pub const query = @import("query.zig");
pub const document = @import("document.zig");
pub const Document = document.Document;
pub const folds = @import("folds.zig");

test {
    _ = languages;
    _ = highlight;
    _ = query;
    _ = document;
}
