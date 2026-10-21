import Foundation

/// Reads and writes settings.json. Reading is forgiving field by field: a
/// wrong value falls back to its default and becomes a problem for the log,
/// while the rest of the file still counts (docs/spec/settings.md).
public enum SettingsFile {
    public static func read(_ data: Data) -> (Settings, [String]) {
        var problems: [String] = []
        var settings = Settings()
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (settings, ["settings.json não é um objeto JSON; valem os padrões"])
        }
        var reader = FieldReader(problems: problems)
        if let g = reader.section(root, "general") {
            settings.general.shell = reader.string(g, "general.shell") ?? settings.general.shell
            settings.general.confirmClose = reader.bool(g, "general.confirmClose") ?? settings.general.confirmClose
            settings.general.confirmMultilinePaste = reader.bool(g, "general.confirmMultilinePaste") ?? settings.general.confirmMultilinePaste
            settings.general.openFiles = reader.choice(g, "general.openFiles", Settings.fileOpenings) ?? settings.general.openFiles
            settings.general.language = reader.choice(g, "general.language", Settings.languages) ?? settings.general.language
        }
        if let t = reader.section(root, "terminal") {
            settings.terminal.fontFamily = reader.string(t, "terminal.fontFamily") ?? settings.terminal.fontFamily
            if let size = reader.number(t, "terminal.fontSize") {
                settings.terminal.fontSize = min(max(size, Settings.fontSizes.lowerBound), Settings.fontSizes.upperBound)
            }
            settings.terminal.cursor = reader.choice(t, "terminal.cursor", Settings.cursors) ?? settings.terminal.cursor
            settings.terminal.cursorBlink = reader.bool(t, "terminal.cursorBlink") ?? settings.terminal.cursorBlink
            if let lines = reader.number(t, "terminal.historyLines") {
                settings.terminal.historyLines = min(max(Int(lines), Settings.historyRange.lowerBound), Settings.historyRange.upperBound)
            }
            settings.terminal.optionAsMeta = reader.bool(t, "terminal.optionAsMeta") ?? settings.terminal.optionAsMeta
            settings.terminal.copyOnSelect = reader.bool(t, "terminal.copyOnSelect") ?? settings.terminal.copyOnSelect
            if let v = reader.number(t, "terminal.minimumContrast") { settings.terminal.minimumContrast = v.clamped(to: Settings.contrastRange) }
            if let v = reader.number(t, "terminal.lineHeight") { settings.terminal.lineHeight = v.clamped(to: Settings.lineHeights) }
            if let v = reader.number(t, "terminal.letterSpacing") { settings.terminal.letterSpacing = v.clamped(to: Settings.letterSpacings) }
            if let list = reader.strings(t, "terminal.fontFeatures") {
                settings.terminal.fontFeatures = list.filter { Settings.isFontFeature($0) }
                if settings.terminal.fontFeatures.count != list.count {
                    reader.problems.append("terminal.fontFeatures: cada item é uma etiqueta OpenType de 4 letras, como \"calt\" ou \"-liga\"")
                }
            }
        }
        if let a = reader.section(root, "appearance") {
            settings.appearance.theme = reader.string(a, "appearance.theme") ?? settings.appearance.theme
            settings.appearance.lightTheme = reader.string(a, "appearance.lightTheme") ?? settings.appearance.lightTheme
            settings.appearance.darkTheme = reader.string(a, "appearance.darkTheme") ?? settings.appearance.darkTheme
            if let accent = reader.string(a, "appearance.accent") {
                if accent.isEmpty || Settings.isHexColor(accent) { settings.appearance.accent = accent }
                else { reader.problems.append("appearance.accent: \"\(accent)\" não é uma cor #RRGGBB") }
            }
            settings.appearance.mode = reader.choice(a, "appearance.mode", Settings.modes) ?? settings.appearance.mode
            settings.appearance.vibrancy = reader.bool(a, "appearance.vibrancy") ?? settings.appearance.vibrancy
            if a["backgroundImage"] is NSNull { settings.appearance.backgroundImage = nil }
            else { settings.appearance.backgroundImage = reader.string(a, "appearance.backgroundImage") }
            if let opacity = reader.number(a, "appearance.backgroundOpacity") { settings.appearance.backgroundOpacity = min(max(opacity, 0), 1) }
            if let blur = reader.number(a, "appearance.backgroundBlur") { settings.appearance.backgroundBlur = min(max(blur, 0), 50) }
            settings.appearance.highContrast = reader.bool(a, "appearance.highContrast") ?? settings.appearance.highContrast
            if let v = reader.number(a, "appearance.uiZoom") { settings.appearance.uiZoom = v.clamped(to: Settings.zoomRange) }
            settings.appearance.density = reader.choice(a, "appearance.density", Settings.densities) ?? settings.appearance.density
            settings.appearance.uiFont = reader.string(a, "appearance.uiFont") ?? settings.appearance.uiFont
            if let v = reader.number(a, "appearance.uiFontSize") { settings.appearance.uiFontSize = v.clamped(to: Settings.uiFontSizes) }
        }
        if let t = reader.section(root, "tabs") {
            if let v = reader.number(t, "tabs.unfocusedDim") { settings.tabs.unfocusedDim = v.clamped(to: Settings.dimRange) }
        }
        if let e = reader.section(root, "explorer") {
            settings.explorer.showHidden = reader.bool(e, "explorer.showHidden") ?? settings.explorer.showHidden
            settings.explorer.followTerminal = reader.bool(e, "explorer.followTerminal") ?? settings.explorer.followTerminal
        }
        if let m = reader.section(root, "markdown") {
            settings.markdown.openAs = reader.choice(m, "markdown.openAs", Settings.markdownOpenings) ?? settings.markdown.openAs
        }
        if let v = reader.section(root, "preview") {
            settings.preview.pickTarget = reader.choice(v, "preview.pickTarget", Settings.pickTargets) ?? settings.preview.pickTarget
            settings.preview.pickScreenshot = reader.bool(v, "preview.pickScreenshot") ?? settings.preview.pickScreenshot
        }
        if let p = reader.section(root, "power") {
            settings.power.mode = reader.choice(p, "power.mode", Settings.keepAwakeModes) ?? settings.power.mode
            settings.power.onAtLaunch = reader.bool(p, "power.onAtLaunch") ?? settings.power.onAtLaunch
            settings.power.keepDisplayOn = reader.bool(p, "power.keepDisplayOn") ?? settings.power.keepDisplayOn
        }
        if let s = reader.section(root, "shortcuts") {
            for (combo, value) in s {
                if value is NSNull { settings.shortcuts[combo] = .some(nil) }
                else if let id = value as? String { settings.shortcuts[combo] = .some(id) }
                else { reader.problems.append("shortcuts.\(combo): esperava o id de um comando ou null") }
            }
        }
        problems = reader.problems
        return (settings, problems)
    }

    public static func write(_ settings: Settings) -> Data {
        let s = settings
        var shortcuts: [String: Any] = [:]
        for (combo, id) in s.shortcuts { shortcuts[combo] = id ?? NSNull() }
        let object: [String: Any] = [
            "general": ["shell": s.general.shell, "confirmClose": s.general.confirmClose,
                        "confirmMultilinePaste": s.general.confirmMultilinePaste, "openFiles": s.general.openFiles,
                        "language": s.general.language],
            "terminal": ["fontFamily": s.terminal.fontFamily, "fontSize": s.terminal.fontSize, "cursor": s.terminal.cursor,
                         "cursorBlink": s.terminal.cursorBlink, "historyLines": s.terminal.historyLines,
                         "optionAsMeta": s.terminal.optionAsMeta, "copyOnSelect": s.terminal.copyOnSelect,
                         "minimumContrast": s.terminal.minimumContrast, "lineHeight": s.terminal.lineHeight,
                         "letterSpacing": s.terminal.letterSpacing, "fontFeatures": s.terminal.fontFeatures],
            "appearance": ["theme": s.appearance.theme, "lightTheme": s.appearance.lightTheme, "darkTheme": s.appearance.darkTheme,
                           "accent": s.appearance.accent, "mode": s.appearance.mode, "vibrancy": s.appearance.vibrancy,
                           "backgroundImage": s.appearance.backgroundImage ?? NSNull(),
                           "backgroundOpacity": s.appearance.backgroundOpacity, "backgroundBlur": s.appearance.backgroundBlur,
                           "highContrast": s.appearance.highContrast, "uiZoom": s.appearance.uiZoom,
                           "density": s.appearance.density, "uiFont": s.appearance.uiFont, "uiFontSize": s.appearance.uiFontSize],
            "tabs": ["unfocusedDim": s.tabs.unfocusedDim],
            "explorer": ["showHidden": s.explorer.showHidden, "followTerminal": s.explorer.followTerminal],
            "markdown": ["openAs": s.markdown.openAs],
            "preview": ["pickTarget": s.preview.pickTarget, "pickScreenshot": s.preview.pickScreenshot],
            "power": ["mode": s.power.mode, "onAtLaunch": s.power.onAtLaunch, "keepDisplayOn": s.power.keepDisplayOn],
            "shortcuts": shortcuts,
        ]
        return (try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])) ?? Data()
    }
}

/// Reads one typed field at a time, noting what is wrong.
private struct FieldReader {
    var problems: [String]

    mutating func section(_ root: [String: Any], _ key: String) -> [String: Any]? {
        guard let value = root[key] else { return nil }
        guard let section = value as? [String: Any] else {
            problems.append("\(key): esperava uma seção")
            return nil
        }
        return section
    }

    mutating func string(_ object: [String: Any], _ field: String) -> String? {
        typed(object, field, "um texto") { $0 as? String }
    }

    mutating func bool(_ object: [String: Any], _ field: String) -> Bool? {
        typed(object, field, "true ou false") { ($0 as? NSNumber).flatMap { CFGetTypeID($0) == CFBooleanGetTypeID() ? $0.boolValue : nil } }
    }

    mutating func number(_ object: [String: Any], _ field: String) -> Double? {
        typed(object, field, "um número") { ($0 as? NSNumber).flatMap { CFGetTypeID($0) == CFBooleanGetTypeID() ? nil : $0.doubleValue } }
    }

    mutating func strings(_ object: [String: Any], _ field: String) -> [String]? {
        typed(object, field, "uma lista de textos") { $0 as? [String] }
    }

    mutating func choice(_ object: [String: Any], _ field: String, _ options: [String]) -> String? {
        guard let text = string(object, field) else { return nil }
        guard options.contains(text) else {
            problems.append("\(field): \"\(text)\" não é uma das opções (\(options.joined(separator: ", ")))")
            return nil
        }
        return text
    }

    private mutating func typed<T>(_ object: [String: Any], _ field: String, _ expected: String, _ cast: (Any) -> T?) -> T? {
        let key = String(field.split(separator: ".").last!)
        guard let value = object[key] else { return nil }
        guard let typed = cast(value) else {
            problems.append("\(field): esperava \(expected)")
            return nil
        }
        return typed
    }
}

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double { Swift.min(Swift.max(self, range.lowerBound), range.upperBound) }
}

extension Settings {
    /// "calt", "ss01", "-liga": a 4-letter OpenType tag, "-" to turn it off.
    static func isHexColor(_ text: String) -> Bool {
        text.count == 7 && text.hasPrefix("#") && UInt32(text.dropFirst(), radix: 16) != nil
    }

    static func isFontFeature(_ text: String) -> Bool {
        let tag = text.hasPrefix("-") ? text.dropFirst() : Substring(text)
        return tag.count == 4 && tag.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }
}
