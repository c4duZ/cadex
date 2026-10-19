//! Entry point of the explorer feature: list, read and change files inside
//! the authorized directories, and watch folders for changes
//! (docs/spec/explorer.md).

pub const Error = @import("errors.zig").Error;
pub const listing = @import("listing.zig");
pub const operations = @import("operations.zig");
pub const read = @import("read.zig");
pub const write = @import("write.zig");
pub const watch = @import("watch.zig");
pub const natural = @import("natural.zig");

test {
    _ = listing;
    _ = operations;
    _ = read;
    _ = write;
    _ = watch;
    _ = natural;
}
