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
        case .search(let query): return [query.path]
        case .graph(let p?): return [p.api + "/graph", p.api + "/pages"]
        case .graph(nil): return ["api/v1/graph"]
        case .mailbox(let query): return [query.path]
        case .workstreams(let page): return ["extra/workstreams" + (page > 1 ? "?page=\(page)" : "")]
        case .review(let query): return [query.path]
        case .health: return ["extra/health"]
        // The guides are a list of the app's (PanelGuides.swift): nothing to read.
        case .docs: return []
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
    func go(_ place: PanelPlace) {
        let next = place.normalized
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
        section = next.section
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
            made.window?.makeFirstResponder(made.firstFocus)
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

    /// The place read again (the inbox after a save or a discard, as upstream reloads its page).
    func reload() { open(trail.current, from: trail.current) }

    /// A write from the inbox: through the app's command when there is one (ADR 0005).
    func send(_ write: PanelWrite) {
        if let message = actions.message { return message(write) }
        perform(write)
    }

    /// The write done: the engine's answer goes to the screen that asked (the inbox, the review, the
    /// health); a decision made from ⌘K with the page elsewhere reaches no screen.
    func perform(_ write: PanelWrite, then: (@MainActor () -> Void)? = nil) {
        actions.write(write.path, write.body) { [weak self] answer in
            (self?.screen as? PanelWriting)?.finished(write, answer)
            then?()
        }
    }

    /// A fix the owner did not confirm: its button back.
    func fixCancelled(_ what: String) { (screen as? PanelHealthView)?.cancelled(what) }

    /// A guide opens on GitHub (memory.open-guide, ADR 0005), or the page opens it itself.
    func openGuide(_ guide: PanelGuide) {
        if let open = actions.openGuide { return open(guide) }
        NSWorkspace.shared.open(guide.url)
    }

    /// The inbox is on screen (the message commands' availability).
    var showsInbox: Bool { screen is PanelInboxView }

    /// A graph is on screen (memory.graph-fit's availability).
    var showsGraph: Bool { screen is PanelGraphView }

    /// memory.graph-fit: the graph shown, zoom and pan undone.
    func fitGraph() { (screen as? PanelGraphView)?.canvas.fit() }

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

    /// The search screen; a hit opens its page with the search kept for the page's "why".
    private func makeSearch(_ result: PanelSearchResult, go: @escaping (PanelPlace) -> Void) -> PanelSearchView {
        PanelSearchView(result, open: { [weak self] hit in
            self?.recall[PanelHitKey(project: hit.project, path: hit.path)] = result.query
            go(.page(hit.project, hit.path))
        }, go: go)
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
        case .page(let p, let path):
            guard let page = PanelPageDetail.parse(data[0]) else { return nil }
            return PanelPageView(p, page: page, evidence: PanelEvidence.parse(data.count > 1 ? data[1] : nil) ?? PanelEvidence(),
                                 recall: recall[PanelHitKey(project: p, path: path)], read: project.read, go: go)
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
        case .search:
            guard let read = PanelSearchResult.parse(data[0]) else { return nil }
            return makeSearch(read, go: go)
        case .graph(let p?):
            guard let read = PanelGraph.parse(project: p, graph: data[0], pages: data.count > 1 ? data[1] : nil) else { return nil }
            return PanelGraphView(read, go: go)
        case .graph(nil):
            guard let read = PanelGraph.parse(global: data[0]) else { return nil }
            return PanelGraphView(read, go: go)
        case .mailbox(let query):
            guard let read = PanelMailbox.parse(data[0], query: query) else { return nil }
            return PanelInboxView(read, write: { [weak self] in self?.send($0) }, reload: { [weak self] in self?.reload() }, go: go)
        case .workstreams:
            guard let read = PanelWorkstreams.parse(data[0]) else { return nil }
            return PanelWorkstreamsView(read, go: go)
        case .review(let query):
            guard let read = PanelReview.parse(data[0], query: query) else { return nil }
            return PanelReviewView(read, write: { [weak self] in self?.send($0) }, reload: { [weak self] in self?.reload() }, go: go)
        case .health:
            guard let read = PanelHealth.parse(data[0]) else { return nil }
            // What a fix did survives the read again it asks for, once.
            let said = healthSaid
            healthSaid = nil
            return PanelHealthView(read, said: said, write: { [weak self] in self?.send($0) }, reload: { [weak self] said in
                self?.healthSaid = said
                self?.reload()
            }, go: go)
        case .docs(let words, let history):
            return PanelDocsView(words: words, history: history, open: { [weak self] in self?.openGuide($0) }, go: go)
        }
    }
}
