import Foundation

/// `cadex share` (plan 39 E): this Mac's address on the tailnet, read now if
/// nobody has read it, and the file server started there for its owner.
extension MachinesController {
    /// The link of `path` shared for an hour, or why not (in words, for the phone's terminal).
    public func shareFile(_ path: String, _ done: @escaping @MainActor (Result<(url: String, share: FileShareStore.Share), FileShareError>) -> Void) {
        guard isEnabled else { return done(.failure(.off)) }
        guard let share = FileShareServer.shared.store.add(path) else { return done(.failure(.noFile)) }
        selfOnTailnet { me in
            guard let me else { return done(.failure(.noTailnet)) }
            guard let base = FileShareServer.shared.start(ip: me.ip, owner: me.ownerID) else { return done(.failure(.noTailnet)) }
            done(.success((base + "/s/" + share.token + "/", share)))
        }
    }

    /// The shares still valid, with their links (nil before any share started the server).
    public func sharedFiles() -> [(url: String, share: FileShareStore.Share)] {
        let address = FileShareServer.shared.listener.address
        guard !address.isEmpty else { return [] }
        return FileShareServer.shared.store.list().map { ("http://\(address):\(FileShareServer.port)/s/\($0.token)/", $0) }
    }

    /// This Mac on the tailnet: the reading the card made, else one now.
    func selfOnTailnet(_ done: @escaping @MainActor (Machine?) -> Void) {
        if let me = status?.machines.first(where: \.isSelf), status?.isRunning == true { return done(me) }
        guard let endpoint = daemon.find() else { return done(nil) }
        let read = self.read
        Task {
            let result = await Task.detached { read(endpoint) }.value
            done(result?.isRunning == true ? result?.machines.first(where: \.isSelf) : nil)
        }
    }
}

public enum FileShareError: Error, Sendable {
    case off, noFile, noTailnet

    public var words: String {
        switch self {
        case .off: return "Machines (Tailscale) is off in Cadex's settings"
        case .noFile: return "no such file"
        case .noTailnet: return "this Mac is not on a tailnet (is Tailscale running and logged in?)"
        }
    }
}
