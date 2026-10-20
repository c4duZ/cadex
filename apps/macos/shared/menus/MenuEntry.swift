import AppKit
import Icons

/// One line of a popup menu: a command with its icon and shortcut, or a
/// separator. The action runs after the menu closes.
public struct MenuEntry {
    public let title: String
    public let icon: Icon?
    /// The shortcut as the palette shows it ("⌘T", "F2"), drawn as keys.
    public let shortcut: String?
    public let isEnabled: Bool
    public let isSeparator: Bool
    let action: @MainActor () -> Void

    public init(_ title: String, icon: Icon? = nil, shortcut: String? = nil, isEnabled: Bool = true,
                action: @escaping @MainActor () -> Void) {
        self.title = title
        self.icon = icon
        self.shortcut = shortcut
        self.isEnabled = isEnabled
        isSeparator = false
        self.action = action
    }

    private init() {
        title = ""
        icon = nil
        shortcut = nil
        isEnabled = false
        isSeparator = true
        action = {}
    }

    public static var separator: MenuEntry { MenuEntry() }

    /// No separator first, last or twice in a row: lists built by leaving
    /// out what cannot run would otherwise show empty groups.
    public static func tidy(_ entries: [MenuEntry]) -> [MenuEntry] {
        var out: [MenuEntry] = []
        for entry in entries {
            if entry.isSeparator, out.last?.isSeparator ?? true { continue }
            out.append(entry)
        }
        if out.last?.isSeparator == true { out.removeLast() }
        return out
    }

    /// "⇧⌘D" from a menu key equivalent, the way the palette writes it.
    public static func shortcutLabel(key: String, modifiers: NSEvent.ModifierFlags) -> String {
        var label = ""
        if modifiers.contains(.control) { label += "⌃" }
        if modifiers.contains(.option) { label += "⌥" }
        if modifiers.contains(.shift) { label += "⇧" }
        if modifiers.contains(.command) { label += "⌘" }
        return label + key.uppercased()
    }
}

/// The menu's colors, from the theme (the app sets `current` when the theme
/// changes), the same as the ⌘K palette's.
public struct MenuStyle {
    public var background: NSColor
    public var border: NSColor
    public var text: NSColor
    public var secondaryText: NSColor
    public var selection: NSColor
    public var accent: NSColor
    public var keycap: NSColor

    public init(background: NSColor, border: NSColor, text: NSColor, secondaryText: NSColor,
                selection: NSColor, accent: NSColor, keycap: NSColor) {
        self.background = background
        self.border = border
        self.text = text
        self.secondaryText = secondaryText
        self.selection = selection
        self.accent = accent
        self.keycap = keycap
    }

    @MainActor public static var current = MenuStyle(
        background: .windowBackgroundColor, border: .separatorColor, text: .labelColor,
        secondaryText: .secondaryLabelColor, selection: .quaternaryLabelColor, accent: .controlAccentColor,
        keycap: .controlBackgroundColor)
}
