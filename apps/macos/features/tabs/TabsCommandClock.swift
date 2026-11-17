import AppKit
import Terminal

/// One clock for the headers that say "running 38 s" (TabCommandLooks): it ticks each second only
/// while this window's shown tabs have such a command, and stops by itself after.
@MainActor
final class TabsCommandClock {
    static let shared = TabsCommandClock()
    private var timer: Timer?
    private var controllers: [ObjectIdentifier: () -> Bool] = [:]

    /// `tick` refreshes a controller's headers; false: it has nothing running any more.
    func want(_ owner: AnyObject, tick: @escaping () -> Bool) {
        controllers[ObjectIdentifier(owner)] = tick
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { _ in MainActor.assumeIsolated { TabsCommandClock.shared.fire() } }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func fire() {
        controllers = controllers.filter { $0.value() }
        if controllers.isEmpty {
            timer?.invalidate()
            timer = nil
        }
    }
}

extension TabsController {
    /// Armed when a shown tab has a command running without an address yet.
    func armCommandClock() {
        guard isShown, TabCommandLooks.needsClock(Array(tabs.values)) else { return }
        TabsCommandClock.shared.want(self) { [weak self] in
            guard let self, self.isShown, TabCommandLooks.needsClock(Array(self.tabs.values)) else { return false }
            self.activeTab?.layout.refreshHeaders()
            self.onCommandTick?()
            return true
        }
    }
}
