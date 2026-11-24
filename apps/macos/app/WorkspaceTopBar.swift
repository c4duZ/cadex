import AppKit

/// The top bar goes up with the sidebar (the owner, 2026-11-22: "quando eu sumo com a barra lateral,
/// a top bar sobe também, dando foco total aos terminais"). Only the owner's closing does it (⌘B,
/// or inspector.visible saved off); a sidebar that closes on its own (a narrow window, a preview
/// opening) leaves the bar, and any way of opening the sidebar brings the bar back
/// (`setInspector`). With the bar go the window's buttons and the empty toolbar that gives the title
/// bar its height, so nothing of the frame stays over the terminals; ⌘B brings everything back.
extension WorkspaceView {
    /// The owner's ⌘B, or the saved state at launch: the sidebar, and the top bar with it.
    func setSidebarByOwner(visible: Bool, launching: Bool = false) {
        let animated = !launching && window?.isVisible == true && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        setInspector(visible: visible, launching: launching)
        if !visible { collapseTopBar(true, animated: animated) }
    }

    /// The top bar up (0 pt, hidden) or back. Kept as a wish before the view has a window: the
    /// window's parts follow when it gets one (`applyTopBarToWindow`).
    func collapseTopBar(_ collapsed: Bool, animated: Bool) {
        guard collapsed != topBarCollapsed else { return }
        topBarCollapsed = collapsed
        applyTopBarToWindow()
        if !collapsed { titleBar.isHidden = false }
        let height = collapsed ? 0 : TitleBarView.height
        guard animated else {
            titleBarHeight.constant = height
            titleBar.isHidden = collapsed
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            titleBarHeight.animator().constant = height
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.topBarCollapsed == collapsed else { return }
                self.titleBar.isHidden = collapsed
            }
        })
    }

    /// The window's buttons and toolbar as the bar is. In full screen the toolbar stays off either
    /// way (WindowSession hides it there, and gives it back on leaving by this state); in Cadex's
    /// full screen the buttons go too, as the system's hides them (CadexWindow).
    func applyTopBarToWindow() {
        guard let window else { return }
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(kind)?.isHidden = topBarCollapsed || window.isAnyFullScreen
        }
        if !window.styleMask.contains(.fullScreen) { window.toolbar?.isVisible = !topBarCollapsed && !window.isAnyFullScreen }
    }
}
