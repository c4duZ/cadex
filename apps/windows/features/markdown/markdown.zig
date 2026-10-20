//! The markdown feature (docs/spec/markdown.md): writing the project's
//! notes with links that work between files (ADR 0006). A note is an
//! editable editor pane with the help of session.zig; the rendered page
//! is the preview's document, asked for through Host.show_rendered.

pub const Markdown = @import("controller.zig").Markdown;
pub const Host = @import("controller.zig").Host;
pub const Session = @import("session.zig").Session;
pub const commands = @import("commands.zig");
pub const isMarkdown = Markdown.isMarkdown;

test {
    _ = @import("index.zig");
    _ = @import("trigger.zig");
    _ = @import("lists.zig");
    _ = @import("completion.zig");
    _ = @import("session.zig");
    _ = @import("backlinks.zig");
    _ = @import("controller.zig");
    _ = @import("commands.zig");
}

test {
    @import("win32").refAllDeep(@This());
}
