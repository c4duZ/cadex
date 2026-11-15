import Agents
import AppKit
import Terminal
import UserNotifications

/// A program's own notifications (OSC 777, OSC 9) as macOS ones
/// (docs/spec/terminal.md; the owner's choice of 2026-11-15): any program
/// in any terminal, unless terminal.programNotifications is off or you
/// look at that terminal. One per terminal: a new one replaces the last.
/// A click brings that terminal to the front, through the agents' center
/// delegate (AgentNotifier.onOpenTerminal), the app's only one.
extension AppDelegate {
    func startProgramNotifications() {
        NotificationCenter.default.addObserver(forName: TerminalView.programDidNotify, object: nil, queue: .main) { [weak self] note in
            let title = note.userInfo?["title"] as? String ?? ""
            let body = note.userInfo?["body"] as? String ?? ""
            // The view is read on the main queue it was posted on.
            nonisolated(unsafe) let object = note.object
            MainActor.assumeIsolated {
                guard let self, let view = object as? TerminalView else { return }
                self.postProgramNotification(from: view, title: title, body: body)
            }
        }
        AgentNotifier.shared.onOpenTerminal = { [weak self] key in self?.goToAgent(key: key, pid: 0) }
    }

    private func postProgramNotification(from view: TerminalView, title: String, body: String) {
        guard settings.store.settings.terminal.programNotifications, AgentNotifier.canPost, !view.isLookedAt else { return }
        guard !title.isEmpty || !body.isEmpty else { return }
        // OSC 9 has only a body: the terminal's name is the title then.
        let place = Self.conversationName(view)
        postTerminalNotification(title: title.isEmpty ? place : title, subtitle: title.isEmpty ? "" : place, body: body, key: Self.key(view))
    }

    /// One macOS notification for a terminal (a program's, an agent's
    /// `cadex notify`): a new one from it replaces the last; the click goes there.
    func postTerminalNotification(title: String, subtitle: String, body: String, key: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = subtitle
        content.body = body
        content.sound = .default
        content.userInfo = ["terminal": key]
        center.add(UNNotificationRequest(identifier: "terminal-" + key, content: content, trigger: nil))
    }
}
