//! The look every widget draws with: the theme's interface colors (filled
//! by the app from the themes feature) and the sizes, in DIPs, scaled by
//! the window's DPI.

const gfx = @import("gfx");
const Color = gfx.Color;

pub const Style = struct {
    /// Title bar, the gaps between panels, status bar.
    chrome: Color = Color.rgb(0x222222),
    /// The rounded panels: sidebar and the terminal area.
    panel: Color = Color.rgb(0x111111),
    panel_border: Color = Color.rgb(0x201e18),
    tab_active: Color = Color.rgb(0x534c45),
    field: Color = Color.rgb(0x2e2e2e),
    text: Color = Color.rgb(0xeeeeee),
    secondary_text: Color = Color.rgb(0xb4b4b4),
    accent: Color = Color.rgb(0xffe0c2),
    dark: bool = true,

    /// Pixels per DIP: 1 at 96 dpi, 1.5 at 144.
    scale: f32 = 1,

    /// The interface font: Segoe UI Variable, which comes with Windows 11.
    font_family: []const u8 = "Segoe UI Variable Text",
    font_size: f32 = 13,
    mono_family: []const u8 = "Cascadia Mono",

    pub fn px(self: Style, dips: f32) f32 {
        return @round(dips * self.scale);
    }

    pub fn font(self: Style, size: f32) gfx.FontSpec {
        return .{ .family = self.font_family, .size = size * self.scale };
    }

    pub fn ui(self: Style) gfx.FontSpec {
        return self.font(self.font_size);
    }

    pub fn small(self: Style) gfx.FontSpec {
        return self.font(self.font_size - 1.5);
    }

    pub fn bold(self: Style) gfx.FontSpec {
        var spec = self.ui();
        spec.weight = .semibold;
        return spec;
    }

    pub fn mono(self: Style, size: f32) gfx.FontSpec {
        return .{ .family = self.mono_family, .size = size * self.scale };
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

test {
    @import("win32").refAllDeep(@This());
}
