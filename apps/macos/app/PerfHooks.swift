import Agents
import Machines
import AppKit
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
        if let id = environment["CADEX_PERF_COMMAND"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in _ = self?.commands.run(id) }
        }
        // The focused pane split to the right, to compare two panes with the Terminals mockup.
        if environment["CADEX_PERF_SPLIT"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in _ = self?.commands.run("pane.split-right") }
        }
        if environment["CADEX_PERF_HISTORY_OPEN"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in self?.panelHistory?.openFirstCommit() }
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
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out))
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
}
