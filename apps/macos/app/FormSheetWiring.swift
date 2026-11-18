import AppKit
import Strings
import UILooks

/// The app's forms (New Run, Add Task, Dispatch, Dependencies, New Automation) in the frame's
/// sheet, not the system alert (plan 31 B): the title, what will happen, the form, Cancel and the
/// main button; `accepted` runs on the main button.
extension WindowSession {
    func showForm(_ title: String, text: String, form: NSView, primary: String, first: NSView? = nil,
                  accepted: @escaping @MainActor () -> Void) {
        let sheet = FrameSheet.show(in: window, title: title, text: text, body: form, primary: primary,
                                    cancel: T("Cancel", "Cancelar"), first: first) { ok in if ok { accepted() } }
        if let sheet { perfAnswer(sheet, title: title, text: text) }
    }

    /// CADEX_PERF_SHEETS=1: the sheet is said in the log and answered by itself, as the alerts'
    /// perfAnswer (the orchestration's checks in the app read "Cadex sheet:").
    func perfAnswer(_ sheet: FrameSheet, title: String, text: String, accept: Bool = true) {
        guard ProcessInfo.processInfo.environment["CADEX_PERF_SHEETS"] == "1" else { return }
        NSLog("Cadex sheet: %@ | %@", title, text)
        let wait = ProcessInfo.processInfo.environment["CADEX_PERF_SHEETS_WAIT"].flatMap(Double.init) ?? 1.5
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak sheet] in sheet?.finish(accept) }
    }
}
