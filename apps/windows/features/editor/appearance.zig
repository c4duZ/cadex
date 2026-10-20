//! How every code view looks: the font and the colors, filled by the app
//! from the theme and the terminal font (this feature does not depend on
//! themes), as the Mac's EditorAppearance. Immediate mode reads it every
//! frame, so setting it restyles the open views.

const gfx = @import("gfx");
const cadex = @import("cadex");

const Color = gfx.Color;

/// CADEX_TOKEN_* runs 1...17; index 0 is unused.
pub const token_count = 18;

pub const Appearance = struct {
    /// The terminal's font, in points.
    font_family: []const u8 = "Cascadia Mono",
    font_points: f32 = 13,
    background: Color = Color.rgb(0x1e1e1e),
    foreground: Color = Color.rgb(0xd4d4d4),
    current_line: Color = Color.rgb(0xd4d4d4).alpha(0.06),
    line_number: Color = Color.rgb(0x858585),
    selection: Color = Color.rgb(0x264f78),
    /// Null kinds draw in the foreground.
    tokens: [token_count]?Color = [_]?Color{null} ** token_count,

    /// The colors of a theme's terminal, as the Mac makes them
    /// (apps/macos/app/FileOpener.swift): editors of a theme look like its
    /// terminal.
    pub fn fromTerminal(palette: Palette) Appearance {
        const fg = Color.rgb(palette.foreground);
        return .{
            .font_family = palette.font_family,
            .font_points = palette.font_points,
            .background = Color.rgb(palette.background),
            .foreground = fg,
            .current_line = fg.alpha(0.06),
            .line_number = Color.rgb(palette.secondary_text).alpha(0.7),
            .selection = Color.rgb(palette.selection).alpha(0.45),
            .tokens = tokensFromAnsi(palette.ansi, palette.foreground),
        };
    }

    pub fn token(self: *const Appearance, kind: u8) Color {
        if (kind < token_count) if (self.tokens[kind]) |c| return c;
        return self.foreground;
    }

    /// The font spec in pixels for `scale` (points are 4/3 of a pixel at 96 dpi).
    pub fn font(self: *const Appearance, scale: f32) gfx.FontSpec {
        return .{ .family = self.font_family, .size = @round(self.font_points * 4.0 / 3.0 * scale) };
    }
};

pub const Palette = struct {
    font_family: []const u8 = "Cascadia Mono",
    font_points: f32 = 13,
    background: u32,
    foreground: u32,
    selection: u32,
    /// The interface's secondary text, for line numbers.
    secondary_text: u32,
    /// black, red, green, yellow, blue, magenta, cyan, white, then bright.
    ansi: [16]u32,
};

/// The token colors from the 16 ANSI colors (EditorAppearance.tokens on the Mac).
pub fn tokensFromAnsi(ansi: [16]u32, foreground: u32) [token_count]?Color {
    var t = [_]?Color{null} ** token_count;
    const fg = Color.rgb(foreground);
    t[cadex.CADEX_TOKEN_KEYWORD] = Color.rgb(ansi[5]);
    t[cadex.CADEX_TOKEN_STRING] = Color.rgb(ansi[2]);
    t[cadex.CADEX_TOKEN_NUMBER] = Color.rgb(ansi[3]);
    t[cadex.CADEX_TOKEN_COMMENT] = Color.rgb(ansi[8]);
    t[cadex.CADEX_TOKEN_FUNCTION] = Color.rgb(ansi[4]);
    t[cadex.CADEX_TOKEN_TYPE] = Color.rgb(ansi[6]);
    t[cadex.CADEX_TOKEN_CONSTANT] = Color.rgb(ansi[11]);
    t[cadex.CADEX_TOKEN_PROPERTY] = Color.rgb(ansi[14]);
    t[cadex.CADEX_TOKEN_OPERATOR] = fg;
    t[cadex.CADEX_TOKEN_PUNCTUATION] = fg.alpha(0.7);
    t[cadex.CADEX_TOKEN_VARIABLE] = Color.rgb(ansi[1]);
    t[cadex.CADEX_TOKEN_TAG] = Color.rgb(ansi[1]);
    t[cadex.CADEX_TOKEN_ATTRIBUTE] = Color.rgb(ansi[3]);
    t[cadex.CADEX_TOKEN_ESCAPE] = Color.rgb(ansi[6]);
    t[cadex.CADEX_TOKEN_HEADING] = Color.rgb(ansi[4]);
    t[cadex.CADEX_TOKEN_LINK] = Color.rgb(ansi[12]);
    t[cadex.CADEX_TOKEN_EMPHASIS] = Color.rgb(ansi[13]);
    return t;
}

/// What open views use; the app sets it when the theme or font changes.
pub var current: Appearance = .{};

test {
    @import("win32").refAllDeep(@This());
}
