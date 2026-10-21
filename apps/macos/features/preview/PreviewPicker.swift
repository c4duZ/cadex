import AppKit
import Strings
import WebKit

/// Picking an element of the page (docs/spec/preview.md, "Escolher
/// elemento"): the mouse goes to the script in the picker's world, the
/// answer to the overlay, and the click to whoever delivers it (the app:
/// the agent's terminal or the clipboard). Nothing is left in the page:
/// no user script, no message handler (docs/adr/0018-element-picker.md).
@MainActor
final class PreviewPicker {
    private let web: PickingWebView
    private let overlay: PickerOverlay
    /// Hands a pick over and says where it went; nil copies it.
    var onDeliver: ((PickDelivery) -> PickOutcome)?
    /// Picking started or ended (the bar's button follows).
    var onStateChange: (() -> Void)?
    private(set) var isPicking = false
    /// Whether this document has the script; a navigation clears it.
    private var injected = false
    /// One question at a time while hovering; the newest point waits.
    private var asking = false
    private var waiting: CGPoint?

    init(web: PickingWebView, overlay: PickerOverlay) {
        self.web = web
        self.overlay = overlay
        web.onPickMove = { [weak self] in self?.hover($0) }
        web.onPickClick = { [weak self] in self?.click($0, $1) }
        web.onPickExit = { [weak self] in self?.overlay.target = nil }
        web.onResign = { [weak self] in self?.stop() }
    }

    func toggle() { isPicking ? stop() : start() }

    func start() {
        guard !isPicking else { return }
        isPicking = true
        web.isPicking = true
        overlay.showsBanner = true
        // So Esc reaches the preview and a click elsewhere ends picking.
        web.window?.makeFirstResponder(web)
        onStateChange?()
    }

    func stop() {
        guard isPicking else { return }
        isPicking = false
        web.isPicking = false
        overlay.showsBanner = false
        overlay.target = nil
        waiting = nil
        onStateChange?()
    }

    /// A new document: the script is gone and the outline is stale.
    func pageChanged() {
        injected = false
        overlay.target = nil
    }

    private func hover(_ point: CGPoint) {
        guard !asking else { return waiting = point }
        asking = true
        ask("at", point) { [weak self] answer in
            guard let self else { return }
            asking = false
            if isPicking { overlay.target = answer.flatMap(mark) }
            if let next = waiting {
                waiting = nil
                hover(next)
            }
        }
    }

    private func click(_ point: CGPoint, _ flags: NSEvent.ModifierFlags) {
        let page = web.url?.absoluteString ?? ""
        let mark = UUID().uuidString
        ask("describe", point, mark: mark) { [weak self] answer in
            guard let self, let answer, let element = PickedElement(json: answer, page: page) else { return }
            guard PickedElement.object(answer)?["marked"] as? Bool == true else { return deliver(element, flags) }
            readPageSource(mark) { [weak self] json in
                var read = element
                let stack = json.flatMap { read.merge(pageSource: $0) }
                guard let stack, let self else { self?.deliver(read, flags); return }
                // React 19: map the stack back, then deliver (plan 16, phase C).
                let page = web.url
                Task { @MainActor [weak self] in
                    read.source = await SourceLookup.resolve(stack: stack, page: page)
                    self?.deliver(read, flags)
                }
            }
        }
    }

    /// The one read in the page's world, for where the element was written.
    private func readPageSource(_ mark: String, then done: @escaping @MainActor (String?) -> Void) {
        web.callAsyncJavaScript(PageSourceScript.body, arguments: ["mark": mark], in: nil, in: .page) { result in
            MainActor.assumeIsolated { done((try? result.get()) as? String) }
        }
    }

    private func deliver(_ element: PickedElement, _ flags: NSEvent.ModifierFlags) {
        let delivery = PickDelivery(element: element, toClipboard: flags.contains(.option), keepPicking: flags.contains(.shift))
        let outcome = onDeliver?(delivery) ?? Self.copy(delivery.text())
        if !delivery.keepPicking { stop() }
        overlay.flash(PickerOverlay.Mark(box: viewBox(element.box), label: Self.flashText(outcome)),
                      color: Self.flashColor(outcome))
    }

    /// Asks the picker's world; the script goes along the first time.
    private func ask(_ function: String, _ point: CGPoint, mark: String? = nil, then done: @escaping @MainActor (String?) -> Void) {
        let zoom = web.pageZoom > 0 ? web.pageZoom : 1
        let script = PickerScript.call(function, x: point.x / zoom, y: point.y / zoom, mark: mark, inject: !injected)
        web.evaluateJavaScript(script, in: nil, in: PickerScript.world) { [weak self] result in
            MainActor.assumeIsolated {
                switch result {
                case .success(let value):
                    self?.injected = true
                    done(value as? String)
                case .failure:
                    // A navigation took the script with it: inject again next time.
                    self?.injected = false
                    done(nil)
                }
            }
        }
    }

    /// CSS pixels to view points.
    private func viewBox(_ box: CGRect) -> CGRect {
        let zoom = web.pageZoom > 0 ? web.pageZoom : 1
        return CGRect(x: box.minX * zoom, y: box.minY * zoom, width: box.width * zoom, height: box.height * zoom)
    }

    private func mark(_ json: String) -> PickerOverlay.Mark? {
        guard let object = PickedElement.object(json), let box = PickedElement.rect(object["box"]) else { return nil }
        return PickerOverlay.Mark(box: viewBox(box), label: object["label"] as? String ?? "")
    }

    static func copy(_ text: String) -> PickOutcome {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        return .copied(note: nil)
    }

    static func flashText(_ outcome: PickOutcome) -> String {
        switch outcome {
        case .pasted(let name): T("Pasted into \(name)", "Colado em \(name)")
        case .copied(let note): note ?? T("Copied", "Copiado")
        }
    }

    static func flashColor(_ outcome: PickOutcome) -> NSColor {
        if case .pasted = outcome { return PickerOverlay.pastedColor }
        return PickerOverlay.copiedColor
    }
}
