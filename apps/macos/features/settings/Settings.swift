import Foundation

/// Every user preference, as saved in settings.json (docs/spec/settings.md).
/// One file, one place: terminal, appearance and shortcuts all live here.
public struct Settings: Equatable, Sendable {
    /// The file's version: what an old file (without it) gets moved to once,
    /// when the defaults change (SettingsFile.migrate). 2: the new frame's
    /// theme; 3: the new frame's status bar (docs/adr/0035-work-frame.md, 2026-11-17).
    public static let currentVersion = 7
    public var version = Settings.currentVersion

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
        /// 1.6: the new frame's terminal (tokens.json, components.terminalTheme.lineHeight).
        public var lineHeight: Double = 1.6
        /// Extra space between letters, in points.
        public var letterSpacing: Double = 0
        /// OpenType features: "calt" and "liga" join ligatures, "-" turns one off.
        public var fontFeatures: [String] = []
        /// A program's own notifications (OSC 777, OSC 9) as macOS ones.
        public var programNotifications = true
        /// The main window's terminals outlive the app, in the terminal
        /// daemon (plan 19 phase E); off until it passes `make perf`.
        public var keepSessions = false
    }

    public struct Appearance: Equatable, Sendable {
        /// The theme family id: Cadex Night, the new frame's (docs/adr/0035-work-frame.md).
        public var theme = "cadex-night"
        /// With the mode following the system, another theme for its light
        /// or dark mode; empty uses `theme` (plan 15, phase B).
        public var lightTheme = ""
        public var darkTheme = ""
        /// "#RRGGBB" in place of the theme's accent; empty keeps the theme's.
        public var accent = ""
        /// "system", "dark" or "light".
        public var mode = "system"
        public var vibrancy = false
        /// The window's opacity, 1 solid: below it the frame, the sidebar and the panes become one
        /// glass in the theme's color over the desktop or the window behind (owner, 2026-11-18).
        public var windowOpacity: Double = 1
        /// "auto", "system" or "cadex": the system's full screen is a Space over black, where a
        /// translucent window shows black; Cadex's covers the screen over the wallpaper (2026-11-24).
        public var fullScreen = "auto"
        /// "normal" or "strong": the strong glass blurs the wallpaper behind everything through a
        /// clean dark frost, makes the panes glass boxes, and puts ⌘K, the menus and the cards in the
        /// same glass; it turns a solid window translucent (the owner, 2026-11-24).
        public var glass = "normal"
        /// "line" (the panes' border as the mockups draw it) or "glow": the border in the work color,
        /// with a soft glow (the owner, 2026-11-24: configurable, today's the default).
        public var paneBorder = "line"
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

    /// The right panel (docs/spec/inspector.md): open or closed, and its tab, come back on reopen.
    public struct Inspector: Equatable, Sendable {
        public var visible = true
        public var tab = "changes"
        /// Its width, dragged by the edge; 260 is components.inspector.width (the side column, ADR 0038).
        public var width = 260.0
        /// The pages' order, dragged in the rail (plan 36 phase E); empty: the app's own.
        public var order: [String] = []
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
        /// Each kind's sound: "none", "default", a macOS sound's name or
        /// the path of a file (the owner wants every one to sound, his own
        /// way, 2026-10-22). Three different ones by default.
        public var soundPermission = "Funk"
        public var soundQuestion = "Ping"
        public var soundFinished = "Glass"
        /// Read each account's plan usage (Accounts, the usage item). Off:
        /// no usage file is read or watched (ADR 0021: no login is ever read).
        public var accounts = true
        /// Names you gave accounts, by folder ("~/.claude-diogo": "Liderhub").
        public var accountNames: [String: String] = [:]
        /// Accounts left out of Accounts and the usage item, by folder.
        public var hiddenAccounts: [String] = []
        /// Each hidden account's login when it was hidden: it comes back when
        /// that changes (another account or organization logs in), by folder.
        public var hiddenLogins: [String: String] = [:]
        /// Clicking an account opens its agent without permission prompts
        /// (Claude Code's --dangerously-skip-permissions, Codex's
        /// --dangerously-bypass-approvals-and-sandbox). Off by default.
        public var launchSkipPermissions = false
        /// The hooks that tell the app what a session Cadex opened does (plan
        /// 19): its id after /clear and --resume. Off: none in the kit.
        public var stateHooks = true
        /// The bell, the feed and the board (plan 19, phase C). Off: none.
        public var attention = true
        /// The bell's number on the Dock's icon too.
        public var dockBadge = true
        /// Machines whose agents notify nothing: "local" is this Mac (plan 23
        /// adds remote ones).
        public var mutedMachines: [String] = []
        /// A done or idle agent not looked at for this long ends and comes
        /// back when its terminal is opened (plan 19 phase F); 0 is off.
        public var hibernateAfterMinutes = 30
        /// Index every account's conversations for the History page (plan 18,
        /// phase D). Off: nothing indexed or watched.
        public var history = true
        /// The account of the new sessions Cadex opens ("~/.claude-work");
        /// empty is the default account (docs/spec/agents.md, Contas gerenciadas).
        public var activeAccount = ""
        /// A project's own account, by git root ("~/code/app": "~/.claude-work"):
        /// it beats the active account in that project.
        public var projectAccounts: [String: String] = [:]
    }

    /// The agent uses the Cadex (docs/adr/0024-agent-tools.md, plan 20).
    public struct AgentTools: Equatable, Sendable {
        /// The sessions Cadex opens get `cadex` on their PATH, its MCP and
        /// skills, and the socket takes their command requests.
        public var enabled = true
        /// The agent drives the preview (plan 20 phase C).
        public var browser = true
    }

    /// The agent operates other apps (docs/adr/0026-computer-use.md): off
    /// until the owner turns it on; the apps allowed and the extra blocked.
    public struct ComputerUse: Equatable, Sendable {
        public var enabled = false
        public var allowedApps: [String] = []
        public var blockedApps: [String] = []
    }

    /// Tasks' worktrees (docs/spec/worktrees.md, plan 19 phase D).
    public struct Worktrees: Equatable, Sendable {
        /// Where tasks go: empty is beside each repository (`<repo>.worktrees`).
        public var root = ""
        /// Repository (with ~) → the setup hooks, in order.
        public var setupHooks: [String: [String]] = [:]
    }

    public struct SSH: Equatable, Sendable {
        /// Test each host of ~/.ssh/config with a TCP connection while the
        /// SSH item shows (docs/spec/ssh.md). Off: the list only.
        public var ping = true
    }

    /// The tailnet's machines (docs/spec/machines.md, plan 23).
    public struct Machines: Equatable, Sendable {
        /// Read the owner's Tailscale. Off: no socket of it opened, no file
        /// of it read, no process of it run.
        public var tailscale = true
        /// Listen on this Mac's tailnet address for the owner's other devices
        /// (WhoIs, same user only). Off: nothing listens on the network.
        public var acceptRemote = false
        /// MagicDNS name → the user ssh logs in as, asked once per machine.
        public var users: [String: String] = [:]
    }

    /// The review tab (docs/spec/review.md, plan 21).
    public struct Git: Equatable, Sendable {
        /// Unchanged lines kept around each change; the rest folds.
        public var reviewContextLines = 3
        public var reviewWrap = false
        public var reviewShowWhitespace = false
    }

    /// The review's line authorship (docs/adr/0027-local-authorship.md).
    public struct Review: Equatable, Sendable {
        /// Off: the session kit gets no PostToolUse hook and nothing is kept.
        public var authorship = true
    }

    /// The project memory (docs/spec/memory.md, plan 22).
    public struct Memory: Equatable, Sendable {
        /// Off: sessions get no memory hooks and the engine is not warmed.
        public var enabled = true
        /// Off: each account has its own memory (clients' accounts apart).
        public var shareAcrossAccounts = true
        /// At a milestone the session's own Claude consolidates the session
        /// into the memory (plan 22 phase F; docs/spec/memory.md).
        public var consolidateInSession = true
        /// The context percent that is a milestone.
        public var consolidateAtContext = 70
        /// The memory agent, a `claude -p` on the account (ADR 0029): off by
        /// default; its daily cap and whether its proposals wait for the owner.
        /// On by default (ADR 0037, plan 32 C).
        public var backgroundAgent = true
        public var dailyBudgetUsd = 1.0
        public var requireApproval = false
        /// The one-time notice that the memory agent is on, what it spends and how to turn it off
        /// was shown (ADR 0037 asks for it on the first opening; it did not exist: UX audit, 2026-11-18).
        public var agentNoticeShown = false
    }

    public struct StatusBar: Equatable, Sendable {
        /// The items on each side, in order; an item in neither is hidden
        /// (docs/spec/status-bar.md). The app drops unknown ids.
        public var left = ["project", "agents"]
        public var right = ["drawer", "memory", "usage", "keepAwake", "update", "environment"]
    }

    public var general = General()
    public var terminal = Terminal()
    public var appearance = Appearance()
    public var tabs = Tabs()
    public var explorer = Explorer()
    public var markdown = Markdown()
    public var preview = Preview()
    public var power = Power()
    public var inspector = Inspector()
    public var statusBar = StatusBar()
    public var agents = Agents()
    public var ssh = SSH()
    public var machines = Machines()
    public var git = Git()
    public var review = Review()
    public var memory = Memory()
    public var orchestration = Orchestration()
    public var worktrees = Worktrees()
    public var agentTools = AgentTools()
    public var computerUse = ComputerUse()
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
    static let inspectorTabs = ["changes", "files", "history", "memory", "sessions"]
    /// The right panel's width: narrower hides its rows' text, wider eats the terminals.
    public static let inspectorWidths = 240.0...640.0
    static let keepAwakeModes = ["always", "running"]
    static let contrastRange = 1.0...21.0
    /// appearance.windowOpacity: a thin dark tint already carries the text over a wallpaper (the
    /// owner's reference, 2026-11-18: 15 to 30%); under 10% nothing is left of the theme.
    public static let windowOpacityRange = 0.1...1.0
    static let fullScreenModes = ["auto", "system", "cadex"]
    static let glassModes = ["normal", "strong"]
    static let paneBorders = ["line", "glow"]
    /// The opacity theme.toggle-translucent turns on when the window is solid: 80% looked milky,
    /// the owner wanted the wallpaper to show (2026-11-18).
    public static let translucentOpacity = 0.35
    static let lineHeights = 0.8...2.0
    static let letterSpacings = -1.0...4.0
    static let zoomRange = 0.8...1.5
    static let densities = ["normal", "compact"]
    static let uiFontSizes = 9.0...24.0
}
