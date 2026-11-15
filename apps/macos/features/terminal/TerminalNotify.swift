import AppKit

/// A program's own notification (OSC 777 `notify;title;body`, OSC 9), as
/// the core hands it (docs/spec/terminal.md): told to the app, which posts
/// it as a macOS notification unless you look at this terminal.
extension TerminalView {
    /// Posted with the title and body in userInfo; the object is the view.
    public static let programDidNotify = Notification.Name("CadexTerminalProgramDidNotify")

    /// You are looking at it: its window is key, Cadex in front, and it has the focus.
    public var isLookedAt: Bool {
        NSApp.isActive && window?.isKeyWindow == true && window?.firstResponder === self
    }

    func programNotified(title: String, body: String) {
        NotificationCenter.default.post(name: Self.programDidNotify, object: self, userInfo: ["title": title, "body": body])
    }
}
