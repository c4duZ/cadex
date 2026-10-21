//! The look every widget draws with: the theme's interface colors (filled
//! by the app from the themes feature) and the sizes, in DIPs, scaled by
//! the window's DPI and the interface's zoom (plan 15, phase D: zoom,
//! density and font apart from the terminal's, set when Cadex opens).

const gfx = @import("gfx");
const Color = gfx.Color;

pub const Style = struct {
    /// Title bar, the gaps between panels, status bar.
    chrome: Color = Color.rgb(0x222222),
    /// The rounded panels: sidebar and the terminal area.
    panel: Color = Color.rgb(0x111111),
    panel_border: Color = Color.rgb(0x201e18),
    tab_active: Color = Color.rgb(0x534c45),
    /// Text over tab_active: the theme's, or black or white when an accent
    /// made the fill too close to it (plan 15, phase B).
    tab_active_text: Color = Color.rgb(0xeeeeee),
    field: Color = Color.rgb(0x2e2e2e),
    text: Color = Color.rgb(0xeeeeee),
    secondary_text: Color = Color.rgb(0xb4b4b4),
    accent: Color = Color.rgb(0xffe0c2),
    dark: bool = true,

    /// Pixels per DIP of the interface: the window's (1 at 96 dpi, 1.5 at
    /// 144) times the zoom (appearance.uiZoom).
    scale: f32 = 1,
    /// Pixels per DIP of the window alone, for what the zoom leaves out:
    /// the terminal and the code of the editor keep their own font size.
    window_scale: f32 = 1,
    /// Row heights: 1, or 0.85 in compact density (about what Zed's
    /// compact mode takes off a row, as the Mac's UILooks).
    density: f32 = 1,

    /// The interface font (appearance.uiFont): Segoe UI Variable, which
    /// comes with Windows 11, unless the user picked another.
    font_family: []const u8 = "Segoe UI Variable Text",
    /// The base text size (appearance.uiFontSize); every font grows with it
    /// from the 13 the design was drawn at.
    font_size: f32 = design_font_size,
    mono_family: []const u8 = "Cascadia Mono",

    pub const design_font_size = 13;

    pub fn px(self: Style, dips: f32) f32 {
        return @round(dips * self.scale);
    }

    /// A row's or bar's height: zoomed, and tighter when compact; whole
    /// pixels so the lines between rows stay crisp.
    pub fn rowPx(self: Style, dips: f32) f32 {
        return @round(dips * self.scale * self.density);
    }

    /// The interface font at a design size, grown by the zoom and the
    /// chosen base size.
    pub fn font(self: Style, size: f32) gfx.FontSpec {
        return .{ .family = self.font_family, .size = size * self.scale * self.font_size / design_font_size };
    }

    pub fn ui(self: Style) gfx.FontSpec {
        return self.font(design_font_size);
    }

    pub fn small(self: Style) gfx.FontSpec {
        return self.font(design_font_size - 1.5);
    }

    pub fn bold(self: Style) gfx.FontSpec {
        var spec = self.ui();
        spec.weight = .semibold;
        return spec;
    }

    /// Short code in the interface (a sha, a status letter), scaled like the rest.
    pub fn mono(self: Style, size: f32) gfx.FontSpec {
        return .{ .family = self.mono_family, .size = size * self.scale * self.font_size / design_font_size };
    }

    /// A hovered row or button: the text color, faint.
    pub fn hover(self: Style) Color {
        return self.text.alpha(if (self.dark) 0.08 else 0.06);
    }

    pub fn pressed(self: Style) Color {
        return self.text.alpha(if (self.dark) 0.14 else 0.11);
    }

    pub fn selection(self: Style) Color {
        return self.accent.alpha(0.28);
    }

    pub fn separator(self: Style) Color {
        return self.panel_border;
    }
};

test "zoom, base size and density as the Mac's UILooks" {
    const plain: Style = .{};
    try @import("std").testing.expectEqual(@as(f32, 13), plain.ui().size);
    try @import("std").testing.expectEqual(@as(f32, 22), plain.rowPx(22));
    const zoomed: Style = .{ .scale = 1.25, .density = 0.85, .font_size = 13 };
    try @import("std").testing.expectEqual(@as(f32, 16.25), zoomed.ui().size);
    try @import("std").testing.expectEqual(@as(f32, 48), zoomed.px(38));
    const compact: Style = .{ .density = 0.85 };
    try @import("std").testing.expectEqual(@as(f32, 17), compact.rowPx(20));
    try @import("std").testing.expectEqual(@as(f32, 20), compact.px(20));
}

test {
    @import("win32").refAllDeep(@This());
}
