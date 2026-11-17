import Foundation

/// Typing into a terminal that may have just opened (a New Task's agent, a
/// race's contender, a dispatch, an automation, an ssh): text written to a
/// brand new shell before its line editor started was lost now and then,
/// because zsh flushes pending input when it sets up the terminal (found
/// 2026-11-16 by plan 24's `make perf`, three of three agents lost in a
/// shell that started fast). The text waits for the shell's first output and
/// then 300 ms without output (its prompt), at most 5 s from the opening; a
/// terminal that is already settled gets it at once.
extension TerminalView {
    static let settleQuiet: TimeInterval = 0.3
    static let settleLimit: TimeInterval = 5

    /// Writes `text` to the shell once it is ready for typing.
    public func typeWhenReady(_ text: String) {
        pendingTyping.append(text)
        flushTypingIfReady()
    }

    /// Called on each output of the session (TerminalView's onOutput).
    func noteOutputForTyping() {
        lastOutputAt = Date()
        if !pendingTyping.isEmpty { flushTypingIfReady() }
    }

    func flushTypingIfReady() {
        guard !pendingTyping.isEmpty else { return }
        let now = Date()
        let settled = lastOutputAt.map { now.timeIntervalSince($0) >= Self.settleQuiet } ?? false
        guard settled || now.timeIntervalSince(openedAt) >= Self.settleLimit else {
            typingCheck?.invalidate()
            let check = Timer(timeInterval: 0.1, repeats: false) { [weak self] _ in MainActor.assumeIsolated { self?.flushTypingIfReady() } }
            RunLoop.main.add(check, forMode: .common)
            typingCheck = check
            return
        }
        typingCheck?.invalidate()
        typingCheck = nil
        let text = pendingTyping.joined()
        pendingTyping = []
        session?.write(text)
    }
}
