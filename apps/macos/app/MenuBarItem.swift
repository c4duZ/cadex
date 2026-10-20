import AppKit

/// The Cadex symbol in the macOS menu bar, by the clock (docs/spec/power.md):
/// filled while keep-awake is on, only the outline while off, seen even with
/// Cadex behind other apps, as Amphetamine's (owner, 2026-10-20). A click
/// does what the coffee in the title bar does.
@MainActor
final class MenuBarItem: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let onClick: () -> Void

    init(onClick: @escaping () -> Void) {
        self.onClick = onClick
        super.init()
        item.button?.target = self
        item.button?.action = #selector(clicked)
    }

    func show(on: Bool, tip: String) {
        item.button?.image = CadexMark.image(filled: on)
        item.button?.toolTip = tip
        item.button?.setAccessibilityLabel(tip)
    }

    @objc private func clicked() {
        onClick()
    }
}
