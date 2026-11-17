import Foundation

/// What a supervised agent asks of its run, besides its own reports
/// (docs/adr/0033-cadex-launches-agents.md, the agent's list): spawning a
/// sub-task within orchestration.maxDepth, a question to the coordinator
/// or the owner, a message to another dispatch of the same run, and reading
/// its own inbox. Every call names the dispatch it comes from; the app has
/// already matched that dispatch to the caller's session token.
extension RunBook {
    /// `orchestration.spawn`: a task of the same run, one deeper than the
    /// caller's, depending on nothing (the coordinator wires it); refused at
    /// orchestration.maxDepth. The spec is text kept in the store, never run.
    public func spawn(from id: String, title: String, spec: String, maxDepth: Int) throws -> RunTask {
        guard let parent: Dispatch = try store.get(.dispatches, id: id), RunGraph.live([parent]).count == 1 else {
            throw RunError.alreadyEnded(id)
        }
        guard let task: RunTask = try store.get(.tasks, id: parent.task) else { throw RunError.unknown(parent.task) }
        guard RunGraph.maySpawn(parentDepth: task.depth, maxDepth: maxDepth) else { throw RunError.tooDeep(maxDepth) }
        try sign(id)
        return try addTask(run: parent.run, title: title, spec: spec, spawnedBy: id, depth: task.depth + 1)
    }

    /// `orchestration.ask`: to the coordinator when the run has an agent
    /// coordinating, else to the owner.
    @discardableResult
    public func ask(from id: String, question: String) throws -> RunMessage {
        var dispatch = try live(id)
        let to = try run(dispatch.run)?.coordinator == nil ? "owner" : "coordinator"
        let line = try post(run: dispatch.run, kind: .question, from: id, to: to, text: question)
        // "waiting for an answer" until one comes (docs/spec/orchestration.md).
        dispatch = try store.get(.dispatches, id: id) ?? dispatch
        dispatch.waitingFor = line.id
        try store.put(.dispatches, id: id, parent: dispatch.run, dispatch)
        return line
    }

    /// `orchestration.send-message`: only to a dispatch of the same run.
    @discardableResult
    public func send(from id: String, to other: String, text: String) throws -> RunMessage {
        let dispatch = try live(id)
        guard let target: Dispatch = try store.get(.dispatches, id: other) else { throw RunError.unknown(other) }
        guard target.run == dispatch.run else { throw RunError.wrongRun(other) }
        return try post(run: dispatch.run, kind: .message, from: id, to: other, text: text)
    }

    /// The owner's (or the coordinator's) answer to a question, delivered to
    /// the dispatch that asked.
    @discardableResult
    public func answer(_ question: String, text: String, from: String = "owner") throws -> RunMessage {
        guard let asked: RunMessage = try store.get(.messages, id: question), asked.kind == .question else { throw RunError.unknown(question) }
        var reply = try post(run: asked.run, kind: .answer, from: from, to: asked.from, text: text)
        reply.answers = question
        try store.put(.messages, id: reply.id, parent: reply.run, reply)
        if var asker: Dispatch = try store.get(.dispatches, id: asked.from), asker.waitingFor == question {
            asker.waitingFor = nil
            try store.put(.dispatches, id: asker.id, parent: asker.run, asker)
        }
        return reply
    }

    /// `orchestration.inbox`: the unread lines to `id` (or to "owner",
    /// "coordinator"), marked read as they are handed over.
    public func inbox(_ id: String, markRead: Bool = true) throws -> [RunMessage] {
        let runId: String
        if let dispatch: Dispatch = try store.get(.dispatches, id: id) { runId = dispatch.run } else { return [] }
        return try unread(run: runId, to: id, markRead: markRead)
    }

    /// The unread lines of a run to `to`, for the owner's and the
    /// coordinator's inbox on the run page.
    public func unread(run: String, to: String, markRead: Bool) throws -> [RunMessage] {
        let found = try (store.all(.messages, parent: run) as [RunMessage]).filter { $0.to == to && !$0.read }
        if markRead {
            try store.batch {
                for var line in found {
                    line.read = true
                    try store.put(.messages, id: line.id, parent: run, line)
                }
            }
        }
        return found
    }

    func live(_ id: String) throws -> Dispatch {
        guard let dispatch: Dispatch = try store.get(.dispatches, id: id) else { throw RunError.unknown(id) }
        guard RunGraph.live([dispatch]).count == 1 else { throw RunError.alreadyEnded(id) }
        try sign(id)
        return dispatch
    }

    func post(run: String, kind: MessageKind, from: String, to: String, text: String) throws -> RunMessage {
        let line = RunMessage(id: newId(), run: run, kind: kind, from: from, to: to, text: text, at: now())
        try store.put(.messages, id: line.id, parent: run, line)
        return line
    }
}
