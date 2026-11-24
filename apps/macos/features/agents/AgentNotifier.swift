import AppKit
import Strings
import UserNotifications

/// The system notification when an agent stops and waits for you: it asks
/// permission, it asked a question, it finished (docs/spec/agents.md,
/// Notificações). It rides on the AgentsController's reading while some
/// kind is on, and reads the end of a log only at a stop.
@MainActor
public final class AgentNotifier: NSObject {
    public struct Kinds: Equatable, Sendable {
        public var permission = true
        public var question = true
        public var finished = true
        public init(permission: Bool = true, question: Bool = true, finished: Bool = true) {
            self.permission = permission
            self.question = question
            self.finished = finished
        }
        var any: Bool { permission || question || finished }
    }

    public static let shared = AgentNotifier()

    /// Which stops notify (agents.notifyPermission, -Question, -Finished).
    public var kinds = Kinds() { didSet { if kinds != oldValue { update() } } }
    /// Each kind's sound: "none", "default", a macOS sound's name or a file
    /// (agents.soundPermission, -Question, -Finished; AgentNotifySound.swift).
    public var sounds: [AgentNotifyText.Kind: String] = [:]
    /// Whether you are looking at that agent now (its terminal in front in
    /// the key window): then nothing is posted.
    public var isLooking: (AgentSession) -> Bool = { _ in false }
    /// agents.mutedMachines: "local" (this Mac) or a machine's name; a
    /// session of a muted machine stops without a notification.
    public var mutedMachines: Set<String> = []
    /// A click on a notification: go to the session, by its id.
    public var onOpen: ((String) -> Void)?
    /// A click on a program's notification (posted by the app): its terminal's key.
    public var onOpenTerminal: ((String) -> Void)?

    /// Each stop that notifies, before it is posted (the tests' window in).
    var didStop: ((AgentSession, AgentStop) -> Void)?
    /// Each notification as it is posted, and whether quietly (the tests' window in).
    var didPost: ((AgentSession, AgentStop, Bool) -> Void)?
    /// What the session's terminal heard from the agent (OSC 7501), when it
    /// runs in a Cadex terminal; the app says. Without it, the end of the log.
    public var reportedStop: ((AgentSession) -> AgentStop?)?
    /// How long after a stop its log is read; the tests read at once.
    var stopDelay: TimeInterval = 1
    private let controller: AgentsController
    private var token: UUID?
    private var lastStatus: [String: AgentSession.Status] = [:]
    private var asked = false

    init(controller: AgentsController = .shared) {
        self.controller = controller
    }

    /// Notifications only from an app bundle: outside one (`swift run`) the
    /// system's center has no app to post for and stops the process.
    public static var canPost: Bool { Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil }

    private func update() {
        if kinds.any, token == nil {
            lastStatus = [:]
            token = controller.watch { [weak self] in self?.changed() }
        } else if !kinds.any, let token {
            controller.stop(token)
            self.token = nil
        }
    }

    /// Starts following the sessions (called once settings are read), and
    /// takes the clicks on notifications posted before a relaunch.
    public func start() {
        if Self.canPost {
            UNUserNotificationCenter.current().delegate = self
            // Asked when the app opens, not at the first stop: a notification
            // added while the question is up is dropped (found testing, 2026-10-21).
            if kinds.any { askPermission() }
        }
        update()
    }

    private func askPermission() {
        guard !asked else { return }
        asked = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// A session that was working and now waits: why, and a notification
    /// unless that kind is off or you are looking at it.
    func changed() {
        var now: [String: AgentSession.Status] = [:]
        for session in controller.sessions {
            now[session.id] = session.status
            // Any status after working is a stop: the end of the log says why.
            guard lastStatus[session.id] == .working, session.status != .working else { continue }
            if stopDelay > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + stopDelay) { [weak self] in MainActor.assumeIsolated { self?.stopped(session.id) } }
            } else {
                stopped(session.id)
            }
        }
        lastStatus = now
    }

    /// Why the session stopped, read a moment after it did: the status
    /// file can change before the log gets the Esc's mark, which read
    /// at once looked like a finished turn. Nothing if it works again.
    private func stopped(_ id: String) {
        guard let session = controller.sessions.first(where: { $0.id == id }), session.status != .working else { return }
        // In a Cadex terminal the agent's own report says why, with no log
        // read (plan 19); the end of the log only for sessions in other terminals.
        let stop = reportedStop?(session) ?? AgentStop.read(session)
        if stop == .loginExpired { AgentUsageController.shared.loginFailed(session.account.dir) }
        guard wants(stop), !isLooking(session) else { return }
        didStop?(session, stop)
        guard !mutedMachines.contains(session.machine ?? "local") else { return }
        // A finished turn while you are in Cadex (another tab or project): the banner without its
        // sound. It used to post nothing there (UX audit, 2026-11-18: a sound on every turn taught
        // people to turn them all off), and the owner, in Cadex all day, missed most stops (the
        // owner, 2026-11-24: "muitas vezes o Cadex não avisa quando a sessão parou").
        if case .finished = stop, appIsActive() { return post(session, stop, quiet: true) }
        post(session, stop)
    }

    /// Whether Cadex is the app in front (NSApp.isActive); a test can say otherwise.
    var appIsActive: () -> Bool = { NSApp?.isActive ?? false }

    func wants(_ stop: AgentStop) -> Bool {
        switch stop {
        case .permission: kinds.permission
        case .question, .unknown, .loginExpired: kinds.question
        case .finished: kinds.finished
        case .interrupted: false
        }
    }

    /// `quiet`: the banner without the kind's sound.
    private func post(_ session: AgentSession, _ stop: AgentStop, quiet: Bool = false) {
        didPost?(session, stop, quiet)
        post(id: session.id, agent: session.account.provider == .codex ? "Codex" : "Claude", project: AgentProject.of(session.cwd).name,
             account: session.account.name, name: session.name, stop, quiet: quiet)
    }

    /// You went to the session's terminal: what it said is read, so its
    /// notification leaves Notification Center (as Ghostty does for a tab).
    public func forget(_ sessionID: String) {
        guard Self.canPost else { return }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["agent-" + sessionID])
    }

    /// agents.test-notifications: one of each kind, as they will look, a
    /// second apart. Notifications off for Cadex in System Settings: opens
    /// that page instead.
    public func sendTest(project: String, account: String) {
        guard Self.canPost else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard granted else {
                        let page = "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=" + (Bundle.main.bundleIdentifier ?? "")
                        if let url = URL(string: page) { NSWorkspace.shared.open(url) }
                        return
                    }
                    let samples: [AgentStop] = [.permission(tool: "Bash", subject: "npm test"),
                                                .question(T("Which branch should it merge into?", "Em qual branch fazer o merge?")),
                                                .finished(T("All tests pass and the change is committed.", "Os testes passam e a mudança está commitada."))]
                    // Two seconds apart, so each sound is heard on its own.
                    for (index, stop) in samples.enumerated() {
                        DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 2) {
                            MainActor.assumeIsolated {
                                AgentNotifier.shared.post(id: "test-\(index)", agent: "Claude", project: project, account: account, name: "test", stop)
                            }
                        }
                    }
                }
            }
        }
    }

    private func post(id: String, agent: String, project: String, account: String, name: String, _ stop: AgentStop, quiet: Bool = false) {
        guard Self.canPost else { return }
        let center = UNUserNotificationCenter.current()
        askPermission()
        let text = AgentNotifyText.make(stop, agent: agent, project: project, session: name, account: account)
        let content = UNMutableNotificationContent()
        content.title = text.title
        content.subtitle = text.subtitle
        content.body = text.body
        let kind = AgentNotifyText.kind(of: stop)
        content.sound = quiet ? nil : AgentNotifySound.sound(sounds[kind] ?? "default", kind: kind)
        content.threadIdentifier = id
        content.userInfo = ["session": id]
        // One per session: a new stop replaces the one before it.
        center.add(UNNotificationRequest(identifier: "agent-" + id, content: content, trigger: nil))
    }
}

extension AgentNotifier: UNUserNotificationCenterDelegate {
    /// Shown while Cadex is in front too: you may be in another tab.
    public nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                                   withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    public nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                                   withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let id = info["session"] as? String
        let terminal = info["terminal"] as? String
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if let id { AgentNotifier.shared.onOpen?(id) }
                if let terminal { AgentNotifier.shared.onOpenTerminal?(terminal) }
            }
        }
        completionHandler()
    }
}
