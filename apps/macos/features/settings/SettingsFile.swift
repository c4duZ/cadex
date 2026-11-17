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
            settings.terminal.programNotifications = reader.bool(t, "terminal.programNotifications") ?? settings.terminal.programNotifications
            settings.terminal.keepSessions = reader.bool(t, "terminal.keepSessions") ?? settings.terminal.keepSessions
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
            settings.tabs.documentSide = reader.choice(t, "tabs.documentSide", Settings.documentSides) ?? settings.tabs.documentSide
            settings.tabs.paneHeaders = reader.choice(t, "tabs.paneHeaders", Settings.paneHeaderModes) ?? settings.tabs.paneHeaders
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
        if let s = reader.section(root, "sidebar") {
            settings.sidebar.items = reader.strings(s, "sidebar.items") ?? settings.sidebar.items
        }
        if let s = reader.section(root, "inspector") {
            settings.inspector.visible = reader.bool(s, "inspector.visible") ?? settings.inspector.visible
            settings.inspector.tab = reader.choice(s, "inspector.tab", Settings.inspectorTabs) ?? settings.inspector.tab
            if let width = reader.number(s, "inspector.width") {
                settings.inspector.width = min(max(width, Settings.inspectorWidths.lowerBound), Settings.inspectorWidths.upperBound)
            }
        }
        if let s = reader.section(root, "agents") {
            settings.agents.sessions = reader.bool(s, "agents.sessions") ?? settings.agents.sessions
            settings.agents.notifyPermission = reader.bool(s, "agents.notifyPermission") ?? settings.agents.notifyPermission
            settings.agents.notifyQuestion = reader.bool(s, "agents.notifyQuestion") ?? settings.agents.notifyQuestion
            settings.agents.notifyFinished = reader.bool(s, "agents.notifyFinished") ?? settings.agents.notifyFinished
            settings.agents.soundPermission = reader.string(s, "agents.soundPermission") ?? settings.agents.soundPermission
            settings.agents.soundQuestion = reader.string(s, "agents.soundQuestion") ?? settings.agents.soundQuestion
            settings.agents.soundFinished = reader.string(s, "agents.soundFinished") ?? settings.agents.soundFinished
            settings.agents.hiddenAccounts = reader.strings(s, "agents.hiddenAccounts") ?? settings.agents.hiddenAccounts
            settings.agents.accounts = reader.bool(s, "agents.accounts") ?? settings.agents.accounts
            settings.agents.launchSkipPermissions = reader.bool(s, "agents.launchSkipPermissions") ?? settings.agents.launchSkipPermissions
            settings.agents.activeAccount = reader.string(s, "agents.activeAccount") ?? settings.agents.activeAccount
            settings.agents.history = reader.bool(s, "agents.history") ?? settings.agents.history
            settings.agents.stateHooks = reader.bool(s, "agents.stateHooks") ?? settings.agents.stateHooks
            settings.agents.attention = reader.bool(s, "agents.attention") ?? settings.agents.attention
            settings.agents.dockBadge = reader.bool(s, "agents.dockBadge") ?? settings.agents.dockBadge
            if let minutes = reader.number(s, "agents.hibernateAfterMinutes") {
                settings.agents.hibernateAfterMinutes = min(max(Int(minutes), 0), 24 * 60)
            }
            settings.agents.mutedMachines = reader.strings(s, "agents.mutedMachines") ?? settings.agents.mutedMachines
            if let projects = s["projectAccounts"] {
                if let projects = projects as? [String: String] { settings.agents.projectAccounts = projects }
                else { reader.problems.append("agents.projectAccounts: esperava a conta por pasta de projeto") }
            }
            if let logins = s["hiddenLogins"] {
                if let logins = logins as? [String: String] { settings.agents.hiddenLogins = logins }
                else { reader.problems.append("agents.hiddenLogins: esperava o login por pasta") }
            }
            if let names = s["accountNames"] {
                if let names = names as? [String: String] { settings.agents.accountNames = names }
                else { reader.problems.append("agents.accountNames: esperava nomes por pasta") }
            }
        }
        if let s = reader.section(root, "computerUse") {
            settings.computerUse.enabled = reader.bool(s, "computerUse.enabled") ?? settings.computerUse.enabled
            settings.computerUse.allowedApps = s["allowedApps"] as? [String] ?? settings.computerUse.allowedApps
            settings.computerUse.blockedApps = s["blockedApps"] as? [String] ?? settings.computerUse.blockedApps
        }
        if let s = reader.section(root, "agentTools") {
            settings.agentTools.enabled = reader.bool(s, "agentTools.enabled") ?? settings.agentTools.enabled
            settings.agentTools.browser = reader.bool(s, "agentTools.browser") ?? settings.agentTools.browser
        }
        if let s = reader.section(root, "worktrees") {
            settings.worktrees.root = reader.string(s, "worktrees.root") ?? settings.worktrees.root
            if let hooks = s["setupHooks"] {
                if let hooks = hooks as? [String: [String]] { settings.worktrees.setupHooks = hooks }
                else { reader.problems.append("worktrees.setupHooks: esperava a lista de comandos por repositório") }
            }
        }
        if let s = reader.section(root, "git") {
            if let lines = reader.number(s, "git.reviewContextLines") { settings.git.reviewContextLines = min(max(Int(lines), 0), 50) }
            settings.git.reviewWrap = reader.bool(s, "git.reviewWrap") ?? settings.git.reviewWrap
            settings.git.reviewShowWhitespace = reader.bool(s, "git.reviewShowWhitespace") ?? settings.git.reviewShowWhitespace
        }
        if let s = reader.section(root, "review") {
            settings.review.authorship = reader.bool(s, "review.authorship") ?? settings.review.authorship
        }
        if let s = reader.section(root, "memory") {
            settings.memory.enabled = reader.bool(s, "memory.enabled") ?? settings.memory.enabled
            settings.memory.shareAcrossAccounts = reader.bool(s, "memory.shareAcrossAccounts") ?? settings.memory.shareAcrossAccounts
            settings.memory.consolidateInSession = reader.bool(s, "memory.consolidateInSession") ?? settings.memory.consolidateInSession
            if let percent = reader.number(s, "memory.consolidateAtContext") {
                settings.memory.consolidateAtContext = min(max(Int(percent), 10), 95)
            }
            settings.memory.backgroundAgent = reader.bool(s, "memory.backgroundAgent") ?? settings.memory.backgroundAgent
            if let budget = reader.number(s, "memory.dailyBudgetUsd") {
                settings.memory.dailyBudgetUsd = min(max(budget, 0), 50)
            }
            settings.memory.requireApproval = reader.bool(s, "memory.requireApproval") ?? settings.memory.requireApproval
        }
        if let s = reader.section(root, "ssh") {
            settings.ssh.ping = reader.bool(s, "ssh.ping") ?? settings.ssh.ping
        }
        if let s = reader.section(root, "orchestration") {
            var o = settings.orchestration
            o.enabled = reader.bool(s, "orchestration.enabled") ?? o.enabled
            o.automations = reader.bool(s, "orchestration.automations") ?? o.automations
            o.keepAwakeDuringRuns = reader.bool(s, "orchestration.keepAwakeDuringRuns") ?? o.keepAwakeDuringRuns
            // Bounds: at least 1 agent and 1 level, and a cap that is a cap.
            if let n = reader.number(s, "orchestration.maxAgents") { o.maxAgents = min(max(Int(n), 1), 20) }
            if let n = reader.number(s, "orchestration.maxDepth") { o.maxDepth = min(max(Int(n), 0), 5) }
            if let n = reader.number(s, "orchestration.heartbeatMinutes") { o.heartbeatMinutes = min(max(Int(n), 1), 120) }
            if let n = reader.number(s, "orchestration.defaultBudgetUsd") { o.defaultBudgetUsd = min(max(n, 0.1), 100) }
            if let n = reader.number(s, "orchestration.defaultMaxMinutes") { o.defaultMaxMinutes = min(max(Int(n), 1), 24 * 60) }
            settings.orchestration = o
        }
        if let s = reader.section(root, "machines") {
            settings.machines.tailscale = reader.bool(s, "machines.tailscale") ?? settings.machines.tailscale
            settings.machines.acceptRemote = reader.bool(s, "machines.acceptRemote") ?? settings.machines.acceptRemote
            if let users = s["users"] {
                if let users = users as? [String: String] { settings.machines.users = users }
                else { reader.problems.append("machines.users: esperava um usuário por máquina") }
            }
        }
        if let s = reader.section(root, "statusBar") {
            settings.statusBar.left = reader.strings(s, "statusBar.left") ?? settings.statusBar.left
            settings.statusBar.right = reader.strings(s, "statusBar.right") ?? settings.statusBar.right
        }
        if let s = reader.section(root, "shortcuts") {
            for (combo, value) in s {
                if value is NSNull { settings.shortcuts[combo] = .some(nil) }
                else if let id = value as? String { settings.shortcuts[combo] = .some(id) }
                else { reader.problems.append("shortcuts.\(combo): esperava o id de um comando ou null") }
            }
        }
        problems = reader.problems
        migrate(&settings, from: root["version"] as? Int ?? 1, root: root)
        return (settings, problems)
    }

    /// Moves an older file to the current defaults, once: a file of version 1
    /// still on the old default theme (Caffeine) goes to Cadex Night, the
    /// new frame's (docs/adr/0035-work-frame.md). Only `theme`: the dark and
    /// light themes were empty by default, so Caffeine there was a choice and
    /// stays (review of 2026-11-17). A file of a newer app keeps its version.
    /// SettingsStore saves right after, so it happens once.
    static func migrate(_ settings: inout Settings, from version: Int, root: [String: Any] = [:]) {
        if version < 2, settings.appearance.theme == "caffeine" { settings.appearance.theme = "cadex-night" }
        if version < 3 {
            // A side the old file did not write had the old default, not the new one (review of
            // 2026-11-17: a file with only `left` got the new frame's whole right side).
            let bar = root["statusBar"] as? [String: Any]
            if bar?["left"] == nil { settings.statusBar.left = ["folder"] }
            if bar?["right"] == nil { settings.statusBar.right = ["environment"] }
            migrateStatusBar(&settings.statusBar)
        }
        if version < 4 {
            // Files, Git, Git History and Memory went to the right panel and Accounts to the usage
            // item's card (plan 26 phases C and E): their ids leave the sidebar's list once.
            settings.sidebar.items.removeAll { movedOutOfSidebar.contains($0) }
        }
        settings.version = max(version, Settings.currentVersion)
    }

    /// The sidebar's pages that left it in plan 26 (migration 0035).
    static let movedOutOfSidebar: Set<String> = ["files", "git", "history", "memory", "accounts"]

    /// The new frame's status bar (plan 26 phase B): the old default becomes the new one; a bar
    /// someone arranged stays theirs, with Folder and Git branch shown together becoming Project,
    /// and keep-awake and the update joining on the right, since they leave the title bar where
    /// they were always in sight (docs/spec/status-bar.md).
    static func migrateStatusBar(_ bar: inout Settings.StatusBar) {
        let defaults = Settings.StatusBar()
        if bar.left == ["folder"] && bar.right == ["environment"] {
            bar = defaults
            return
        }
        let shown = bar.left + bar.right
        if shown.contains("folder") && shown.contains("branch") {
            bar.left = bar.left.map { $0 == "folder" ? "project" : $0 }.filter { $0 != "branch" }
            bar.right = bar.right.map { $0 == "folder" ? "project" : $0 }.filter { $0 != "branch" }
        }
        for id in ["keepAwake", "update"] where !(bar.left + bar.right).contains(id) { bar.right.append(id) }
    }

    /// The version a file says it has: 1 for a file from before versions.
    public static func version(of data: Data) -> Int {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["version"] as? Int ?? 1
    }

    public static func write(_ settings: Settings) -> Data {
        let s = settings
        var shortcuts: [String: Any] = [:]
        for (combo, id) in s.shortcuts { shortcuts[combo] = id ?? NSNull() }
        let object: [String: Any] = [
            "version": s.version,
            "general": ["shell": s.general.shell, "confirmClose": s.general.confirmClose,
                        "confirmMultilinePaste": s.general.confirmMultilinePaste, "openFiles": s.general.openFiles,
                        "language": s.general.language],
            "terminal": ["fontFamily": s.terminal.fontFamily, "fontSize": s.terminal.fontSize, "cursor": s.terminal.cursor,
                         "cursorBlink": s.terminal.cursorBlink, "historyLines": s.terminal.historyLines,
                         "optionAsMeta": s.terminal.optionAsMeta, "copyOnSelect": s.terminal.copyOnSelect,
                         "programNotifications": s.terminal.programNotifications, "keepSessions": s.terminal.keepSessions,
                         "minimumContrast": s.terminal.minimumContrast, "lineHeight": s.terminal.lineHeight,
                         "letterSpacing": s.terminal.letterSpacing, "fontFeatures": s.terminal.fontFeatures],
            "appearance": ["theme": s.appearance.theme, "lightTheme": s.appearance.lightTheme, "darkTheme": s.appearance.darkTheme,
                           "accent": s.appearance.accent, "mode": s.appearance.mode, "vibrancy": s.appearance.vibrancy,
                           "backgroundImage": s.appearance.backgroundImage ?? NSNull(),
                           "backgroundOpacity": s.appearance.backgroundOpacity, "backgroundBlur": s.appearance.backgroundBlur,
                           "highContrast": s.appearance.highContrast, "uiZoom": s.appearance.uiZoom,
                           "density": s.appearance.density, "uiFont": s.appearance.uiFont, "uiFontSize": s.appearance.uiFontSize],
            "tabs": ["unfocusedDim": s.tabs.unfocusedDim, "documentSide": s.tabs.documentSide, "paneHeaders": s.tabs.paneHeaders],
            "explorer": ["showHidden": s.explorer.showHidden, "followTerminal": s.explorer.followTerminal],
            "markdown": ["openAs": s.markdown.openAs],
            "preview": ["pickTarget": s.preview.pickTarget, "pickScreenshot": s.preview.pickScreenshot],
            "power": ["mode": s.power.mode, "onAtLaunch": s.power.onAtLaunch, "keepDisplayOn": s.power.keepDisplayOn],
            "sidebar": ["items": s.sidebar.items],
            "inspector": ["visible": s.inspector.visible, "tab": s.inspector.tab, "width": s.inspector.width],
            "statusBar": ["left": s.statusBar.left, "right": s.statusBar.right],
            "ssh": ["ping": s.ssh.ping],
            "machines": ["tailscale": s.machines.tailscale, "acceptRemote": s.machines.acceptRemote, "users": s.machines.users],
            "review": ["authorship": s.review.authorship],
            "orchestration": ["enabled": s.orchestration.enabled, "automations": s.orchestration.automations,
                              "maxAgents": s.orchestration.maxAgents, "maxDepth": s.orchestration.maxDepth,
                              "heartbeatMinutes": s.orchestration.heartbeatMinutes, "keepAwakeDuringRuns": s.orchestration.keepAwakeDuringRuns,
                              "defaultBudgetUsd": s.orchestration.defaultBudgetUsd, "defaultMaxMinutes": s.orchestration.defaultMaxMinutes],
            "memory": ["enabled": s.memory.enabled, "shareAcrossAccounts": s.memory.shareAcrossAccounts,
                       "consolidateInSession": s.memory.consolidateInSession, "consolidateAtContext": s.memory.consolidateAtContext,
                       "backgroundAgent": s.memory.backgroundAgent, "dailyBudgetUsd": s.memory.dailyBudgetUsd,
                       "requireApproval": s.memory.requireApproval],
            "git": ["reviewContextLines": s.git.reviewContextLines, "reviewWrap": s.git.reviewWrap,
                    "reviewShowWhitespace": s.git.reviewShowWhitespace],
            "worktrees": ["root": s.worktrees.root, "setupHooks": s.worktrees.setupHooks],
            "agentTools": ["enabled": s.agentTools.enabled, "browser": s.agentTools.browser],
            "computerUse": ["enabled": s.computerUse.enabled, "allowedApps": s.computerUse.allowedApps, "blockedApps": s.computerUse.blockedApps],
            "agents": ["sessions": s.agents.sessions, "notifyPermission": s.agents.notifyPermission,
                       "notifyQuestion": s.agents.notifyQuestion, "notifyFinished": s.agents.notifyFinished,
                       "soundPermission": s.agents.soundPermission, "soundQuestion": s.agents.soundQuestion,
                       "soundFinished": s.agents.soundFinished,
                       "accounts": s.agents.accounts, "accountNames": s.agents.accountNames, "hiddenAccounts": s.agents.hiddenAccounts,
                       "hiddenLogins": s.agents.hiddenLogins, "launchSkipPermissions": s.agents.launchSkipPermissions,
                       "activeAccount": s.agents.activeAccount, "projectAccounts": s.agents.projectAccounts,
                       "history": s.agents.history, "stateHooks": s.agents.stateHooks,
                       "attention": s.agents.attention, "dockBadge": s.agents.dockBadge, "mutedMachines": s.agents.mutedMachines,
                       "hibernateAfterMinutes": s.agents.hibernateAfterMinutes],
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
