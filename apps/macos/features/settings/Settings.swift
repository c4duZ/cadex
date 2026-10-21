import Foundation

/// Every user preference, as saved in settings.json (docs/spec/settings.md).
/// One file, one place: terminal, appearance and shortcuts all live here.
public struct Settings: Equatable, Sendable {
    public struct General: Equatable, Sendable {
        /// Empty: the system's shell.
        public var shell = ""
        public var confirmClose = true
        public var confirmMultilinePaste = true
        /// Where files, diffs, the git history and web previews open:
        /// "beside" the focused pane or in a new "tab" (docs/spec/tabs.md).
        public var openFiles = "beside"
        /// The interface's language, "en" or "pt"; counts when Cadex opens
        /// (docs/adr/0015-english-default-two-languages.md).
        public var language = "en"
    }

    public struct Terminal: Equatable, Sendable {
        public var fontFamily = "SF Mono"
        public var fontSize: Double = 13
        /// "bar", "block" or "underline".
        public var cursor = "bar"
        public var cursorBlink = false
        public var historyLines = 10_000
        public var optionAsMeta = false
        public var copyOnSelect = false
        /// The WCAG ratio text keeps against its background; 1 is off (plan 15).
        public var minimumContrast: Double = 1
        /// Line height as a multiple of the font's.
        public var lineHeight: Double = 1
        /// Extra space between letters, in points.
        public var letterSpacing: Double = 0
        /// OpenType features: "calt" and "liga" join ligatures, "-" turns one off.
        public var fontFeatures: [String] = []
    }

    public struct Appearance: Equatable, Sendable {
        /// The theme family id ("caffeine").
        public var theme = "caffeine"
        /// With the mode following the system, another theme for its light
        /// or dark mode; empty uses `theme` (plan 15, phase B).
        public var lightTheme = ""
        public var darkTheme = ""
        /// "#RRGGBB" in place of the theme's accent; empty keeps the theme's.
        public var accent = ""
        /// "system", "dark" or "light".
        public var mode = "system"
        public var vibrancy = false
        /// A path, or nil for no background image.
        public var backgroundImage: String?
        public var backgroundOpacity: Double = 0.5
        public var backgroundBlur: Double = 0
        /// Text at 7:1, stronger borders, no transparency; also on with the
        /// system's "Increase contrast" (plan 15, phase C).
        public var highContrast = false
        /// The interface's zoom, density and font, apart from the terminal's;
        /// they count when Cadex opens (plan 15, phase D).
        public var uiZoom: Double = 1
        /// "normal" or "compact".
        public var density = "normal"
        /// Empty: the system font.
        public var uiFont = ""
        public var uiFontSize: Double = 13
    }

    public struct Tabs: Equatable, Sendable {
        /// The shade over the panes without focus, 0 to 0.6 (0.26 measured
        /// against dark themes on 2026-10-19).
        public var unfocusedDim: Double = 0.26
        /// Where a file opened beside goes, with half the tab: "right" or
        /// "left" (issue #5).
        public var documentSide = "right"
    }

    public struct Explorer: Equatable, Sendable {
        /// Names starting with "." in the tree, dimmed (docs/spec/explorer.md).
        public var showHidden = true
        /// The tree follows the folder of the terminal in use (docs/spec/workspace.md).
        public var followTerminal = true
    }

    public struct Markdown: Equatable, Sendable {
        /// How a note opens: "source" (the text, to edit) or "rendered"
        /// (docs/spec/markdown.md). The button in the tab switches either way.
        public var openAs = "source"
    }

    public struct Preview: Equatable, Sendable {
        /// Where a picked element goes: "terminal" (pasted into the agent's
        /// prompt, without Enter) or "clipboard" (docs/spec/preview.md).
        public var pickTarget = "terminal"
        /// A picture of the picked element goes with it, as a PNG path.
        public var pickScreenshot = true
    }

    public struct Power: Equatable, Sendable {
        /// What the coffee in the title bar turns on: "always" or
        /// "running" (only while a terminal runs a program); ⌘K picks
        /// either on the spot (docs/spec/power.md).
        public var mode = "always"
        /// Turned on when Cadex opens.
        public var onAtLaunch = false
        /// The screen stays on too while the computer is held.
        public var keepDisplayOn = false
    }

    public struct Sidebar: Equatable, Sendable {
        /// The icons on top of the sidebar, in order; a page left out is
        /// hidden (docs/spec/sidebar.md). The app drops unknown ids.
        public var items = ["files", "search", "git", "agents"]
    }

    public struct Agents: Equatable, Sendable {
        /// Read the agent sessions of every Claude Code account on this Mac
        /// (docs/spec/agents.md). Off: no file of theirs is opened.
        public var sessions = true
        /// Notify when an agent stops: it asks permission, it asked a
        /// question, it finished (docs/spec/agents.md, Notificações).
        public var notifyPermission = true
        public var notifyQuestion = true
        public var notifyFinished = true
        /// Read each account's plan usage (Accounts, the usage item). Off:
        /// no login is read and no request is made.
        public var accounts = true
        /// Names you gave accounts, by folder ("~/.claude-diogo": "Liderhub").
        public var accountNames: [String: String] = [:]
        /// Accounts left out of Accounts and the usage item, by folder.
        public var hiddenAccounts: [String] = []
    }

    public struct SSH: Equatable, Sendable {
        /// Test each host of ~/.ssh/config with a TCP connection while the
        /// SSH item shows (docs/spec/ssh.md). Off: the list only.
        public var ping = true
    }

    public struct StatusBar: Equatable, Sendable {
        /// The items on each side, in order; an item in neither is hidden
        /// (docs/spec/status-bar.md). The app drops unknown ids.
        public var left = ["folder"]
        public var right = ["environment"]
    }

    public var general = General()
    public var terminal = Terminal()
    public var appearance = Appearance()
    public var tabs = Tabs()
    public var explorer = Explorer()
    public var markdown = Markdown()
    public var preview = Preview()
    public var power = Power()
    public var sidebar = Sidebar()
    public var statusBar = StatusBar()
    public var agents = Agents()
    public var ssh = SSH()
    /// "cmd+shift+t" → command id, or nil to turn a default off.
    public var shortcuts: [String: String?] = [:]

    public init() {}

    // Limits from docs/spec/settings.md.
    static let fontSizes = 8.0...32.0
    static let historyRange = 100...100_000
    static let cursors = ["bar", "block", "underline"]
    static let modes = ["system", "dark", "light"]
    static let markdownOpenings = ["source", "rendered"]
    static let pickTargets = ["terminal", "clipboard"]
    static let documentSides = ["right", "left"]
    static let fileOpenings = ["beside", "tab"]
    static let languages = ["en", "pt"]
    static let keepAwakeModes = ["always", "running"]
    static let contrastRange = 1.0...21.0
    static let lineHeights = 0.8...2.0
    static let letterSpacings = -1.0...4.0
    static let dimRange = 0.0...0.6
    static let zoomRange = 0.8...1.5
    static let densities = ["normal", "compact"]
    static let uiFontSizes = 9.0...24.0
}
