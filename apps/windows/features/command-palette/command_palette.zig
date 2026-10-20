//! The command-palette feature (docs/spec/command-palette.md): the registry
//! every action goes through, and the palette that finds and runs them.

pub const Registry = @import("registry.zig").Registry;
pub const Command = @import("registry.zig").Command;
pub const sections = @import("registry.zig").sections;
pub const sectionOf = @import("registry.zig").sectionOf;
pub const sectionTitle = @import("registry.zig").sectionTitle;
pub const Source = @import("source.zig").Source;
pub const Item = @import("source.zig").Item;
pub const How = @import("source.zig").How;
pub const rank = @import("source.zig").rank;
pub const Commands = @import("commands.zig").Commands;
pub const Pin = @import("commands.zig").Pin;
pub const Palette = @import("palette.zig").Palette;
pub const Prefix = @import("palette.zig").Prefix;
pub const Pending = @import("palette.zig").Pending;

test {
    _ = @import("registry.zig");
    _ = @import("source.zig");
    _ = @import("commands.zig");
    _ = @import("palette.zig");
}
