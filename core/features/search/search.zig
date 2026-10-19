//! Entry point of the search feature: fuzzy ranking (command palette and
//! ⌘P), the workspace's file names in memory, and content search (⌘⇧F).
//! docs/spec/search.md.

pub const fuzzy = @import("fuzzy.zig");
pub const rank = @import("rank.zig");
pub const files = @import("files.zig");
pub const Index = @import("index.zig").Index;
pub const content = @import("content.zig");
pub const walker = @import("walker.zig");

test {
    _ = fuzzy;
    _ = rank;
    _ = files;
    _ = @import("index.zig");
    _ = content;
    _ = walker;
}
