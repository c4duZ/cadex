//! The spaces' questions over the window: the name for space.rename, and
//! the one question closing the window asks for every space.

const std = @import("std");
const gfx = @import("gfx");
const ui = @import("ui");
const App = @import("app.zig").App;
const wiring = @import("wiring.zig");

pub fn draw(app: *App) void {
    const u = &app.u;
    if (app.space_rename) |*buffer| {
        const full: gfx.Rect = .{ .w = u.size.x, .h = u.size.y };
        u.beginOverlay(full);
        defer u.endOverlay();
        u.painter.fill(full, gfx.Color.black.alpha(0.3));
        const box: gfx.Rect = .{ .x = (u.size.x - u.px(360)) / 2, .y = u.size.y * 0.3, .w = u.px(360), .h = u.px(96) };
        u.painter.fillRounded(box.inset(-1, -1), u.px(10), u.style.panel_border);
        u.painter.fillRounded(box, u.px(10), u.style.panel);
        var inner = box.inset(u.px(16), u.px(14));
        u.painter.text("Renomear space", u.style.bold(), inner.takeTop(u.px(24)), u.style.text, .{});
        const res = ui.text_field.textField(u, ui.id("space.rename", 0), inner.takeTop(u.px(32)), buffer, &app.space_rename_scroll, .{ .autofocus = true });
        if (res.submitted) app.spaces.rename(buffer.text());
        if (res.submitted or res.cancelled) {
            buffer.deinit(app.gpa);
            app.space_rename = null;
            u.focus = ui.context.none;
        }
    }
    if (app.quit_question) |q| {
        const buttons: []const []const u8 = if (q.unsaved) &.{ "Salvar e sair", "Sair sem salvar", "Cancelar" } else &.{ "Sair", "Cancelar" };
        const title = if (q.unsaved) "Há arquivos não salvos" else "Há programas rodando nos terminais";
        if (ui.menu.ask(u, .{ .title = title, .message = "Sair do Cadex encerra todos os spaces.", .buttons = buttons })) |choice| {
            app.quit_question = null;
            const cancel = choice == buttons.len - 1;
            if (!cancel) {
                if (q.unsaved and choice == 0) for (app.spaces.list.items) |s| {
                    _ = s.tabs.saveAll(.all);
                };
                wiring.quitNow(app);
            }
        }
    }
}

test {
    @import("win32").refAllDeep(@This());
}
