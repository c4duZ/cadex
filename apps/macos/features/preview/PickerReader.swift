import AppKit
import TempImages
import WebKit

/// Reads the page for the picker (docs/adr/0018-element-picker.md): asks
/// the script in the picker's world, then, for a click, where the element
/// was written (the one read in the page's world, React 19's stack mapped
/// back) and a picture of it.
@MainActor
final class PickerReader {
    private let web: PickingWebView
    /// Whether a pick carries a picture of the element
    /// (preview.pickScreenshot); nil takes one.
    var takesPictures: (() -> Bool)?
    /// Pictures of picked elements, in <temporary directory>/cadex-pick/.
    static let pictures = TempImageStore(folder: "cadex-pick", prefix: "pick")
    private static var cleanedPictures = false
    /// Whether this document has the script; a navigation clears it.
    private var injected = false
    /// Held for as long as the preview: WebKit drops a content world nobody
    /// holds, and the script with it. Made anew for each question, every
    /// other hover answer came back empty in the release build and the
    /// outline flashed (log of 2026-10-21).
    private let world = PickerScript.world

    init(web: PickingWebView) {
        self.web = web
        if !Self.cleanedPictures {
            Self.cleanedPictures = true
            DispatchQueue.global(qos: .utility).async { Self.pictures.removeOld() }
        }
    }

    func pageChanged() { injected = false }

    /// The element under a view point, with where it was written and its
    /// picture; nil over nothing pickable (the page's background).
    func read(at point: CGPoint, then done: @escaping @MainActor (PickedElement?) -> Void) {
        let page = web.url?.absoluteString ?? ""
        let mark = UUID().uuidString
        ask("describe", point, mark: mark) { [weak self] answer in
            guard let self, let answer, let element = PickedElement(json: answer, page: page) else { return done(nil) }
            guard PickedElement.object(answer)?["marked"] as? Bool == true else { return withPicture(element, done) }
            readPageSource(mark) { [weak self] json in
                var read = element
                let stack = json.flatMap { read.merge(pageSource: $0) }
                guard let self else { return done(nil) }
                guard let stack else { return withPicture(read, done) }
                // React 19: map the stack back (plan 16, phase C).
                let page = web.url
                Task { @MainActor [weak self] in
                    read.source = await SourceLookup.resolve(stack: stack, page: page)
                    self?.withPicture(read, done)
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

    private func withPicture(_ element: PickedElement, _ done: @escaping @MainActor (PickedElement?) -> Void) {
        picture(of: element.box) { path in
            var element = element
            element.screenshot = path
            done(element)
        }
    }

    /// A PNG of the element as shown (plan 16, phase D).
    private func picture(of box: CGRect, then done: @escaping @MainActor (String?) -> Void) {
        guard takesPictures?() ?? true, let rect = Self.pictureRect(viewBox(box), in: web.bounds) else { return done(nil) }
        let configuration = WKSnapshotConfiguration()
        configuration.rect = rect
        // Wide elements (a whole page) come out at most 1600 points across.
        if rect.width > 1600 { configuration.snapshotWidth = 1600 }
        web.takeSnapshot(with: configuration) { image, _ in
            MainActor.assumeIsolated {
                guard let image, let tiff = image.tiffRepresentation,
                      let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]),
                      let url = try? Self.pictures.save(TempImageStore.fitted(png)) else { return done(nil) }
                done(url.path)
            }
        }
    }

    /// The element with a margin of 8 points, cut to what the view shows:
    /// a snapshot must lie inside the view's bounds (WKSnapshotConfiguration).
    static func pictureRect(_ box: CGRect, in bounds: CGRect) -> CGRect? {
        let rect = box.insetBy(dx: -8, dy: -8).intersection(bounds)
        return rect.isNull || rect.width < 1 || rect.height < 1 ? nil : rect
    }

    /// Asks the picker's world; the script goes along the first time, and
    /// again on a failed question (a navigation took it), once.
    func ask(_ function: String, _ point: CGPoint, mark: String? = nil, then done: @escaping @MainActor (String?) -> Void) {
        ask(function, point, mark: mark, retry: true, then: done)
    }

    private func ask(_ function: String, _ point: CGPoint, mark: String?, retry: Bool,
                     then done: @escaping @MainActor (String?) -> Void) {
        let zoom = web.pageZoom > 0 ? web.pageZoom : 1
        let script = PickerScript.call(function, x: point.x / zoom, y: point.y / zoom, mark: mark, inject: !injected)
        web.evaluateJavaScript(script, in: nil, in: world) { [weak self] result in
            MainActor.assumeIsolated {
                guard let self else { return }
                switch result {
                case .success(let value):
                    self.injected = true
                    done(value as? String)
                case .failure where retry && self.injected:
                    self.injected = false
                    self.ask(function, point, mark: mark, retry: false, then: done)
                case .failure:
                    self.injected = false
                    done(nil)
                }
            }
        }
    }

    /// CSS pixels to view points.
    func viewBox(_ box: CGRect) -> CGRect {
        let zoom = web.pageZoom > 0 ? web.pageZoom : 1
        return CGRect(x: box.minX * zoom, y: box.minY * zoom, width: box.width * zoom, height: box.height * zoom)
    }
}
