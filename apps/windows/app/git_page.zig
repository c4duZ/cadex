//! The sidebar's Git page; the source-control feature draws it once it is
//! wired (plan 12, fase F). Until then a note says so.

const gfx = @import("gfx");
const App = @import("app.zig").App;

pub fn draw(app: *App, area: gfx.Rect) void {
    const u = &app.u;
    u.painter.text("Git: em breve", u.style.ui(), area.inset(u.px(12), u.px(12)), u.style.secondary_text, .{ .vcenter = false });
}

test {
    @import("win32").refAllDeep(@This());
}
