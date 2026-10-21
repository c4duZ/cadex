import Foundation
import Network

/// The servers of ~/.ssh/config and whether each answers (docs/spec/ssh.md),
/// once for the whole app and only while something shows them: then the
/// file is watched, and each host gets a TCP connection to its port, at
/// most 3 s, when the item starts showing and every 10 min. No login, no
/// command, no key read. With nobody watching: no test, no file watched.
@MainActor
public final class SSHController {
    public enum Reach: Equatable, Sendable {
        case unknown
        case testing
        /// Answered, in milliseconds.
        case up(Int)
        case down
        /// Reached through a proxy: not tested.
        case proxied
    }

    public static let shared = SSHController()

    public private(set) var hosts: [SSHHost] = []
    public private(set) var reach: [String: Reach] = [:]
    /// ssh.ping: off, the list stays and nothing is tested.
    public var pings = true { didSet { if pings != oldValue { restart() } } }
    /// The home folder Includes resolve from, and its ~/.ssh/config.
    var home = NSHomeDirectory()
    var config: String { home + "/.ssh/config" }
    /// The connection test (tests put a fake one).
    var probe: (SSHHost) async -> Reach = SSHController.connect

    static let every: TimeInterval = 600
    nonisolated static let timeout: TimeInterval = 3

    private var watchers: [UUID: () -> Void] = [:]
    private var timer: Timer?
    private var fileWatch: DispatchSourceFileSystemObject?

    var isRunning: Bool { timer != nil || fileWatch != nil }

    public func watch(_ changed: @escaping () -> Void) -> UUID {
        let id = UUID()
        watchers[id] = changed
        if watchers.count == 1 { restart() } else { changed() }
        return id
    }

    public func stop(_ id: UUID) {
        watchers[id] = nil
        if watchers.isEmpty { restart() }
    }

    /// ssh.test-again.
    public func testNow() {
        guard pings, !watchers.isEmpty else { return }
        for host in hosts { test(host) }
    }

    /// How many answered of those tested: the item's "SSH 3/3".
    public var counts: (up: Int, tested: Int) {
        let tested = hosts.filter { host in
            switch reach[host.alias] ?? .unknown {
            case .up, .down: true
            default: false
            }
        }
        return (tested.filter { if case .up = reach[$0.alias] { true } else { false } }.count, tested.count)
    }

    private func restart() {
        timer?.invalidate()
        timer = nil
        fileWatch?.cancel()
        fileWatch = nil
        guard !watchers.isEmpty else { return }
        load()
        watchFile()
        guard pings else { return publish() }
        testNow()
        let timer = Timer(timeInterval: Self.every, repeats: true) { _ in MainActor.assumeIsolated { SSHController.shared.testNow() } }
        timer.tolerance = 30
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func load() {
        hosts = SSHConfig.hosts(at: config, home: home)
        for host in hosts where host.proxy != nil { reach[host.alias] = .proxied }
        reach = reach.filter { key, _ in hosts.contains { $0.alias == key } }
        publish()
    }

    private func test(_ host: SSHHost) {
        guard host.proxy == nil else { return }
        reach[host.alias] = .testing
        publish()
        Task {
            let result = await probe(host)
            reach[host.alias] = result
            publish()
        }
    }

    /// Edited, replaced (an editor's atomic save) or removed: read it again.
    private func watchFile() {
        let fd = open(config, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete, .extend], queue: .main)
        source.setEventHandler {
            MainActor.assumeIsolated {
                let controller = SSHController.shared
                controller.load()
                // A rename or delete ends this watch: start a new one on the new file.
                controller.fileWatch?.cancel()
                controller.watchFile()
                controller.testNow()
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        fileWatch = source
    }

    private func publish() {
        for changed in watchers.values { changed() }
    }

    /// A TCP connection to the host's port: "up" with the time it took, or
    /// "down" after 3 s or a refusal.
    nonisolated static func connect(_ host: SSHHost) async -> Reach {
        guard let port = NWEndpoint.Port(rawValue: host.port) else { return .down }
        let connection = NWConnection(host: NWEndpoint.Host(host.hostName), port: port, using: .tcp)
        let started = Date()
        return await withCheckedContinuation { continuation in
            let once = Once()
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: once.run { continuation.resume(returning: .up(Int(Date().timeIntervalSince(started) * 1000))) }
                case .failed, .waiting: once.run { continuation.resume(returning: .down) }
                default: return
                }
                connection.cancel()
            }
            connection.start(queue: .global(qos: .utility))
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                once.run { continuation.resume(returning: .down) }
                connection.cancel()
            }
        }
    }
}

/// Runs its block once, from any thread: a connection answers or times out.
final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func run(_ block: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        done = true
        block()
    }
}
