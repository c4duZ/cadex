//! The tabs feature (docs/spec/tabs.md): tabs in the title bar, each split
//! into panes holding a terminal or a document, closing that asks, and
//! the snapshot the spaces save.

pub const Tabs = @import("controller.zig").Tabs;
pub const Host = @import("controller.zig").Host;
pub const OpenFiles = @import("controller.zig").OpenFiles;
pub const Question = @import("controller.zig").Question;
pub const Tab = @import("tab.zig").Tab;
pub const Pane = @import("tab.zig").Pane;
pub const Document = @import("document.zig").Document;
pub const Bar = @import("bar.zig").Bar;
pub const Layout = @import("layout.zig").Layout;
pub const commands = @import("commands.zig");
pub const snapshot = @import("snapshot.zig");
pub const pane_tree = @import("pane_tree.zig");
pub const folderTitle = @import("tab_list.zig").folderTitle;

test {
    _ = @import("pane_tree.zig");
    _ = @import("tab_list.zig");
    _ = @import("document.zig");
    _ = @import("tab.zig");
    _ = @import("controller.zig");
    _ = @import("bar.zig");
    _ = @import("layout.zig");
    _ = @import("commands.zig");
    _ = @import("snapshot.zig");
}
