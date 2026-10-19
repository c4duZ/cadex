//! Entry point of the markdown feature: the rendered HTML and the index of
//! headings and links (docs/spec/markdown.md, docs/adr/0010-markdown-rendering.md).

pub const anchor = @import("anchor.zig");
pub const html = @import("html.zig");
pub const sanitize = @import("sanitize.zig");
pub const outline = @import("outline.zig");
pub const resolve = @import("resolve.zig");
pub const Index = @import("index.zig").Index;
pub const queries = @import("queries.zig");

test {
    _ = anchor;
    _ = html;
    _ = sanitize;
    _ = outline;
    _ = resolve;
    _ = @import("index.zig");
}
