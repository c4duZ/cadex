//! The Terminal page's reading rows (plan 15, phase C), as the Mac's
//! TerminalTextRows.swift: minimum contrast, line height, letter spacing,
//! ligatures and the font's other OpenType features. The terminal redraws
//! with them at once.

const std = @import("std");
const gfx = @import("gfx");
const ui = @import("ui");
const strings = @import("strings");
const settings = @import("settings");
const App = @import("app.zig").App;
const page = @import("settings_page.zig");

const t = strings.t;
const model = settings.model;

/// The two features that join ligatures; the toggle adds or removes both.
const ligatures = [_][]const u8{ "calt", "liga" };
const max_features = 16;

var features_text: ui.TextBuffer = .{};
var features_scroll: ui.text_field.Scroll = .{};

/// The field starts with the saved features (but the ligatures) when the page opens.
pub fn prepare(app: *App) void {
    var buf: [256]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    for (others(app.settings.current.terminal.font_features), 0..) |f, i| {
        if (i > 0) w.writeAll(", ") catch break;
        w.writeAll(f) catch break;
    }
    features_text.set(app.gpa, w.buffered()) catch {};
}

fn isLigature(f: []const u8) bool {
    for (ligatures) |l| if (std.mem.eql(u8, l, f)) return true;
    return false;
}

fn ligaturesOn(features: []const []const u8) bool {
    for (ligatures) |l| {
        for (features) |f| {
            if (std.mem.eql(u8, f, l)) break;
        } else return false;
    }
    return true;
}

/// The features but calt and liga, at most `max_features`.
fn others(features: []const []const u8) []const []const u8 {
    const S = struct {
        var buf: [max_features][]const u8 = undefined;
    };
    var n: usize = 0;
    for (features) |f| if (!isLigature(f) and n < max_features) {
        S.buf[n] = f;
        n += 1;
    };
    return S.buf[0..n];
}

/// terminal.toggle-ligatures and the row's switch.
pub fn toggleLigatures(app: *App) void {
    setLigatures(app, !ligaturesOn(app.settings.current.terminal.font_features));
}

fn setLigatures(app: *App, on: bool) void {
    var s = app.settings.current;
    var list: [max_features + 2][]const u8 = undefined;
    var n: usize = 0;
    if (on) for (ligatures) |l| {
        list[n] = l;
        n += 1;
    };
    for (others(s.terminal.font_features)) |f| {
        list[n] = f;
        n += 1;
    }
    s.terminal.font_features = list[0..n];
    page.commit(app, s);
}

/// The field's "ss01, zero, -liga": the valid tags after the ligatures.
fn setOthers(app: *App, text: []const u8) void {
    var s = app.settings.current;
    var list: [max_features + 2][]const u8 = undefined;
    var n: usize = 0;
    for (s.terminal.font_features) |f| if (isLigature(f)) {
        list[n] = f;
        n += 1;
    };
    var it = std.mem.tokenizeScalar(u8, text, ',');
    while (it.next()) |raw| {
        const f = std.mem.trim(u8, raw, " ");
        if (!model.isFontFeature(f) or n == list.len) continue;
        list[n] = f;
        n += 1;
    }
    s.terminal.font_features = list[0..n];
    page.commit(app, s);
}

fn rounded(v: f64, step: f64) f64 {
    return @round(v / step) * step;
}

pub fn draw(app: *App, area: *gfx.Rect) void {
    const u = &app.u;
    var s = app.settings.current;
    page.heading(u, area, t("Reading", "Leitura"));
    if (page.stepper(u, page.row(u, area, t("Minimum contrast", "Contraste mínimo"), t("Text a program colors too close to its background is moved toward white or black until it reads. 1 leaves the colors alone; 4.5 is the usual minimum for text, 7 is high contrast.", "Texto que um programa pinta perto demais do fundo vai para o branco ou o preto até dar para ler. 1 deixa as cores como estão; 4,5 é o mínimo usual para texto, 7 é alto contraste.")), 40, s.terminal.minimum_contrast, 0.5, ":1")) |v| {
        s.terminal.minimum_contrast = std.math.clamp(rounded(v, 0.5), model.contrast_range[0], model.contrast_range[1]);
        page.commit(app, s);
    }
    if (page.stepper(u, page.row(u, area, t("Line height", "Altura da linha"), t("Space between lines, as a multiple of the font's own.", "O espaço entre as linhas, em vezes o da própria fonte.")), 41, s.terminal.line_height, 0.05, "×")) |v| {
        s.terminal.line_height = std.math.clamp(rounded(v, 0.05), model.line_heights[0], model.line_heights[1]);
        page.commit(app, s);
    }
    if (page.stepper(u, page.row(u, area, t("Letter spacing", "Espaçamento entre letras"), t("Extra space between letters, in points. Below zero brings them closer.", "Espaço a mais entre as letras, em pontos. Abaixo de zero aproxima.")), 42, s.terminal.letter_spacing, 0.25, " pt")) |v| {
        s.terminal.letter_spacing = std.math.clamp(rounded(v, 0.25), model.letter_spacings[0], model.letter_spacings[1]);
        page.commit(app, s);
    }
    if (ui.widgets.toggle(u, ui.id("settings.ligatures", 0), page.row(u, area, t("Ligatures", "Ligaduras"), t("With a font that has them, such as Fira Code or JetBrains Mono, -> and != join into one sign.", "Com uma fonte que as tem, como Fira Code ou JetBrains Mono, -> e != viram um sinal só.")), ligaturesOn(s.terminal.font_features))) |v| setLigatures(app, v);
    const r = page.row(u, area, t("Font features", "Recursos da fonte"), t("OpenType features, separated by commas: ss01 for a stylistic set, zero for a slashed zero, -liga to turn one off.", "Recursos OpenType, separados por vírgula: ss01 para um conjunto de estilo, zero para o zero cortado, -liga para desligar um."));
    const res = ui.text_field.textField(u, ui.id("settings.font-features", 0), r.inset(0, u.px(4)), &features_text, &features_scroll, .{ .placeholder = "ss01, zero" });
    if (res.submitted) setOthers(app, features_text.text());
}

test "ligatures on means both calt and liga" {
    try std.testing.expect(ligaturesOn(&.{ "liga", "ss01", "calt" }));
    try std.testing.expect(!ligaturesOn(&.{"calt"}));
    try std.testing.expectEqual(@as(usize, 1), others(&.{ "calt", "zero", "liga" }).len);
}

test {
    @import("win32").refAllDeep(@This());
}
