//! The settings feature (docs/spec/settings.md): the user's choices in one
//! file, the same settings.json as the Mac, and (page.zig) the page that
//! edits them.

pub const model = @import("model.zig");
pub const Settings = model.Settings;
pub const Store = @import("store.zig").Store;

test {
    _ = @import("model.zig");
    _ = @import("store.zig");
}
