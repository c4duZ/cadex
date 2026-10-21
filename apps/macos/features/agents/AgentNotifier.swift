import AppKit
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
    /// Whether you are looking at that agent now (its terminal in front in
    /// the key window): then nothing is posted.
    public var isLooking: (AgentSession) -> Bool = { _ in false }
    /// The theme's accent, for the picture beside the text.
    public var accent: NSColor = .controlAccentColor
    /// A click on a notification: go to the session, by its id.
    public var onOpen: ((String) -> Void)?

    /// Each stop that notifies, before it is posted (the tests' window in).
    var didStop: ((AgentSession, AgentStop) -> Void)?
    private let controller: AgentsController
    private var token: UUID?
    private var lastStatus: [String: AgentSession.Status] = [:]
    private var asked = false

    init(controller: AgentsController = .shared) {
        self.controller = controller
    }

    /// Notifications only from an app bundle: outside one (`swift run`) the
    /// system's center has no app to post for and stops the process.
    static var canPost: Bool { Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil }

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
        if Self.canPost { UNUserNotificationCenter.current().delegate = self }
        update()
    }

    /// A session that was working and now waits: why, and a notification
    /// unless that kind is off or you are looking at it.
    func changed() {
        var now: [String: AgentSession.Status] = [:]
        for session in controller.sessions {
            now[session.id] = session.status
            guard lastStatus[session.id] == .working, session.status == .waiting else { continue }
            let stop = AgentStop.read(session)
            guard wants(stop), !isLooking(session) else { continue }
            didStop?(session, stop)
            post(session, stop)
        }
        lastStatus = now
    }

    func wants(_ stop: AgentStop) -> Bool {
        switch stop {
        case .permission: kinds.permission
        case .question, .unknown: kinds.question
        case .finished: kinds.finished
        }
    }

    private func post(_ session: AgentSession, _ stop: AgentStop) {
        guard Self.canPost else { return }
        let center = UNUserNotificationCenter.current()
        if !asked {
            asked = true
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
        let content = UNMutableNotificationContent()
        let project = AgentProject.of(session.cwd).name
        content.title = "\(project) · \(session.account.name)"
        content.body = "\(stop.text) — \(session.name)"
        content.sound = .default
        content.threadIdentifier = session.id
        content.userInfo = ["session": session.id]
        if let picture = AgentNotifyIcon.attachment(for: stop, accent: accent) { content.attachments = [picture] }
        // One per session: a new stop replaces the one before it.
        center.add(UNNotificationRequest(identifier: "agent-" + session.id, content: content, trigger: nil))
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
        let id = response.notification.request.content.userInfo["session"] as? String
        DispatchQueue.main.async {
            MainActor.assumeIsolated { if let id { AgentNotifier.shared.onOpen?(id) } }
        }
        completionHandler()
    }
}
