//! Entry point of the search feature. Today: fuzzy ranking for the command
//! palette. File and content search come with plan 4.

pub const fuzzy = @import("fuzzy.zig");
pub const rank = @import("rank.zig");

test {
    _ = fuzzy;
    _ = rank;
}
