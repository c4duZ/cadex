import AppKit
import PDFKit

/// A PDF in a tab (docs/spec/media-preview.md): pages that scroll, zoom,
/// and ⌘F searching the text with a small bar (PDFView has no find bar of
/// its own). A locked PDF asks for its password.
@MainActor
final class PDFViewer: NSView, NSSearchFieldDelegate {
    let pdfView = PDFView()
    private let findField = NSSearchField()
    private var matches: [PDFSelection] = []
    private var current = 0
    private var findHeight: NSLayoutConstraint!

    init(path: String) {
        super.init(frame: .zero)
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.backgroundColor = .clear
        findField.placeholderString = "Buscar no PDF"
        findField.delegate = self
        findField.target = self
        findField.action = #selector(findNext)
        findField.sendsWholeSearchString = true
        findField.isHidden = true
        for v in [findField, pdfView] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        findHeight = findField.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            findField.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            findField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            findField.widthAnchor.constraint(equalToConstant: 260),
            findHeight,
            pdfView.topAnchor.constraint(equalTo: findField.bottomAnchor, constant: 6),
            pdfView.leadingAnchor.constraint(equalTo: leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: trailingAnchor),
            pdfView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        load(path)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("PDFViewer is created in code") }

    var hasDocument: Bool { pdfView.document != nil }

    func load(_ path: String) {
        guard let document = PDFDocument(url: URL(fileURLWithPath: path)) else { return }
        pdfView.document = document
        if document.isLocked { DispatchQueue.main.async { [weak self] in self?.askPassword() } }
    }

    private func askPassword() {
        guard let window, let document = pdfView.document else { return }
        let alert = NSAlert()
        alert.messageText = "Este PDF pede uma senha"
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        alert.accessoryView = field
        alert.addButton(withTitle: "Abrir")
        alert.addButton(withTitle: "Cancelar").keyEquivalent = "\u{1B}"
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { [weak self] response in
            MainActor.assumeIsolated {
                guard response == .alertFirstButtonReturn else { return }
                if !document.unlock(withPassword: field.stringValue) { self?.askPassword() }
                self?.pdfView.layoutDocumentView()
            }
        }
    }

    /// edit.find (⌘F) with the PDF focused.
    @objc func showFind(_ sender: Any?) {
        findField.isHidden = false
        findHeight.constant = 24
        window?.makeFirstResponder(findField)
    }

    @objc private func findNext() {
        guard let document = pdfView.document else { return }
        let text = findField.stringValue
        if text.isEmpty { return closeFind() }
        if matches.isEmpty || matches.first?.string?.caseInsensitiveCompare(text) != .orderedSame {
            matches = document.findString(text, withOptions: [.caseInsensitive])
            current = -1
        }
        guard !matches.isEmpty else { return NSSound.beep() }
        current = (current + 1) % matches.count
        pdfView.setCurrentSelection(matches[current], animate: true)
        pdfView.scrollSelectionToVisible(nil)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        closeFind()
        return true
    }

    private func closeFind() {
        findField.isHidden = true
        findHeight.constant = 0
        matches = []
        window?.makeFirstResponder(pdfView)
    }
}
