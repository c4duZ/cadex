/// The high contrast mode (plan 15, phase C; appearance.highContrast, or
/// the system's "Increase contrast"): every text at 7:1 (WCAG AAA), borders
/// at 3:1, the active tab and the accent stronger. Transparency goes off in
/// the app, which applies it.
public extension Theme {
    static let highContrastText = 7.0
    static let highContrastBorder = 3.0

    func withHighContrast() -> Theme {
        var theme = self
        var ui = theme.interface
        // Mid-gray surfaces can't reach 7:1 with any text (brushtrees,
        // 2026-10-20): they go darker (lighter in a light theme) first,
        // enough for white (black) text to pass with room.
        let ink = dark ? RGB(0xFFFFFF) : RGB(0x000000)
        ui.panel = ui.panel.readable(on: [ink], Self.highContrastText + 1)
        ui.chrome = ui.chrome.readable(on: [ink], Self.highContrastText + 1)
        ui.field = ui.field.readable(on: [ink], Self.highContrastText + 1)
        theme.terminal.background = theme.terminal.background.readable(on: [ink], Self.highContrastText + 1)
        let backgrounds = [ui.panel, ui.chrome, ui.field]
        ui.text = ui.text.readable(on: backgrounds, Self.highContrastText)
        ui.secondaryText = ui.secondaryText.readable(on: backgrounds, Self.highContrastText)
        ui.panelBorder = ui.panelBorder.readable(on: ui.panel, Self.highContrastBorder)
        ui.accent = ui.accent.readable(on: ui.chrome, Self.highContrastBorder)
        ui.tabActive = ui.chrome.mixed(ui.accent, 0.45)
        theme.interface = ui
        theme.terminal.foreground = theme.terminal.foreground.readable(on: theme.terminal.background, Self.highContrastText)
        return theme
    }
}

public extension RGB {
    /// This color moved toward white or black, whichever reads better on
    /// `background`, just until the contrast reaches `ratio` (or as far as
    /// it goes). The same rule as the terminal shader's minimum contrast.
    func readable(on background: RGB, _ ratio: Double) -> RGB {
        readable(on: [background], ratio)
    }

    /// The same against several backgrounds at once (text on the panels,
    /// the frame and the fields), the direction taken from the first:
    /// moving for one at a time undid the others (brushtrees, 2026-10-20).
    func readable(on backgrounds: [RGB], _ ratio: Double) -> RGB {
        func worst(_ color: RGB) -> Double { backgrounds.map(color.contrast).min() ?? 21 }
        guard let first = backgrounds.first, worst(self) < ratio else { return self }
        let white = RGB(0xFFFFFF), black = RGB(0x000000)
        let target = white.contrast(with: first) >= black.contrast(with: first) ? white : black
        var low = 0.0, high = 1.0
        for _ in 0..<10 {
            let middle = (low + high) / 2
            if worst(mixed(target, middle)) >= ratio { high = middle } else { low = middle }
        }
        return mixed(target, high)
    }

    /// Black or white, whichever reads better on this color: the text on
    /// a fill of the accent (plan 15, phase B).
    var textOnTop: RGB {
        RGB(0xFFFFFF).contrast(with: self) >= RGB(0x000000).contrast(with: self) ? RGB(0xFFFFFF) : RGB(0x000000)
    }
}

public extension Theme.Interface {
    /// The text on the active tab and the selected rows: the theme's text,
    /// or black or white when an accent of the user's made the fill too
    /// close to it (plan 15, phase B).
    var textOnTabActive: RGB {
        text.contrast(with: tabActive) >= 4.5 ? text : tabActive.textOnTop
    }
}
