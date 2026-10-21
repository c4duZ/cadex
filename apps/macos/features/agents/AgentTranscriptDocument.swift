import AppKit
import Strings
import Tabs

/// A subagent's conversation in a tab, read only (docs/spec/agents.md,
/// Conversa do subagente). It opens from a click on a subagent in Agents
/// and from nowhere else; it reads the log off the main thread and, while
/// the subagent writes, only what it added (a kernel event on the file, no
/// timer). Closed, it lets go of everything: nothing open weighs (the
/// owner's rule for plan 17).
@MainActor
public final class AgentTranscriptDocument: TabDocument {
    public let path: String
    public let title: String
    public var onChange: (() -> Void)?
    public var colors: AgentColors { didSet { transcript.colors = colors } }
    private let transcript: AgentTranscriptView
    private let reader: AgentTranscriptReader
    private let queue = DispatchQueue(label: "cadex.agents.transcript", qos: .userInitiated)
    private var watch: DispatchSourceFileSystemObject?

    /// The log of `agent` in `session`'s subagents folder.
    public static func path(of agent: AgentSubagent, in session: AgentSession) -> String {
        AgentSubagent.folder(of: session) + "/" + agent.id + ".jsonl"
    }

    public convenience init(session: AgentSession, agent: AgentSubagent, colors: AgentColors) {
        self.init(path: Self.path(of: agent, in: session), title: agent.description,
                  detail: agent.type + " · " + session.name + " · " + session.account.name, colors: colors)
    }

    public init(path: String, title: String, detail: String, colors: AgentColors) {
        self.path = path
        self.title = title
        self.colors = colors
        reader = AgentTranscriptReader(path: path)
        transcript = AgentTranscriptView(title: title, detail: detail, colors: colors)
        readNew()
        startWatching()
    }

    public static func identity(for path: String) -> String { "subagent:\(path)" }
    public var identity: String { Self.identity(for: path) }
    public var view: NSView { transcript }
    var drawnText: String { transcript.textView.string }
    public var hasUnsavedChanges: Bool { false }
    public func focus() { transcript.window?.makeFirstResponder(transcript.textView) }
    public func confirmClose(in window: NSWindow?, then close: @escaping @MainActor () -> Void) { close() }

    public func close() {
        watch?.cancel()
        watch = nil
        transcript.clear()
    }

    /// Off the main thread, then the new entries drawn at the bottom.
    private func readNew() {
        let reader = self.reader
        queue.async { [weak self] in
            let entries = reader.readNew()
            guard !entries.isEmpty else { return }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.transcript.append(entries) } }
        }
    }

    /// The file grows while the subagent works: the system says so, and
    /// only the new bytes are read. Nothing runs while it is quiet.
    private func startWatching() {
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.extend, .write], queue: .main)
        source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.readNew() } }
        source.setCancelHandler { Darwin.close(descriptor) }
        source.resume()
        watch = source
    }
}
