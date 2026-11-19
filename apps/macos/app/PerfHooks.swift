import Menus
import Agents
import Machines
import AppKit
import Strings
import UILooks
import Orchestration
import Tabs
import Terminal
import Home
import SourceControl

/// `make perf` only (tools/perf/run.py): what a scenario asks the test app
/// to do on its own, at set times, so it is measured with no click. Each
/// hook reads one variable and does nothing without it.
extension WindowSession {
    func startPerfHooks() {
        let environment = ProcessInfo.processInfo.environment
        if let path = environment["CADEX_PERF_SUBAGENT_LOG"] { openPerfTranscript(path) }
        if let count = environment["CADEX_PERF_TABS"].flatMap(Int.init) { openPerfTabs(count) }
        if let out = environment["CADEX_PERF_REVIEW"] { openPerfReview(out) }
        if let out = environment["CADEX_PERF_MACHINES"] { openPerfMachines(out) }
        if let file = environment["CADEX_PERF_RACE"] { startPerfRace(file) }
        if let file = environment["CADEX_PERF_RUN"] { startPerfRun(file) }
        if environment["CADEX_PERF_PRESS"] != nil { startPerfPresses() }
        if let tab = environment["CADEX_PERF_PANEL"] { showPerfPage(tab) }
        // Files shown down to these paths (comma-separated), the last one chosen: the tree as a
        // mockup draws it, to compare them (2026-11-17).
        // A command typed in the focused terminal once its shell is ready: a real `claude` in the
        // pane, to compare its header with the Pane mockup (plan 28 phase B).
        if let command = environment["CADEX_PERF_TYPE"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.tabs?.activeTerminal?.typeWhenReady(command + "\n") }
        }
        // A message sent to the agent as the owner does: the text, then Return as a key event (it
        // marks the scrollbar), at CADEX_PERF_SEND_AT seconds (plan 28 phase D, seen in the app).
        if let message = environment["CADEX_PERF_SEND"] {
            let at = environment["CADEX_PERF_SEND_AT"].flatMap(Double.init) ?? 15
            DispatchQueue.main.asyncAfter(deadline: .now() + at) { [weak self] in
                guard let terminal = self?.tabs?.activeTerminal else { return }
                terminal.insertText(message, replacementRange: NSRange(location: NSNotFound, length: 0))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                                   context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36) {
                        terminal.keyDown(with: key)
                    }
                }
            }
        }
        // A page opened beside the focused terminal, to compare with the PreviewOne mockup.
        if let url = environment["CADEX_PERF_PREVIEW"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.openPreview(url, beside: true) }
        }
        // The home screen's prompt sent as the owner's Enter (plan 29 phase A).
        if let prompt = environment["CADEX_PERF_HOME_PROMPT"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.home?.actions.submit(prompt) }
        }
        // Every terminal's screen as text, at CADEX_PERF_DUMP_SCREEN_AT seconds, into the file named.
        if let out = environment["CADEX_PERF_DUMP_SCREEN"] {
            let at = environment["CADEX_PERF_DUMP_SCREEN_AT"].flatMap(Double.init) ?? 10
            DispatchQueue.main.asyncAfter(deadline: .now() + at) { [weak self] in
                let screens = (self?.projects?.projects ?? []).flatMap { $0.tabs.allTerminals }.enumerated().map { index, terminal in
                    "== terminal \(index + 1)\n" + terminal.screenLines().map { $0.replacingOccurrences(of: " +$", with: "", options: .regularExpression) }
                        .filter { !$0.isEmpty }.joined(separator: "\n")
                }
                try? screens.joined(separator: "\n").write(toFile: out, atomically: true, encoding: .utf8)
            }
        }
        // Clone… without its two questions: "<address>|<parent folder>" (plan 29 phase A).
        if let clone = environment["CADEX_PERF_HOME_CLONE"], let bar = clone.firstIndex(of: "|") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.homeCloneRun(String(clone[..<bar]), into: String(clone[clone.index(after: bar)...]))
            }
        }
        // A command by its id, as the palette runs it (the New Task sheet, plan 29 phase B).
        // An open permission request with no agent (plan 38 C, to see the needs-you queue):
        // "project|who|tool|subject" at CADEX_PERF_REQUEST_AT s.
        if let spec = environment["CADEX_PERF_REQUEST"]?.split(separator: "|").map(String.init), spec.count == 4 {
            let at = environment["CADEX_PERF_REQUEST_AT"].flatMap(Double.init) ?? 3
            DispatchQueue.main.asyncAfter(deadline: .now() + at) {
                _ = AgentAttention.shared.addPermission(pid: 0, tool: spec[2], subject: spec[3], project: spec[0], session: spec[1],
                                                    account: "bkdg", key: nil, reply: { _ in })
            }
        }
        if let id = environment["CADEX_PERF_COMMAND"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in _ = self?.commands.run(id) }
        }
        // A second command later (⌘J over what the first one started).
        if let id = environment["CADEX_PERF_COMMAND2"] {
            let at = environment["CADEX_PERF_COMMAND2_AT"].flatMap(Double.init) ?? 10
            DispatchQueue.main.asyncAfter(deadline: .now() + at) { [weak self] in _ = self?.commands.run(id) }
        }
        // A menu shown for a capture (the owner's review, 2026-11-18): "new" (the tabs' "+"), "pane"
        // (a pane's "+"), at CADEX_PERF_MENU_AT s, under the title bar's search.
        if let spec = environment["CADEX_PERF_DRAG"] {
            startPerfDrag(spec, at: environment["CADEX_PERF_DRAG_AT"].flatMap(Double.init) ?? 6)
        }
        if let spec = environment["CADEX_PERF_CLICK"] {
            startPerfClicks(spec, at: environment["CADEX_PERF_CLICK_AT"].flatMap(Double.init) ?? 5,
                            gap: environment["CADEX_PERF_CLICK_GAP"].flatMap(Double.init) ?? 1.5)
        }
        if let spec = environment["CADEX_PERF_HOVER"] {
            startPerfHover(spec, at: environment["CADEX_PERF_HOVER_AT"].flatMap(Double.init) ?? 5)
        }
        if let which = environment["CADEX_PERF_MENU"] {
            let at = environment["CADEX_PERF_MENU_AT"].flatMap(Double.init) ?? 3
            DispatchQueue.main.asyncAfter(deadline: .now() + at) { [weak self] in
                guard let self, let anchor = self.workspace?.titleBar else { return }
                let entries = which == "pane" ? self.paneMenu() : self.newTabMenu()
                PopupMenu.show(entries, below: anchor)
            }
        }
        // Plan 33 E: the focused Claude goes on in the account of this folder at CADEX_PERF_SWITCH_AT s,
        // as a click on it in the pane's header; the limit notices looked at at CADEX_PERF_LIMIT_AT s.
        if let dir = environment["CADEX_PERF_SWITCH"] {
            let at = environment["CADEX_PERF_SWITCH_AT"].flatMap(Double.init) ?? 25
            DispatchQueue.main.asyncAfter(deadline: .now() + at) { [weak self] in
                guard let account = AgentsController.shared.everyAccount().first(where: { $0.dir == dir }) else { return NSLog("Cadex script: no account %@", dir) }
                // As the title bar's list: a focused Claude goes on there; a shell picks the next one's.
                self?.chooseAccount(account)
            }
        }
        if let at = environment["CADEX_PERF_LIMIT_AT"].flatMap(Double.init) {
            DispatchQueue.main.asyncAfter(deadline: .now() + at) { [weak self] in self?.refreshLimitCards() }
        }
        // The home screen clicked as the owner would: "card:task", "recent:<folder>" (plan 29).
        if let action = environment["CADEX_PERF_HOME_ACTION"], let colon = action.firstIndex(of: ":") {
            let kind = String(action[..<colon]), value = String(action[action.index(after: colon)...])
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let home = self?.home else { return }
                if kind == "recent" { return home.actions.openRecent(value) }
                if let card = HomeCard.allCases.first(where: { "\($0)" == value }) { home.actions.card(card) }
            }
        }
        // ⌘J's list searched with this text and its last item chosen, as the palette does (the text
        // that finds nothing becomes New Task's request); "first:" chooses the first item instead.
        if let query = environment["CADEX_PERF_JUMP"] {
            let at = environment["CADEX_PERF_JUMP_AT"].flatMap(Double.init) ?? 6
            DispatchQueue.main.asyncAfter(deadline: .now() + at) { [weak self] in
                guard let self else { return }
                let source = JumpSource(window: self)
                let first = query.hasPrefix("first:")
                source.search(first ? String(query.dropFirst(6)) : query) { items, _ in
                    guard let item = first ? items.first : items.last else { return }
                    source.choose(item)
                    source.stop()
                }
            }
        }
        // A key pressed as the keyboard sends it, to the key window (⌘1 with ⌘J open), at
        // CADEX_PERF_KEY_AT seconds: "1" is ⌘1; it goes through the shortcuts' monitor as a real one.
        if let digit = environment["CADEX_PERF_KEY"], let code = ["1": 18, "2": 19, "3": 20][digit] {
            let at = environment["CADEX_PERF_KEY_AT"].flatMap(Double.init) ?? 10
            DispatchQueue.main.asyncAfter(deadline: .now() + at) {
                guard let target = NSApp.keyWindow ?? NSApp.windows.first(where: { $0 is NSPanel && $0.isVisible }),
                      let press = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: ProcessInfo.processInfo.systemUptime,
                                                   windowNumber: target.windowNumber, context: nil, characters: digit,
                                                   charactersIgnoringModifiers: digit, isARepeat: false, keyCode: UInt16(code)) else { return }
                NSApp.sendEvent(press)
            }
        }
        // What the window shows, as JSON, at CADEX_PERF_REPORT_AT seconds (the checks of plan 29).
        if let out = environment["CADEX_PERF_REPORT"] {
            let at = environment["CADEX_PERF_REPORT_AT"].flatMap(Double.init) ?? 8
            DispatchQueue.main.asyncAfter(deadline: .now() + at) { [weak self] in
                guard let self else { return }
                let projects = (self.projects?.projects ?? []).map { project -> [String: Any] in
                    ["name": project.name, "tabs": project.tabs.count,
                     "terminals": project.tabs.allTerminals.map { $0.currentDirectory ?? "" },
                     "focused": project.tabs.activeTerminal?.currentDirectory ?? "",
                     "programs": project.tabs.allTerminals.map { $0.programTitle }]
                }
                var report: [String: Any] = ["projects": projects, "active": self.projects?.activeName ?? "", "home": self.home != nil,
                                             "palette": self.palette?.currentSource?.placeholder ?? ""]
                if let sheet = self.newTaskSheet {
                    report["sheet"] = ["agents": sheet.request.agents.map(\.title), "prompt": sheet.request.prompt, "race": sheet.request.isRace]
                }
                // Every inspector tab button on screen, with its label's look (a stale bold, 2026-11-17).
                func buttons(_ v: NSView) -> [NSView] { (String(describing: type(of: v)).contains("InspectorTabButton") ? [v] : []) + v.subviews.flatMap(buttons) }
                report["inspectorTabs"] = buttons(self.window.contentView?.superview ?? NSView()).map { button -> String in
                    let label = button.subviews.compactMap { $0 as? NSTextField }.first
                    let frame = button.convert(button.bounds, to: nil)
                    return "\(label?.stringValue ?? "?") x=\(Int(frame.minX)) y=\(Int(frame.minY)) bold=\(label?.font?.fontDescriptor.symbolicTraits.contains(.bold) ?? false) hidden=\(button.isHiddenOrHasHiddenAncestor)"
                }
                // The tab strip's titles as drawn (TabBarView's tab views' labels).
                func labels(_ v: NSView) -> [String] { ((v as? NSTextField).map { [$0.stringValue] } ?? []) + v.subviews.flatMap(labels) }
                report["tabStrip"] = self.tabs.map { labels($0.bar) } ?? []
                // The right panel's words (its scope row comes first), and the bell's cards' words.
                func texts(_ v: NSView) -> [String] {
                    guard !v.isHidden else { return [] }
                    return ((v as? NSTextField).map { [$0.stringValue] } ?? []) + v.subviews.flatMap(texts)
                }
                report["inspectorTexts"] = self.workspace.map { [$0.inspector.tab] + Array(texts($0.inspector).filter { !$0.isEmpty }.prefix(8)) } ?? []
                report["panels"] = NSApp.windows.filter { $0 is NSPanel && $0.isVisible }.map { panel in texts(panel.contentView ?? NSView()).filter { !$0.isEmpty } }
                report["commands"] = ["home.show", "tab.new", "agents.open-account", "worktrees.new-task", "worktrees.new-race", "view.jump"]
                    .filter { self.commands.command($0) != nil }
                if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                    try? data.write(to: URL(fileURLWithPath: out))
                }
            }
        }
        // A scene in steps, for the comparisons with the mockups: a JSON list of {"at": seconds, and
        // one of "command": id, "type": text in the focused terminal, "tab": text in a new tab of
        // its folder, "split": text in a pane split to the right ("split-down": below)}.
        if let file = environment["CADEX_PERF_SCRIPT"], let data = FileManager.default.contents(atPath: file),
           let steps = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            for step in steps {
                let at = (step["at"] as? NSNumber)?.doubleValue ?? 3
                DispatchQueue.main.asyncAfter(deadline: .now() + at) { [weak self] in
                    guard let self else { return }
                    if let id = step["command"] as? String, !self.commands.run(id) {
                        NSLog("Cadex script: %@ did not run: %@", id, self.commands.command(id)?.unavailableReason() ?? "unknown")
                    }
                    // The settings window's page scrolled to a fraction of its height (1: the end).
                    if let at = (step["scrollSettings"] as? NSNumber)?.doubleValue,
                       let settings = NSApp.windows.first(where: { $0.title == T("Settings", "Configurações") }),
                       let scroll = Self.firstScroll(in: settings.contentView, skipping: 0) {
                        let document = scroll.documentView?.bounds.height ?? 0
                        let room = max(document - scroll.contentView.bounds.height, 0)
                        scroll.contentView.scroll(to: NSPoint(x: 0, y: room * at))
                        scroll.reflectScrolledClipView(scroll.contentView)
                    }
                    // The terminal's find bar, as ⌘F opens it with the terminal focused.
                    if step["find"] as? Bool == true { self.tabs?.activeTerminal?.showFind(nil) }
                    // The repository's history in a tab, as the History tab opens it.
                    if step["history"] as? Bool == true, let repo = self.mainRepository { self.opener?.openHistory(repo) }
                    // A file's diff, as a click on it in Changes opens it.
                    if let path = step["diff"] as? String, let repo = self.mainRepository {
                        self.opener?.openDiff(.init(repo: repo, path: path, orig: path, staged: false), beside: nil)
                    }
                    // The newest race as its page of cards.
                    if step["raceBoard"] as? Bool == true, let book = OrchestrationController.shared.races(),
                       let race = ((try? book.races()) ?? []).max(by: { $0.createdAt < $1.createdAt }) {
                        self.showRaceBoard(race.id)
                    }
                    // The newest run's page (its command asks which in the palette).
                    if step["runPage"] as? Bool == true, let book = OrchestrationController.shared.runs(),
                       let run = ((try? book.store.all(.runs)) as [Run]?)?.max(by: { $0.createdAt < $1.createdAt }) {
                        self.showRun(run.id)
                    }
                    if let text = step["type"] as? String { self.tabs?.activeTerminal?.typeWhenReady(text + "\n") }
                    if let text = step["tab"] as? String {
                        self.tabs?.newTab(cwd: self.tabs?.activeTerminal?.currentDirectory)
                        self.tabs?.activeTerminal?.typeWhenReady(text + "\n")
                    }
                    for (key, command) in [("split", "pane.split-right"), ("split-down", "pane.split-down")] {
                        guard let text = step[key] as? String else { continue }
                        _ = self.commands.run(command)
                        self.tabs?.activeTerminal?.typeWhenReady(text + "\n")
                    }
                }
            }
        }
        // The focused pane split to the right, to compare two panes with the Terminals mockup.
        if environment["CADEX_PERF_SPLIT"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in _ = self?.commands.run("pane.split-right") }
        }
        if let paths = environment["CADEX_PERF_REVEAL"]?.split(separator: ",").map(String.init) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                for path in paths { self?.explorer?.reveal(path) }
            }
        }
        // The window at a mockup's size ("1440x900"), to compare them pixel for pixel.
        if let size = environment["CADEX_PERF_WINDOW"]?.split(separator: "x").compactMap({ Double($0) }), size.count == 2 {
            window.setContentSize(NSSize(width: size[0], height: size[1]))
        }
        if let out = environment["CADEX_PERF_SNAPSHOT"] { savePerfSnapshot(out) }
    }

    /// The window drawn into a PNG at 4 s, then at `out`: a test window often opens on another
    /// Space, where screencapture fails (2026-11-17, the right panel's fidelity check).
    private func savePerfSnapshot(_ out: String) {
        // CADEX_PERF_SNAPSHOT_AT: later, when what is shown takes longer (a `claude` starting).
        let at = ProcessInfo.processInfo.environment["CADEX_PERF_SNAPSHOT_AT"].flatMap(Double.init) ?? 4
        DispatchQueue.main.asyncAfter(deadline: .now() + at) { [weak self] in
            guard let view = self?.window.contentView?.superview ?? self?.window.contentView,
                  let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            // Drawn now: a window off screen (another Space) skips the display cycle, and a text
            // changed since kept its old picture in the capture (the inspector's tab, 2026-11-17).
            func redraw(_ v: NSView) { v.needsDisplay = true; v.subviews.forEach(redraw) }
            redraw(view)
            view.layoutSubtreeIfNeeded()
            view.displayIfNeeded()
            view.cacheDisplay(in: view.bounds, to: bitmap)
            // The terminals are Metal layers the capture leaves blank: each drawn over its place.
            if let context = NSGraphicsContext(bitmapImageRep: bitmap) {
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = context
                func terminals(_ v: NSView) -> [TerminalView] { ((v as? TerminalView).map { [$0] } ?? []) + v.subviews.flatMap(terminals) }
                // A view over the terminals (the drawer) stays on top: the ones under it are cut out.
                func drawers(_ v: NSView) -> [NSView] { (v is DrawerView ? [v] : []) + v.subviews.flatMap(drawers) }
                // And a card at a terminal's foot (TerminalView.footCard, plan 33): the picture covered it.
                let overlays = drawers(view) + terminals(view).compactMap(\.footCard).filter { $0.superview != nil }
                for terminal in terminals(view) where terminal.window != nil && !terminal.isHiddenOrHasHiddenAncestor {
                    guard let picture = terminal.snapshotImage() else { continue }
                    let rect = terminal.convert(terminal.bounds, to: view)
                    NSGraphicsContext.saveGraphicsState()
                    let covering = overlays.filter { !terminal.isDescendant(of: $0) }.map { $0.convert($0.bounds, to: view) }
                    if !covering.isEmpty {
                        let clip = NSBezierPath(rect: view.bounds)
                        covering.forEach { clip.append(NSBezierPath(rect: $0)) }
                        clip.windingRule = .evenOdd
                        clip.addClip()
                    }
                    NSImage(cgImage: picture, size: rect.size).draw(in: rect)
                    NSGraphicsContext.restoreGraphicsState()
                }
                NSGraphicsContext.restoreGraphicsState()
            }
            try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out))
            // Another window (Settings): next to it, -window.png.
            for other in NSApp.windows where other !== self?.window && !(other is NSPanel) && other.isVisible {
                guard let content = other.contentView?.superview ?? other.contentView,
                      let shot = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { continue }
                content.cacheDisplay(in: content.bounds, to: shot)
                try? shot.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: (out as NSString).deletingPathExtension + "-window.png"))
            }
            // The New Task sheet sits over the terminals, which are drawn over it above: on its
            // own, next to it, -sheet.png.
            if let content = self?.newTaskSheet ?? self?.window.contentView?.subviews.first(where: { $0 is FrameSheet }), let shot = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
                content.cacheDisplay(in: content.bounds, to: shot)
                try? shot.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: (out as NSString).deletingPathExtension + "-sheet.png"))
            }
            // A panel over it (the palette, ⌘J) is a window of its own: next to it, -panel.png.
            for panel in NSApp.windows where panel is NSPanel && panel.isVisible {
                guard let content = panel.contentView?.superview ?? panel.contentView,
                      let shot = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { continue }
                content.cacheDisplay(in: content.bounds, to: shot)
                try? shot.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: (out as NSString).deletingPathExtension + "-panel.png"))
            }
        }
    }

    /// A right panel's tab, or Archive & history ("agent-history"), shown from the start: a
    /// scenario that wants one open asks for it (found 2026-11-14: the History "open" scenario
    /// had never shown the page).
    private func showPerfPage(_ page: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, let workspace = self.workspace else { return }
            // The history became a tab in the center (plan 27 phase C): its command opens it.
            if page == "agent-history" { _ = self.commands.run("agents.show-history"); return }
            if workspace.inspector.known.contains(page) { workspace.showInspector(page) } else { workspace.showTree() }
        }
    }

    /// That log's conversation opened at 12 s and 48 s and closed 12 s
    /// after each: the first opening's one-time cost apart from each
    /// opening's, and what stays once closed. 24 s between a close and the
    /// next opening: closing peaks for 1-2 s and settles about 12 s later
    /// (curve of 2026-11-16), and the measure waits for that.
    private func openPerfTranscript(_ path: String) {
        for start in [12.0, 48.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + start) { [weak self] in
                self?.tabs?.open(AgentTranscriptDocument(path: path, title: "perf", detail: "", colors: Self.agentColors()), beside: false)
            }
            // Its tab has the focus: closing the focused pane closes it.
            DispatchQueue.main.asyncAfter(deadline: .now() + start + 12) { [weak self] in
                if self?.tabs?.activeDocument is AgentTranscriptDocument { self?.tabs?.closeFocusedPane() }
            }
        }
    }

    /// `count` more terminal tabs, one a second from 12 s, then back to the
    /// first: what each terminal tab weighs, shown and hidden.
    private func openPerfTabs(_ count: Int) {
        for index in 0..<count {
            DispatchQueue.main.asyncAfter(deadline: .now() + 12 + Double(index)) { [weak self] in self?.tabs?.newTab() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 14 + Double(count)) { [weak self] in self?.tabs?.select(position: 1) }
    }

    /// Plan 23: the SSH card's Tailnet group "open" for 20 s (its reading,
    /// pings and watch stream, and the group built at each change, as the
    /// card does), then closed; `out` gets "closed <machines>" each time.
    private func openPerfMachines(_ out: String) {
        // Twice, at 12 s and 44 s: the first opening's one-time cost (the
        // text system and the dots' layers) apart from each opening's.
        for (start, last) in [(12.0, false), (44.0, true)] {
            DispatchQueue.main.asyncAfter(deadline: .now() + start) {
                let token = MachinesController.shared.watch {
                    _ = MachinesSection.make(width: 272, text: .white, secondary: .gray) { _ in }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
                    MachinesController.shared.stop(token)
                    let count = MachinesController.shared.status?.others.count ?? 0
                    try? (last ? "closed \(count) twice" : "closed \(count)").write(toFile: out, atomically: true, encoding: .utf8)
                }
            }
        }
    }

    /// Plan 21: the folder's review opened at 12 s; the seconds until it is
    /// read and laid out go to `out` ("open 0.84"), then 15 s of moving
    /// through the changes, back and forth, and "scrolled".
    private func openPerfReview(_ out: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
            guard let self else { return }
            let start = Date()
            openReview(repo: folder.root)
            guard let review = tabs?.activeDocument as? ReviewDocument else { return }
            let before = review.onLoaded
            var first = true
            review.onLoaded = { [weak review] in
                before?()
                guard first, let review else { return }
                first = false
                try? "open \(Date().timeIntervalSince(start))\n".write(toFile: out, atomically: true, encoding: .utf8)
                // CADEX_PERF_REVIEW_STILL: opened, not scrolled (what opening alone weighs).
                let still = ProcessInfo.processInfo.environment["CADEX_PERF_REVIEW_STILL"] != nil
                Self.scroll(review, until: Date().addingTimeInterval(still ? 0 : 15), forward: true, out: out)
            }
        }
    }

    private static func scroll(_ review: ReviewDocument, until end: Date, forward: Bool, out: String) {
        guard Date() < end else {
            let opened = (try? String(contentsOfFile: out, encoding: .utf8)) ?? ""
            try? (opened + "scrolled\n").write(toFile: out, atomically: true, encoding: .utf8)
            return
        }
        let row = review.cursorRow
        if forward { review.nextChange() } else { review.previousChange() }
        let turn = review.cursorRow == row
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak review] in
            if let review { scroll(review, until: end, forward: turn ? !forward : forward, out: out) }
        }
    }

    /// The `skipping`-th scroll view under `view`, depth first (0: the settings window's page).
    static func firstScroll(in view: NSView?, skipping: Int) -> NSScrollView? {
        var found: [NSScrollView] = []
        func walk(_ v: NSView) {
            if let scroll = v as? NSScrollView { found.append(scroll) }
            v.subviews.forEach(walk)
        }
        if let view { walk(view) }
        return found.count > skipping ? found[skipping] : found.last
    }
}
