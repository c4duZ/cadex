import AppKit

/// Esc on a page goes back to the terminal used before it (plan 34 A): pages open under the bar
/// and leave it as it was, so the way out is the key or a tab. A field with text keeps its Esc
/// (a page's search clears first); a sheet over the window keeps it too.
extension WindowSession {
    func startPageKeys() {
        pageKeys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == 53, event.window === self.window, self.window.attachedSheet == nil,
                  event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
                  self.tabs?.showsPage == true else { return event }
            if let editor = self.window.firstResponder as? NSTextView, editor.isFieldEditor, !editor.string.isEmpty { return event }
            self.tabs?.leavePage()
            return nil
        }
    }
}
