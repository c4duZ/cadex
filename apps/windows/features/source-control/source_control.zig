//! The source-control feature (docs/spec/source-control.md): the Git page
//! of the sidebar and the diff document. The app makes one SourceControl
//! with a Host, registers the commands, tells it the folder and the disk
//! changes, calls frame() every frame and draw() where the page shows.

const ui = @import("ui");
const gfx = @import("gfx");
const controller = @import("controller.zig");
const panel = @import("panel.zig");

pub const SourceControl = controller.SourceControl;
pub const State = controller.State;
pub const Host = @import("host.zig").Host;
pub const DiffRequest = @import("host.zig").DiffRequest;
pub const DiffDocument = @import("diff_document.zig").DiffDocument;
pub const register = @import("commands.zig").register;

/// Draws the Git page in `area` (the sidebar's) and handles its input.
pub fn draw(sc: *SourceControl, u: *ui.Ui, area: gfx.Rect) void {
    panel.draw(sc, u, area);
}

test {
    _ = @import("status.zig");
    _ = @import("selection.zig");
    _ = @import("repository.zig");
    _ = @import("worker.zig");
    _ = @import("jobs.zig");
    _ = @import("host.zig");
    _ = @import("controller.zig");
    _ = @import("question.zig");
    _ = @import("branches.zig");
    _ = @import("panel.zig");
    _ = @import("change_list.zig");
    _ = @import("opening.zig");
    _ = @import("commands.zig");
    _ = @import("diff_lines.zig");
    _ = @import("diff_document.zig");
    _ = @import("diff_view.zig");
}

test {
    @import("win32").refAllDeep(@This());
}
