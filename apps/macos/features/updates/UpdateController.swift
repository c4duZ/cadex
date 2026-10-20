import Foundation
import Strings

/// The entry point of updates (docs/spec/updates.md): looks for a newer
/// Cadex after launch and every 6 hours, opens the panel the first time it
/// finds one, and installs it on request. One for the whole app; every
/// window's title bar shows its state.
@MainActor
public final class UpdateController {
    public enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(UpdateRelease)
        /// Bytes so far and the total, when known.
        case downloading(Int64, Int64?)
        /// In place of the running app; reopening finishes.
        case installed(String)
        case failed(String)
    }

    public private(set) var state: State = .idle {
        didSet {
            onChange?()
            panel?.render()
        }
    }
    public var onChange: (() -> Void)?
    /// Runs a command by id in the window in front: the panel's buttons
    /// are commands (ADR 0005).
    public var runCommand: ((String) -> Void)?
    /// Quits as usual (asking over running programs) and opens Cadex again.
    public var relaunch: (() -> Void)?

    public let currentVersion: String
    /// Nil outside an .app bundle (`make run`): there is nothing to replace.
    let installer: UpdateInstaller?
    private let feed: URL
    private var timer: Timer?
    private var panel: UpdatePanel?
    private let defaults: UserDefaults
    /// The version whose panel opened by itself in this run: "Later" means
    /// until the next launch, not until the next 6-hour check.
    private var promptedVersion: String?
    /// Opens the panel for a version found by an automatic check; tests
    /// replace it, since they have no windows.
    var prompt: (() -> Void)?
    static let skippedKey = "updates.skippedVersion"

    static let defaultFeed = URL(string: "https://github.com/c4duZ/cadex/releases/latest/download/latest.json")!
    /// Between automatic checks while Cadex stays open.
    static let interval: TimeInterval = 6 * 60 * 60

    /// CADEX_UPDATE_FEED points at another latest.json (a file:// one in
    /// tests and when checking a release before publishing it).
    public convenience init(bundle: Bundle = .main) {
        let env = ProcessInfo.processInfo.environment["CADEX_UPDATE_FEED"]
        let feed = env.flatMap { $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : URL(string: $0) } ?? Self.defaultFeed
        let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let installer = bundle.bundleIdentifier.map { UpdateInstaller(app: bundle.bundleURL, bundleID: $0) }
        self.init(currentVersion: version, feed: feed, installer: installer)
    }

    init(currentVersion: String, feed: URL, installer: UpdateInstaller?, defaults: UserDefaults = .standard) {
        self.currentVersion = currentVersion
        self.feed = feed
        self.installer = installer
        self.defaults = defaults
    }

    /// The version "Don't Remind Me Again" was pressed on: it no longer
    /// opens the panel or shows the button; a newer one does.
    var skippedVersion: String? { defaults.string(forKey: Self.skippedKey) }

    /// Why the commands cannot run here, or nil.
    public var unavailableReason: String? {
        installer == nil ? T("Only in the installed Cadex", "Só no Cadex instalado") : nil
    }

    /// The first check a few seconds after launch, in the background, so
    /// opening is not slower for it (owner, 2026-10-20); then every 6 hours.
    public func start() {
        guard installer != nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.checkAutomatically() }
        }
    }

    private func checkAutomatically() {
        Task { await check(manual: false) }
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.check(manual: false) }
        }
    }

    /// "Check for Updates": the panel, and a fresh look at latest.json.
    public func showAndCheck() {
        showPanel()
        Task { await check(manual: true) }
    }

    private func showPanel() {
        let panel = self.panel ?? UpdatePanel(controller: self)
        self.panel = panel
        panel.show()
    }

    /// Looks at latest.json. An automatic check that fails keeps quiet:
    /// no internet is not worth a message (docs/spec/updates.md). One that
    /// finds a version not skipped opens the panel, once per run.
    func check(manual: Bool) async {
        switch state {
        case .checking, .downloading, .installed: return
        default: break
        }
        let before = state
        if manual { state = .checking }
        do {
            let release = try await fetchRelease()
            guard UpdateVersion.isNewer(release.version, than: currentVersion) else { return state = .upToDate }
            if !manual && release.version == skippedVersion { return state = .idle }
            state = .available(release)
            if !manual && promptedVersion != release.version {
                promptedVersion = release.version
                (prompt ?? showPanel)()
            }
        } catch {
            state = manual ? .failed(Self.describe(error)) : before
        }
    }

    private func fetchRelease() async throws -> UpdateRelease {
        var request = URLRequest(url: feed, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw UpdateError.server(http.statusCode)
        }
        return try JSONDecoder().decode(UpdateRelease.self, from: data)
    }

    /// "Install and Reopen": download, check, replace, reopen. Once
    /// installed, running it again only reopens (the quit was cancelled).
    public func install() {
        if case .installed = state { return relaunch?() ?? () }
        guard case .available(let release) = state, let installer else { return }
        showPanel()
        state = .downloading(0, nil)
        Task {
            do {
                try await installer.install(release) { done, total in
                    Task { @MainActor [weak self] in
                        guard let self, case .downloading = self.state else { return }
                        self.state = .downloading(done, total)
                    }
                }
                state = .installed(release.version)
                relaunch?()
            } catch {
                state = .failed(Self.describe(error))
            }
        }
    }

    /// "Don't Remind Me Again": this version stays quiet from now on, in
    /// this run and the next ones. "Check for Updates" still offers it.
    public func skip() {
        guard case .available(let release) = state else { return }
        defaults.set(release.version, forKey: Self.skippedKey)
        state = .idle
        panel?.hide()
    }

    /// The version waiting, for the title bar's tip.
    public var pendingVersion: String? {
        switch state {
        case .available(let release): release.version
        case .installed(let version): version
        default: nil
        }
    }

    /// Whether the title bar shows its button.
    public var showsButton: Bool {
        switch state {
        case .available, .downloading, .installed: true
        default: false
        }
    }

    /// What the title bar's button says on hover.
    public var buttonTip: String {
        switch state {
        case .downloading(let done, let total):
            T("Downloading the update… \(Self.percent(done, total))", "Baixando a atualização… \(Self.percent(done, total))")
        case .installed: T("Reopen to finish the update", "Reabrir para terminar a atualização")
        default: pendingVersion.map { T("Update to \($0)", "Atualizar para \($0)") } ?? ""
        }
    }

    /// "40% of 9.8 MB", or the MB so far when the total is unknown.
    static func percent(_ done: Int64, _ total: Int64?) -> String {
        let mb = { (bytes: Int64) in String(format: "%.1f MB", Double(bytes) / 1_048_576) }
        guard let total, total > 0 else { return mb(done) }
        return T("\(done * 100 / total)% of \(mb(total))", "\(done * 100 / total)% de \(mb(total))")
    }

    static func describe(_ error: Error) -> String {
        if let error = error as? UpdateError { return error.errorDescription ?? "\(error)" }
        if (error as? URLError) != nil {
            return T("Could not reach GitHub. Check the internet connection.",
                     "Não consegui falar com o GitHub. Confira a conexão com a internet.")
        }
        return T("The update failed: \(error.localizedDescription)", "A atualização falhou: \(error.localizedDescription)")
    }
}
