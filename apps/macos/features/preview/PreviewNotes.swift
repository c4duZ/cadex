import AppKit
import Strings
import WebKit

/// Notes the owner pins to elements of the page for the agent (docs/spec/preview.md,
/// Design Mode e notas; plan 20 phase D): ⌘+click while picking (or
/// preview.add-note, then a click) opens a field under the element; Enter
/// keeps the note, Esc gives it up. Numbered markers sit over the page and
/// follow their elements as it scrolls. The notes live as long as the tab;
/// preview.send-notes pastes them all to the agent, `browser_notes` reads them.
@MainActor
final class PreviewNotes: NSObject, NSTextFieldDelegate {
    struct Note {
        var element: PickedElement
        var text: String
    }

    private(set) var notes: [Note] = []
    private weak var web: PickingWebView?
    private let markers = PreviewNoteMarkers()
    let field = NSTextField()
    private var editing: PickedElement?
    private var refreshing = false
    /// Held as long as the tab, as the picker's.
    private let world = PickerScript.world

    init(web: PickingWebView) {
        self.web = web
        super.init()
        field.placeholderString = T("A note for the agent · Enter keeps · Esc gives up", "Uma nota para o agente · Enter guarda · Esc desiste")
        field.font = .systemFont(ofSize: 12)
        field.delegate = self
        field.isHidden = true
        markers.addSubview(field)
        web.onScrolled = { [weak self] in self?.refresh() }
    }

    /// The markers' view, over the page; the document lays it out.
    var view: NSView { markers }

    /// A field under the element for the owner's note.
    func edit(_ element: PickedElement, at box: CGRect) {
        editing = element
        let width = max(220, min(360, box.width))
        field.frame = NSRect(x: max(4, min(box.minX, markers.bounds.width - width - 4)), y: min(box.maxY + 6, markers.bounds.height - 30), width: width, height: 24)
        field.stringValue = ""
        field.isHidden = false
        markers.window?.makeFirstResponder(field)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) {
            let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if let element = editing, !text.isEmpty { notes.append(Note(element: element, text: String(text.prefix(500)))) }
            finishEditing()
            return true
        }
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            finishEditing()
            return true
        }
        return false
    }

    private func finishEditing() {
        editing = nil
        field.isHidden = true
        markers.window?.makeFirstResponder(web)
        refresh()
    }

    func clear() {
        notes = []
        markers.places = []
    }

    /// What `browser_notes` gives the agent: each note, the owner's words
    /// first, then the element as the picker describes it.
    func forAgent(relativeTo folder: String?) -> String {
        guard !notes.isEmpty else { return "(no notes on this tab)" }
        return delivery(agentTerminal: nil).text(relativeTo: folder)
    }

    func delivery(agentTerminal: String?) -> PickDelivery {
        PickDelivery(elements: notes.map(\.element), toClipboard: false, agentTerminal: agentTerminal, notes: notes.map(\.text))
    }

    /// The markers where their elements are now (asked by selector in the
    /// picker's world); one not on the page has no marker.
    func refresh() {
        guard let web, !notes.isEmpty, !refreshing else { if notes.isEmpty { markers.places = [] }; return }
        refreshing = true
        let selectors = notes.map(\.element.selector).map(BrowserScript.literal).joined(separator: ",")
        web.evaluateJavaScript(BrowserScript.call("boxes([\(selectors)])", inject: true), in: nil, in: world) { [weak self] result in
            MainActor.assumeIsolated {
                guard let self, let web = self.web else { return }
                self.refreshing = false
                let boxes = ((try? result.get()) as? String).flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [Any] } ?? []
                self.markers.places = boxes.enumerated().compactMap { index, value in
                    guard let box = PickedElement.rect(value) else { return nil }
                    let corner = PreviewAgentInput.viewPoint(cssX: box.minX, cssY: box.minY, in: web)
                    return (index + 1, corner)
                }
            }
        }
    }
}

/// The numbered markers over the page, and the note field; clicks pass to
/// the page except on the field.
@MainActor
final class PreviewNoteMarkers: NSView {
    var places: [(Int, NSPoint)] = [] { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }

    override func draw(_ dirtyRect: NSRect) {
        for (number, corner) in places {
            let circle = NSRect(x: corner.x - 9, y: corner.y - 9, width: 18, height: 18)
            NSColor.systemOrange.setFill()
            NSBezierPath(ovalIn: circle).fill()
            let text = NSAttributedString(string: "\(number)", attributes: [.font: NSFont.boldSystemFont(ofSize: 10), .foregroundColor: NSColor.white])
            let size = text.size()
            text.draw(at: NSPoint(x: circle.midX - size.width / 2, y: circle.midY - size.height / 2))
        }
    }
}
