import AppKit
import Strings
import WebKit

/// Picking elements of the page (docs/spec/preview.md, "Escolher
/// elemento"): the outline follows the mouse; a click sends the element; ⇧
/// +click marks it green and adds it to the selection, which goes out all at
/// once when ⇧ is let go. Whoever delivers is the app (the agent's terminal
/// or the clipboard). Nothing is left in the page: no user script, no
/// message handler (docs/adr/0018-element-picker.md).
@MainActor
final class PreviewPicker {
    private let web: PickingWebView
    private let overlay: PickerOverlay
    let reader: PickerReader
    /// Hands the picks over and says where they went; nil copies them.
    var onDeliver: ((PickDelivery) -> PickOutcome)?
    /// Picking started or ended (the bar's button follows).
    var onStateChange: (() -> Void)?
    /// The terminal of the agent driving this tab, nil without one (plan
    /// 20): the picks go there first, with their computed styles.
    var agentTerminal: (() -> String?)?
    /// ⌘+click, or any click after preview.add-note: a note for this
    /// element (PreviewNotes), with its box in the view.
    var onNote: ((PickedElement, CGRect) -> Void)?
    var takesNote = false
    /// A note is being written: losing the focus to its field does not stop picking.
    var holdsWhileNoting = false
    private(set) var isPicking = false
    /// Marked with ⇧, in the order clicked.
    private(set) var selection: [PickedElement] = []
    /// Clicks still being read; the selection goes out when they are done.
    private var reading = 0
    private var sendWhenRead = false
    /// ⌥ on any click: the selection goes to the clipboard.
    private var copies = false
    /// One hover question at a time, at most every 30 ms, for the newest
    /// point: answers to every move made the outline jump (owner,
    /// 2026-10-21).
    private var asking = false
    private var waiting: CGPoint?
    private var lastAsk = Date.distantPast

    init(web: PickingWebView, overlay: PickerOverlay) {
        self.web = web
        self.overlay = overlay
        reader = PickerReader(web: web)
        web.onPickMove = { [weak self] in self?.hover($0) }
        web.onPickClick = { [weak self] in self?.click($0, $1) }
        web.onPickExit = { [weak self] in self?.overlay.target = nil }
        web.onShiftUp = { [weak self] in self?.shiftUp() }
        web.onResign = { [weak self] in
            // The note's field takes the keyboard: picking goes on, so the
            // owner pins several notes in a row (2026-11-15).
            guard self?.holdsWhileNoting != true else { return }
            self?.stop()
        }
    }

    func toggle() { isPicking ? stop() : start() }

    /// preview.add-note: picking, the next click pins a note.
    func startNote() {
        start()
        takesNote = true
        showSelection()
    }

    func start() {
        guard !isPicking else { return }
        isPicking = true
        web.isPicking = true
        showSelection()
        // So Esc and ⇧ reach the preview, and a click elsewhere ends picking.
        web.window?.makeFirstResponder(web)
        onStateChange?()
    }

    /// Ends picking; a selection not sent is dropped (Esc).
    func stop() {
        guard isPicking else { return }
        isPicking = false
        web.isPicking = false
        selection = []
        reading = 0
        sendWhenRead = false
        copies = false
        takesNote = false
        waiting = nil
        overlay.target = nil
        overlay.selected = []
        overlay.banner = nil
        onStateChange?()
    }

    /// A new document: the script is gone, the outlines are stale.
    func pageChanged() {
        reader.pageChanged()
        overlay.target = nil
    }

    // MARK: Hover

    private func hover(_ point: CGPoint) {
        waiting = point
        guard !asking else { return }
        let wait = 0.03 - Date().timeIntervalSince(lastAsk)
        guard wait <= 0 else {
            asking = true
            DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
                self?.asking = false
                self?.askWaiting()
            }
            return
        }
        askWaiting()
    }

    private func askWaiting() {
        guard isPicking, let point = waiting else { return }
        waiting = nil
        asking = true
        lastAsk = Date()
        reader.ask("at", point) { [weak self] answer in
            guard let self else { return }
            asking = false
            if isPicking { overlay.target = answer.flatMap(mark) }
            if let next = waiting { hover(next) }
        }
    }

    private func mark(_ json: String) -> PickerOverlay.Mark? {
        guard let object = PickedElement.object(json), let box = PickedElement.rect(object["box"]) else { return nil }
        return PickerOverlay.Mark(box: reader.viewBox(box), label: object["label"] as? String ?? "")
    }

    // MARK: Selecting and sending

    private func click(_ point: CGPoint, _ flags: NSEvent.ModifierFlags) {
        if flags.contains(.command) || takesNote { return note(at: point) }
        let adding = flags.contains(.shift)
        if flags.contains(.option) { copies = true }
        if !adding { sendWhenRead = true }
        reading += 1
        reader.read(at: point) { [weak self] element in
            guard let self, isPicking else { return }
            reading -= 1
            if var element {
                // Design Mode: the styles go only to an agent driving this tab.
                if agentTerminal?() == nil { element.styles = nil }
                select(element, toggling: adding)
            }
            if sendWhenRead, reading == 0 { send() }
        }
    }

    /// The element under the click gets a note; the field takes the keys and
    /// picking goes on after it, for the next note (it ended here until
    /// 2026-11-15, so each note asked for ⌘⇧C again).
    private func note(at point: CGPoint) {
        reader.read(at: point) { [weak self] element in
            guard let self, isPicking else { return }
            takesNote = false
            overlay.target = nil
            showSelection()
            if let element { onNote?(element, reader.viewBox(element.box)) }
        }
    }

    /// ⇧+click on a marked element unmarks it.
    private func select(_ element: PickedElement, toggling: Bool) {
        if let index = selection.firstIndex(where: { $0.selector == element.selector }) {
            if toggling { selection.remove(at: index) }
        } else {
            selection.append(element)
        }
        showSelection()
    }

    private func shiftUp() {
        guard isPicking, !selection.isEmpty || reading > 0 else { return }
        sendWhenRead = true
        if reading == 0 { send() }
    }

    private func send() {
        let picked = selection
        guard !picked.isEmpty else { return stop() }
        let delivery = PickDelivery(elements: picked, toClipboard: copies, agentTerminal: agentTerminal?())
        let outcome = onDeliver?(delivery) ?? Self.copy(delivery.text())
        stop()
        let marks = picked.enumerated().map { index, element in
            PickerOverlay.Mark(box: reader.viewBox(element.box),
                               label: index == 0 ? Self.flashText(outcome, count: picked.count) : "\(index + 1)")
        }
        overlay.flash(marks, color: Self.flashColor(outcome))
    }

    private func showSelection() {
        overlay.selected = selection.enumerated().map { index, element in
            PickerOverlay.Mark(box: reader.viewBox(element.box), label: "\(index + 1)")
        }
        overlay.banner = takesNote
            ? T("Click an element to pin a note to it · Esc stops", "Clique num elemento para prender uma nota · Esc sai")
            : selection.isEmpty
            ? T("Click an element · ⇧+click marks several · ⌘+click adds a note · ⌥ copies · Esc stops",
                "Clique num elemento · ⇧+clique marca vários · ⌘+clique põe uma nota · ⌥ copia · Esc sai")
            : T("\(selection.count) marked · let go of ⇧ to send · Esc cancels",
                "\(selection.count) marcado(s) · solte o ⇧ para enviar · Esc cancela")
    }

    static func copy(_ text: String) -> PickOutcome {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        return .copied(note: nil)
    }

    static func flashText(_ outcome: PickOutcome, count: Int) -> String {
        let what = count > 1 ? T("\(count) elements · ", "\(count) elementos · ") : ""
        switch outcome {
        case .pasted(let name): return what + T("Pasted into \(name)", "Colado em \(name)")
        case .copied(let note): return what + (note ?? T("Copied", "Copiado"))
        }
    }

    static func flashColor(_ outcome: PickOutcome) -> NSColor {
        if case .pasted = outcome { return PickerOverlay.pastedColor }
        return PickerOverlay.copiedColor
    }
}
