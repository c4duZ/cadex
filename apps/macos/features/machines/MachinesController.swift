import Foundation

/// The machines of the owner's tailnet (docs/spec/machines.md), once for
/// the whole app and only while something shows them: the SSH card open,
/// or the palette listing them. Then it reads the daemon's status, pings
/// each online machine once, and follows the daemon's watch stream; if the
/// stream cannot start, it reads every 30 s instead. With nobody watching,
/// or machines.tailscale off: nothing read, nothing open, nothing run.
@MainActor
public final class MachinesController {
    public static let shared = MachinesController()

    init() {}

    /// The last reading; nil without a daemon, or with it off or unreachable.
    public private(set) var status: TailnetStatus?
    /// A reading is on its way (the dots stay grey until it lands).
    public private(set) var reading = false
    /// The last ping of each machine, by id; nil while it runs.
    public private(set) var pings: [String: MachinePing?] = [:]
    /// machines.tailscale. Off: everything stops and is forgotten.
    public var isEnabled = true { didSet { if isEnabled != oldValue { enabledChanged() } } }

    /// Where the daemon was looked for (tests point it at a folder).
    var daemon = TailscaleDaemon()
    /// One reading, one ping, the watch stream: the real ones call the
    /// daemon; the tests put fakes. All run off the main thread.
    var read: @Sendable (TailscaleEndpoint) -> TailnetStatus? = MachinesController.readStatus
    var pinger: @Sendable (TailscaleEndpoint, String) -> MachinePing? = MachinesController.pingMachine
    var streamer: @Sendable (TailscaleEndpoint, WatchHandle, @escaping @Sendable () -> Void) -> Bool = MachinesController.stream
    static let every: TimeInterval = 30

    private var watchers: [UUID: () -> Void] = [:]
    private var observers: [UUID: () -> Void] = [:]
    private var handle: WatchHandle?
    private var timer: Timer?
    private var generation = 0

    var isRunning: Bool { handle != nil || timer != nil }

    /// Something shows the machines (the card opened): read now, ping, and
    /// follow changes until `stop`.
    public func watch(_ changed: @escaping () -> Void) -> UUID {
        let id = UUID()
        watchers[id] = changed
        if watchers.count == 1 { start() } else { changed() }
        return id
    }

    public func stop(_ id: UUID) {
        watchers[id] = nil
        if watchers.isEmpty { halt() }
    }

    /// machines.refresh, and the palette's one reading: read now.
    public func refresh(_ done: (() -> Void)? = nil) {
        guard isEnabled, let endpoint = daemon.find() else {
            status = nil
            publish()
            done?()
            return
        }
        reading = true
        publish()
        let read = self.read
        let generation = self.generation
        Task {
            let result = await Task.detached { read(endpoint) }.value
            guard self.generation == generation else { return }
            self.reading = false
            self.status = result
            self.publish()
            done?()
        }
    }

    /// machines.ping, and each online machine when the card opens.
    public func ping(_ machine: Machine) {
        guard isEnabled, !machine.isSelf, let endpoint = daemon.find() else { return }
        pings[machine.id] = .some(nil)
        publish()
        let pinger = self.pinger
        let target = machine.ip
        let generation = self.generation
        Task {
            let result = await Task.detached { pinger(endpoint, target) }.value
            guard self.generation == generation else { return }
            self.pings[machine.id] = .some(result ?? MachinePing(ms: nil, path: .idle, error: "no answer"))
            self.publish()
        }
    }

    public func pingOnline() {
        for machine in status?.others ?? [] where machine.online { ping(machine) }
    }

    private func start() {
        guard isEnabled else { return publish() }
        refresh { [weak self] in self?.pingOnline() }
        guard let endpoint = daemon.find() else { return }
        let handle = WatchHandle()
        self.handle = handle
        let streamer = self.streamer
        let generation = self.generation
        Thread.detachNewThread {
            let followed = streamer(endpoint, handle) {
                DispatchQueue.main.async { MainActor.assumeIsolated { self.changedOnBus(generation) } }
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.streamEnded(generation, followed: followed, by: handle) }
            }
        }
    }

    func changedOnBus(_ generation: Int) {
        guard generation == self.generation, !watchers.isEmpty else { return }
        refresh()
    }

    /// The stream could not start, or ended while someone still looks:
    /// every 30 s instead (ADR 0030).
    func streamEnded(_ generation: Int, followed: Bool, by handle: WatchHandle) {
        guard generation == self.generation, !handle.isStopped, !watchers.isEmpty else { return }
        self.handle = nil
        guard timer == nil else { return }
        let timer = Timer(timeInterval: Self.every, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func halt() {
        generation += 1
        handle?.stop()
        handle = nil
        timer?.invalidate()
        timer = nil
        reading = false
    }

    private func enabledChanged() {
        halt()
        status = nil
        pings = [:]
        if isEnabled, !watchers.isEmpty { start() } else { publish() }
    }

    private func publish() {
        for changed in watchers.values { changed() }
        for changed in observers.values { changed() }
    }

    /// Told of every change without starting a reading or the watch: the
    /// palette waiting for a ping's answer.
    func watchPings(_ changed: @escaping () -> Void) -> UUID {
        let id = UUID()
        observers[id] = changed
        return id
    }

    func stopWatchingPings(_ id: UUID) { observers[id] = nil }

    // MARK: the real daemon

    nonisolated static func readStatus(_ endpoint: TailscaleEndpoint) -> TailnetStatus? {
        let data: Data?
        if case .cli(let path, let beCLI) = endpoint {
            data = LocalAPI.cli(path, beCLI: beCLI, ["status", "--json"])
        } else {
            data = LocalAPI.call(endpoint, "GET", "/localapi/v0/status")
        }
        return data.flatMap(Tailnet.status)
    }

    nonisolated static func pingMachine(_ endpoint: TailscaleEndpoint, _ ip: String) -> MachinePing? {
        if case .cli(let path, let beCLI) = endpoint {
            let out = LocalAPI.cli(path, beCLI: beCLI, ["ping", "-c", "1", "--timeout=3s", ip])
            return out.flatMap { String(data: $0, encoding: .utf8) }.flatMap(Tailnet.cliPing)
        }
        let query = ip.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: ".:"))) ?? ip
        return LocalAPI.call(endpoint, "POST", "/localapi/v0/ping?ip=\(query)&type=disco").flatMap(Tailnet.ping)
    }

    nonisolated static func stream(_ endpoint: TailscaleEndpoint, _ handle: WatchHandle, _ changed: @escaping @Sendable () -> Void) -> Bool {
        if case .cli = endpoint { return false }
        var lastLive: Int?
        return LocalAPI.watch(endpoint, stop: handle) { line in
            if Tailnet.busLineMatters(line, lastLive: &lastLive) { changed() }
        }
    }
}
