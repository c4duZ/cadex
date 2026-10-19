import AppKit

/// The one list of commands. Each feature registers its own through its
/// entry point; the app builds the menu, the shortcuts and the palette
/// from it.
@MainActor
public final class CommandRegistry {
    public private(set) var commands: [Command] = []
    private var indexById: [String: Int] = [:]
    /// Ids in the order they last ran, most recent first (the palette shows
    /// these first with an empty search).
    public private(set) var recent: [String] = []
    private static let recentLimit = 10

    public init() {}

    /// Adds a command. A second command with the same id is a programming
    /// error: it would make "run by id" ambiguous.
    public func register(_ command: Command) {
        precondition(indexById[command.id] == nil, "command \(command.id) registered twice")
        indexById[command.id] = commands.count
        commands.append(command)
    }

    public func register(_ list: [Command]) {
        list.forEach(register)
    }

    public func command(_ id: String) -> Command? {
        indexById[id].map { commands[$0] }
    }

    /// Nil when the command can run, otherwise why not. Unknown ids say so.
    public func unavailableReason(_ id: String) -> String? {
        guard let command = command(id) else { return "Comando desconhecido" }
        return command.unavailableReason()
    }

    /// Runs a command if it exists and is available. Returns whether it ran.
    @discardableResult
    public func run(_ id: String) -> Bool {
        guard let command = command(id), command.unavailableReason() == nil else { return false }
        switch command.action {
        case .responder(let selector):
            NSApplication.shared.sendAction(selector, to: nil, from: nil)
        case .run(let body):
            body()
        }
        recent.removeAll { $0 == id }
        recent.insert(id, at: 0)
        if recent.count > Self.recentLimit { recent.removeLast() }
        return true
    }
}
