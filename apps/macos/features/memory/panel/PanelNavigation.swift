import AppKit
import Strings

/// The routes each place reads, in the order its screen takes them (plan 40 D). Pure, so the tests
/// hold the paths.
public enum PanelLoads {
    public static func paths(_ place: PanelPlace) -> [String] {
        switch place {
        case .section: return []
        case .project(let p, _): return PanelProjectData.paths(p)
        case .page(let p, let path): return [p.api + "/pages/" + PanelPath.page(path), p.extra + "/evidence/" + PanelPath.page(path)]
        case .history(let p, let path, let from, let to):
            let query = [from.map { "from=" + PanelPath.value($0) }, to.map { "to=" + PanelPath.value($0) }].compactMap { $0 }
            return [p.api + "/history/" + PanelPath.page(path) + (query.isEmpty ? "" : "?" + query.joined(separator: "&"))]
        case .session(let p, let id, let offset):
            let session = "/sessions/" + PanelPath.segment(id)
            return [p.api + session + "/observations?offset=\(offset)&limit=\(PanelTimeline.pageSize)", p.extra + session + "/tokens"]
        case .retrievals(let p, let id, let offset):
            return [p.extra + "/sessions/" + PanelPath.segment(id) + "/retrievals" + (offset > 0 ? "?offset=\(offset)" : "")]
        case .agent(let p, let wire): return [p.extra + "/agents/" + PanelPath.segment(wire)]
        }
    }
}

/// Going from place to place inside the Memória page: a section, or a project's screen read from
/// the engine; back and forward through the places seen (⌘[ and ⌘], memory.panel-back and
/// memory.panel-forward).
public extension MemoryPanelDocument {
    /// Where the page is.
    var place: PanelPlace { trail.current }

    /// A click inside the page: through the app's command when there is one (ADR 0005).
    func navigate(_ next: PanelPlace) {
        if let go = actions.go { return go(next) }
        go(next)
    }

    /// The page at `next`, kept in the trail.
    func go(_ next: PanelPlace) {
        let before = trail.current
        trail.go(next)
        open(next, from: before)
    }

    @discardableResult
    func back() -> Bool {
        let before = trail.current
        guard let previous = trail.goBack() else { return false }
        open(previous, from: before)
        return true
    }

    @discardableResult
    func forward() -> Bool {
        let before = trail.current
        guard let next = trail.goForward() else { return false }
        open(next, from: before)
        return true
    }

    /// The place drawn: a section as before; the same project with another tab, in place; the
    /// rest read from the engine, then drawn (an older read arriving late draws nothing).
    internal func open(_ next: PanelPlace, from before: PanelPlace) {
        if case .section(let section) = next { return showSection(section) }
        section = .projects
        if case .project(let p, let tab) = next, case .project(let q, _) = before, p == q, let view = screen as? PanelProjectView {
            return view.select(tab)
        }
        generation += 1
        let mine = generation
        let paths = PanelLoads.paths(next)
        readAll(paths, into: []) { [weak self] answers in
            guard let self, self.generation == mine else { return }
            guard let made = self.make(next, answers) else {
                let words = answers.compactMap { answer -> String? in
                    if case .failure(let e) = answer { return e.words }
                    return nil
                }.first
                return self.show(failed: words ?? T("This screen's data did not read.", "Os dados desta tela não foram lidos."))
            }
            self.screen = made
            made.onBack = { [weak self] in self?.runBack() }
            made.onForward = { [weak self] in self?.runForward() }
            self.place(made)
            made.window?.makeFirstResponder(made)
        }
    }

    /// One at a time: the first read may start the engine, and reads at once raced to start it
    /// (MemoryPanelWiring, 2026-11-19).
    private func readAll(_ paths: [String], into answers: [Result<Data, PanelReadError>], done: @escaping @MainActor ([Result<Data, PanelReadError>]) -> Void) {
        guard let path = paths.first else { return done(answers) }
        actions.read(path) { [weak self] answer in
            guard let self else { return }
            self.readAll(Array(paths.dropFirst()), into: answers + [answer], done: done)
        }
    }

    private func show(failed words: String) {
        screen = nil
        place(PanelEmpty.view(T("Memory did not answer", "A memória não respondeu"), words))
    }

    /// Back and forward from the keys: through the app's commands when it gave them.
    private func runBack() { if let run = actions.back { run() } else { back() } }
    private func runForward() { if let run = actions.forward { run() } else { forward() } }

    /// What memory.open-in-cadex from ⌘K acts on in a project's screen: the session chosen in a
    /// list or shown, else the project; nil on a section.
    var chosenForCadex: (PanelProjectRef, String?)? {
        guard let p = place.project else { return nil }
        switch screen {
        case let view as PanelSessionView: return (p, view.timeline.session.id)
        case let view as PanelAgentView: return (p, view.list?.chosenSession?.id)
        case let view as PanelProjectView: return (p, view.sessionList?.chosenSession?.id)
        default: return (p, nil)
        }
    }

    /// The screen of `next` from its answers; nil when the first does not parse.
    internal func make(_ next: PanelPlace, _ answers: [Result<Data, PanelReadError>]) -> PanelScreen? {
        let data = answers.map { try? $0.get() }
        let go: (PanelPlace) -> Void = { [weak self] place in self?.navigate(place) }
        var project = actions.project
        project.read = { [weak self] path, done in self?.actions.read(path) { done(try? $0.get()) } ?? done(nil) }
        // "Abrir no Cadex" only where a Cadex project has the memory project's folder.
        if let p = next.project, !project.inCadex(p) { project.openInCadex = nil }
        switch next {
        case .section: return nil
        case .project(let p, let tab):
            guard let read = PanelProjectData.parse(p, data) else { return nil }
            return PanelProjectView(p, data: read, tab: tab, actions: project, go: go)
        case .page(let p, _):
            guard let page = PanelPageDetail.parse(data[0]) else { return nil }
            return PanelPageView(p, page: page, evidence: PanelEvidence.parse(data.count > 1 ? data[1] : nil) ?? PanelEvidence(), go: go)
        case .history(let p, _, _, _):
            guard let history = PanelHistory.parse(data[0]) else { return nil }
            return PanelHistoryView(p, history: history, go: go)
        case .session(let p, _, _):
            guard let timeline = PanelTimeline.parse(data[0]) else { return nil }
            var acts = PanelSessionScreenActions()
            acts.read = project.read
            if let open = project.openInCadex { acts.openInCadex = { open(p, $0) } }
            return PanelSessionView(p, timeline: timeline, tokens: PanelTokenReport.parse(data.count > 1 ? data[1] : nil) ?? PanelTokenReport(),
                                    actions: acts, go: go)
        case .retrievals(let p, let id, _):
            guard let read = PanelRetrievals.parse(data[0]) else { return nil }
            return PanelRetrievalsView(p, session: id, retrievals: read, go: go)
        case .agent(let p, _):
            guard let read = PanelAgentData.parse(data[0]) else { return nil }
            return PanelAgentView(p, data: read, actions: project, go: go)
        }
    }
}
