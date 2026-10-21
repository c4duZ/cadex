import Foundation

/// Reads the terminal theme files other apps use (plan 15, phase A):
/// iTerm2's .itermcolors, a Ghostty theme, a base16 or base24 scheme
/// (.yaml), or a Cadex theme (.json). The interface colors of a terminal
/// theme are made from its own background, text and blue.
public enum ThemeImport {
    public static let extensions = ["itermcolors", "yaml", "yml", "json", "conf", ""]

    public static func read(_ url: URL) throws -> Theme {
        let data = try Data(contentsOf: url)
        let name = url.deletingPathExtension().lastPathComponent
        switch url.pathExtension.lowercased() {
        case "json": return try ThemeFile.read(data)
        case "itermcolors": return try iterm(data, name: name)
        case "yaml", "yml": return try base16(String(decoding: data, as: UTF8.self), name: name)
        default: return try ghostty(String(decoding: data, as: UTF8.self), name: name)
        }
    }

    static func iterm(_ data: Data, name: String) throws -> Theme {
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw ThemeFile.Problem(field: "(arquivo)", message: "não é um .itermcolors")
        }
        func color(_ key: String) throws -> RGB {
            guard let c = plist[key] as? [String: Any] else { throw ThemeFile.Problem(field: key, message: "falta a cor") }
            func channel(_ k: String) -> UInt32 { UInt32((((c[k] as? Double) ?? 0) * 255).rounded()) }
            return RGB(channel("Red Component") << 16 | channel("Green Component") << 8 | channel("Blue Component"))
        }
        let ansi = try (0..<16).map { try color("Ansi \($0) Color") }
        let background = try color("Background Color"), foreground = try color("Foreground Color")
        return derived(name: name, terminal: .init(
            background: background, foreground: foreground,
            cursor: (try? color("Cursor Color")) ?? foreground,
            selection: (try? color("Selection Color")) ?? background.mixed(foreground, 0.25), ansi: ansi))
    }

    static func ghostty(_ text: String, name: String) throws -> Theme {
        var values: [String: String] = [:], palette: [Int: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            if parts[0] == "palette" {
                let entry = parts[1].split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                if entry.count == 2, let index = Int(entry[0]) { palette[index] = entry[1] }
            } else {
                values[parts[0]] = parts[1]
            }
        }
        func color(_ value: String?, _ field: String) throws -> RGB {
            try ThemeFile.parse(value.map { $0.hasPrefix("#") ? $0 : "#" + $0 }, field: field)
        }
        let ansi = try (0..<16).map { try color(palette[$0], "palette = \($0)") }
        let background = try color(values["background"], "background"), foreground = try color(values["foreground"], "foreground")
        return derived(name: name, terminal: .init(
            background: background, foreground: foreground,
            cursor: (try? color(values["cursor-color"], "cursor-color")) ?? foreground,
            selection: (try? color(values["selection-background"], "selection-background")) ?? background.mixed(foreground, 0.25),
            ansi: ansi))
    }

    /// tinted-theming's terminal mapping, as tools/themes/tinted.py does.
    static func base16(_ text: String, name fallback: String) throws -> Theme {
        var palette: [String: String] = [:]
        var name = fallback
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            let clean = parts[1].replacingOccurrences(of: "\"", with: "")
            if parts[0] == "name" { name = clean }
            if parts[0].hasPrefix("base"), let hex = clean.split(separator: " ").first {
                palette[parts[0]] = hex.hasPrefix("#") ? String(hex) : "#" + hex
            }
        }
        func color(_ key: String, or other: String? = nil) throws -> RGB {
            try ThemeFile.parse(palette[key] ?? other.flatMap { palette[$0] }, field: key)
        }
        let normal = try ["base00", "base08", "base0B", "base0A", "base0D", "base0E", "base0C", "base05"].map { try color($0) }
        let bright = try [("base12", "base08"), ("base14", "base0B"), ("base13", "base0A"), ("base16", "base0D"),
                          ("base17", "base0E"), ("base15", "base0C")].map { try color($0.0, or: $0.1) }
        let ansi = normal + [try color("base03")] + bright + [try color("base07")]
        return derived(name: name, terminal: .init(
            background: normal[0], foreground: normal[7], cursor: normal[7], selection: try color("base02"), ansi: ansi))
    }

    /// The interface of a terminal-only theme: panels in its background,
    /// the frame a little toward its text, the accent its blue.
    static func derived(name: String, terminal: Theme.Terminal) -> Theme {
        let bg = terminal.background, fg = terminal.foreground
        let dark = bg.luminance < 0.18
        let chrome = bg.mixed(fg, 0.07)
        let accent = terminal.ansi[4]
        return Theme(name: name, dark: dark, interface: .init(
            chrome: chrome, panel: bg, panelBorder: bg.mixed(fg, 0.14), tabActive: chrome.mixed(accent, 0.22),
            field: bg.mixed(fg, 0.1), text: fg, secondaryText: fg.mixed(bg, 0.35), accent: accent), terminal: terminal)
    }
}
