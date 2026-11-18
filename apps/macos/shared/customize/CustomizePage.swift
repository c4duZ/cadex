import AppKit
import Icons
import Strings
import UILooks

/// The colors of a Customize list, the same as the settings window's: text, quiet text, the
/// switch on, the ground, the rows' boxes.
public struct CustomizeColors {
    public var text: NSColor
    public var secondary: NSColor
    public var accent: NSColor
    public var panel: NSColor
    public var box: NSColor
    public var border: NSColor

    public init(text: NSColor = .labelColor, secondary: NSColor = .secondaryLabelColor, accent: NSColor = .controlAccentColor,
                panel: NSColor = .windowBackgroundColor, box: NSColor = .controlBackgroundColor, border: NSColor = .separatorColor) {
        self.text = text
        self.secondary = secondary
        self.accent = accent
        self.panel = panel
        self.box = box
        self.border = border
    }
}

/// One list to arrange (the status bar's items, the accounts), a section of the settings window
/// since plan 32 (it was a tab of the Customize window). Its owner builds it and takes back each
/// change.
public struct CustomizePage {
    public let id: String
    public let title: String
    public let icon: Icon
    public let note: String
    public let entries: [CustomizeEntry]
    public let onChange: ([CustomizeEntry]) -> Void

    public init(id: String, title: String, icon: Icon, note: String, entries: [CustomizeEntry], onChange: @escaping ([CustomizeEntry]) -> Void) {
        self.id = id
        self.title = title
        self.icon = icon
        self.note = note
        self.entries = entries
        self.onChange = onChange
    }
}

public extension CustomizeColors {
    /// The new frame's tokens (they follow the theme): the settings window's own (plan 31 D).
    @MainActor static var frame: CustomizeColors {
        CustomizeColors(text: DesignTokens.Color.textPrimary, secondary: DesignTokens.Color.textMuted, accent: DesignTokens.Project.Toggle.on,
                        panel: DesignTokens.Color.bgWindow, box: DesignTokens.Project.Row.bg, border: DesignTokens.Project.Row.border)
    }
}
