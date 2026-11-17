import Foundation

/// What a run's agent asks with `cadex run orchestration.<…>` (plan 24 D2,
/// docs/spec/orchestration.md "Agentes supervisionados"), answered over the
/// state: the text the agent reads, and what the app must do after (tell
/// the owner of a question, dispatch what became ready). The caller was
/// found from the session's token (`RunBook.caller`).
public enum RunAgentAPI {
    public struct Outcome: Equatable {
        public var text: String
        /// A question to the owner: the app tells them (plan 19's notification).
        public var ownerQuestion: RunMessage?
        /// Something changed: the app redraws and dispatches what is ready.
        public var changed = true
    }

    /// `hasSlot`: whether one more agent fits now (races and runs).
    public static func handle(_ id: String, _ args: [String: String], caller: RunCaller, book: RunBook,
                              maxDepth: Int, hasSlot: Bool, maxAgents: Int = 6) throws -> Outcome {
        func need(_ key: String) throws -> String {
            guard let value = args[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { throw RunError.missing(key) }
            return value
        }
        func dispatchOnly() throws -> Dispatch {
            guard case .dispatch(let dispatch) = caller else { throw RunError.notYours("\(id) is for a task's agent, not the coordinator") }
            return dispatch
        }
        switch id {
        case "orchestration.report-done":
            let dispatch = try dispatchOnly()
            let summary = try need("summary")
            do {
                let ready = try book.reportDone(dispatch.id, summary: String(summary.prefix(2000)))
                let title = try title(dispatch.task, book)
                try book.tellCoordinator(run: dispatch.run, from: dispatch.id, text: "\(title) (task \(dispatch.task)) done: \(summary)")
                return Outcome(text: ready.isEmpty ? "done; thank you" : "done; \(ready.count) task(s) can start now")
            } catch RunError.alreadyEnded(_) {
                return Outcome(text: "already done", changed: false)
            }
        case "orchestration.report-heartbeat":
            try book.heartbeat(try dispatchOnly().id, note: args["note"] ?? "")
            return Outcome(text: "noted")
        case "orchestration.ask":
            let dispatch = try dispatchOnly()
            let line = try book.ask(from: dispatch.id, question: String(try need("question").prefix(2000)))
            let to = line.to == "owner" ? "the owner" : "the run's coordinator"
            return Outcome(text: "asked \(to) (question \(line.id)); read the answer with: cadex run orchestration.inbox",
                           ownerQuestion: line.to == "owner" ? line : nil)
        case "orchestration.send-message":
            let to = try need("to")
            let text = String(try need("text").prefix(2000))
            switch caller {
            case .dispatch(let dispatch):
                try book.send(from: dispatch.id, to: to, text: text)
            case .coordinator(let run):
                guard let target: Dispatch = try book.store.get(.dispatches, id: to), target.run == run.id else { throw RunError.wrongRun(to) }
                if let question = args["answers"], !question.isEmpty {
                    guard let asked: RunMessage = try book.store.get(.messages, id: question), asked.run == run.id, asked.from == to else {
                        throw RunError.unknown(question)
                    }
                    try book.answer(question, text: text, from: "coordinator")
                } else {
                    _ = try book.post(run: run.id, kind: .message, from: "coordinator", to: to, text: text)
                }
            }
            return Outcome(text: "sent to \(to)")
        case "orchestration.inbox":
            let lines: [RunMessage]
            switch caller {
            case .dispatch(let dispatch): lines = try book.inbox(dispatch.id)
            case .coordinator(let run): lines = try book.unread(run: run.id, to: "coordinator", markRead: true)
            }
            return Outcome(text: lines.isEmpty ? "nothing new" : lines.map(describe).joined(separator: "\n"), changed: false)
        case "orchestration.spawn":
            let agent: AgentChoice
            switch caller {
            case .dispatch(let dispatch): agent = dispatch.agent
            case .coordinator(let run):
                guard let auto = run.autoAgent else { throw RunError.notYours("this run has no agent to dispatch sub-tasks to") }
                agent = auto
            }
            let after = (args["after"] ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            let gate = ["yes", "true", "1"].contains((args["gate"] ?? "").lowercased())
            // Refused at the agents' cap only when it would start now.
            if after.isEmpty && !gate && !hasSlot { throw RunError.noSlot(maxAgents) }
            let task = try book.spawnTask(by: caller, title: String(try need("title").prefix(120)), spec: try need("spec"),
                                          after: after, gate: gate, maxDepth: maxDepth, agent: agent)
            let when = gate ? "after the owner approves its gate" : task.state == .ready ? "now" : "when what it waits for is done"
            return Outcome(text: "task \(task.id) \"\(task.title)\" (\(task.state.rawValue)); it is dispatched on its own \(when)")
        case "orchestration.retry":
            guard case .coordinator(let run) = caller else { throw RunError.notYours("only the run's coordinator (or the owner) retries a task") }
            let task = try need("task")
            guard let found: RunTask = try book.store.get(.tasks, id: task), found.run == run.id else { throw RunError.unknown(task) }
            try book.retry(task: task)
            return Outcome(text: "task \(task) will be tried again")
        default:
            throw RunError.notYours("\(id) is not a run's agent command")
        }
    }

    static func title(_ task: String, _ book: RunBook) throws -> String {
        (try book.store.get(.tasks, id: task) as RunTask?)?.title ?? task
    }

    /// One inbox line as the agent reads it.
    static func describe(_ line: RunMessage) -> String {
        switch line.kind {
        case .question: return "[question \(line.id) from dispatch \(line.from)] \(line.text)"
        case .answer: return "[answer to \(line.answers ?? "?") from \(line.from)] \(line.text)"
        case .message: return "[message from \(line.from)] \(line.text)"
        }
    }
}
