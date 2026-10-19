//! The tree-sitter C API, imported once for the editor feature (and, through
//! the entry point, the markdown feature).

pub const c = @cImport(@cInclude("tree_sitter/api.h"));
