import AppKit
import UILooks
import Icons
import Menus
import Tabs
import WebKit
import Strings

/// A web page in a tab (docs/spec/preview.md): the server an agent started
/// in the terminal, next to the code. The page is isolated: no object of
/// the app and no message channel in it, no file: URLs, website data only
/// while the app runs. The element picker reads it from a world of its own
/// (PreviewPicker, docs/adr/0018-element-picker.md).
@MainActor
public final class PreviewDocument: NSObject, TabDocument, WKNavigationDelegate, WKUIDelegate, NSTextFieldDelegate {
    public let view = NSView()
    public var onChange: (() -> Void)?
    let web: PickingWebView
    let address = NSTextField()
    let overlay = PickerOverlay()
    let pick = NSButton(title: "", target: nil, action: nil)
    /// The page's dot in the address box (PreviewBar.swift).
    let dot = NSView()
    /// The page's sizes (the mockup's desktop and phone), and which one shows.
    let desktop = PreviewBar.icon(.monitor, T("Desktop width", "Largura de desktop"))
    let phone = PreviewBar.icon(.deviceMobile, T("Phone width", "Largura de celular"))
    var phoneSized = false
    var sizes: (full: [NSLayoutConstraint], phone: [NSLayoutConstraint]) = ([], [])
    private lazy var picker = PreviewPicker(web: web, overlay: overlay)
    /// Runs a command by id: the bar's pick button fires preview.pick-element.
    public var runCommand: ((String) -> Bool)?
    /// More controls at the end of the bar, given by the app (plan 23:
    /// sharing the page on the tailnet); they run commands by id. The
    /// preview does not know what they are.
    @MainActor public static var extraBarItems: ((PreviewDocument) -> [NSView])?
    /// The bar is the pane's header (the PreviewOne mockup).
    public var barIsHeader: Bool { true }
    /// The page shown now (nil before the first load).
    public var currentURL: URL? { web.url }
    let progress = NSProgressIndicator()
    let back = PreviewBar.icon(.caretLeft, T("Back", "Voltar"))
    let forward = PreviewBar.icon(.caretRight, T("Forward", "Avançar"))
    let message = NSTextField(labelWithString: "")
    private var observations: [NSKeyValueObservation] = []
    /// Loaded when the tab first shows: a page loaded before its view was
    /// in a window was never drawn (2026-10-19).
    private var pending: String?
    /// Fixed at creation: the same address opens the same tab.
    public let identity: String

    /// The tail Safari adds to WebKit's user agent. Without it Google took
    /// the preview for an unknown browser: the old basic HTML page, then the
    /// "unusual traffic" captcha on searching (owner, 2026-10-19).
    static var safariUserAgent: String {
        let info = NSDictionary(contentsOfFile: "/Applications/Safari.app/Contents/Info.plist")
        let version = info?["CFBundleShortVersionString"] as? String ?? "18.0"
        return "Version/\(version) Safari/605.1.15"
    }

    /// An empty `url` opens a blank tab with the address bar ready.
    public init(url: String) {
        identity = Self.identity(for: url)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.applicationNameForUserAgent = Self.safariUserAgent
        web = PickingWebView(frame: .zero, configuration: configuration)
        super.init()
        HoverTip.attach(T("Pick an element (⌘⇧C)", "Escolher elemento (⌘⇧C)"), to: pick)
        picker.onStateChange = { [weak self] in self?.showPicking() }
        picker.agentTerminal = { [weak self] in self?.agentController?.isAttached == true ? self?.agentTerminal : nil }
        picker.onNote = { [weak self] element, box in
            self?.picker.holdsWhileNoting = true
            self?.notes.edit(element, at: box)
        }
        web.navigationDelegate = self
        web.uiDelegate = self
        // "Inspecionar elemento" in the page's context menu (macOS 13.3+).
        if #available(macOS 13.3, *) { web.isInspectable = true }
        layoutBar()
        observations = [
            web.observe(\.title) { [weak self] _, _ in MainActor.assumeIsolated { self?.onChange?() } },
            web.observe(\.estimatedProgress) { [weak self] web, _ in
                MainActor.assumeIsolated { self?.showProgress(web.estimatedProgress, loading: web.isLoading) }
            },
            web.observe(\.isLoading) { [weak self] web, _ in
                MainActor.assumeIsolated { self?.showProgress(web.estimatedProgress, loading: web.isLoading) }
            },
            web.observe(\.canGoBack) { [weak self] web, _ in MainActor.assumeIsolated { self?.back.isEnabled = web.canGoBack } },
            web.observe(\.canGoForward) { [weak self] web, _ in MainActor.assumeIsolated { self?.forward.isEnabled = web.canGoForward } },
        ]
        pending = url
        address.stringValue = Self.url(from: url)?.absoluteString ?? ""
    }

    public var title: String {
        if let t = web.title, !t.isEmpty { return t }
        return web.url?.host.map { "\($0):\(web.url?.port ?? 80)" } ?? "Preview"
    }

    public var hasUnsavedChanges: Bool { false }
    public func focus() {
        if let url = pending, view.window != nil {
            pending = nil
            // After this turn of the loop, once the window is on screen.
            DispatchQueue.main.async { [weak self] in self?.load(url) }
        }
        view.window?.makeFirstResponder(address.stringValue.isEmpty ? address as NSView : web)
    }
    public func confirmClose(in window: NSWindow?, then close: @escaping @MainActor () -> Void) { close() }
    public func close() {
        picker.stop()
        agentController?.stop()
        web.stopLoading()
    }

    // MARK: Picking

    /// Hands a picked element over (the app: the agent's terminal or the
    /// clipboard) and says where it went. Nil copies it.
    public var onPickElement: ((PickDelivery) -> PickOutcome)? {
        get { picker.onDeliver }
        set { picker.onDeliver = newValue }
    }

    /// Whether a pick carries a picture of the element (preview.pickScreenshot).
    public var takesPictures: (() -> Bool)? {
        get { picker.reader.takesPictures }
        set { picker.reader.takesPictures = newValue }
    }

    /// The agent driving this tab (PreviewAgent.swift), made on first use;
    /// its marks go over the page.
    public var agent: PreviewAgent {
        if let agentController { return agentController }
        let made = PreviewAgent(document: self)
        let marks = made.marksView
        marks.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(marks, positioned: .above, relativeTo: overlay)
        NSLayoutConstraint.activate([
            marks.topAnchor.constraint(equalTo: web.topAnchor), marks.bottomAnchor.constraint(equalTo: web.bottomAnchor),
            marks.leadingAnchor.constraint(equalTo: web.leadingAnchor), marks.trailingAnchor.constraint(equalTo: web.trailingAnchor),
        ])
        agentController = made
        return made
    }
    private var agentController: PreviewAgent?
    /// The key of the terminal whose agent drives this tab (the app sets
    /// it with the agent's first goto).
    public var agentTerminal: String?

    /// The owner's notes on this page (PreviewNotes.swift), over the page.
    lazy var notes: PreviewNotes = {
        let made = PreviewNotes(web: web)
        let markers = made.view
        markers.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(markers, positioned: .above, relativeTo: overlay)
        NSLayoutConstraint.activate([
            markers.topAnchor.constraint(equalTo: web.topAnchor), markers.bottomAnchor.constraint(equalTo: web.bottomAnchor),
            markers.leadingAnchor.constraint(equalTo: web.leadingAnchor), markers.trailingAnchor.constraint(equalTo: web.trailingAnchor),
        ])
        // Kept or given up: picking goes on only if the keyboard is back on the page.
        made.onFinished = { [weak self] backToPage in
            guard let self else { return }
            picker.holdsWhileNoting = false
            if !backToPage { picker.stop() }
        }
        return made
    }()

    public var noteCount: Int { notes.notes.count }
    public func addNote() { picker.startNote() }
    public func clearNotes() { notes.clear() }
    /// preview.send-notes: all the notes, pasted to the agent as the picker does.
    @discardableResult
    public func sendNotes() -> PickOutcome? {
        guard noteCount > 0 else { return nil }
        let driving = agentController?.isAttached == true ? agentTerminal : nil
        let delivery = notes.delivery(agentTerminal: driving)
        return onPickElement?(delivery) ?? PreviewPicker.copy(delivery.text())
    }
    /// `browser_notes`: the notes as the agent reads them.
    public func notesForAgent() -> String { notes.forAgent(relativeTo: nil) }

    public var isPicking: Bool { picker.isPicking }
    public func togglePicking() { picker.toggle() }
    public func stopPicking() { picker.stop() }

    private func showPicking() {
        PreviewBar.pickChip(pick, picking: picker.isPicking)
    }

    /// Loads an address; without a scheme, http:// for local servers and
    /// https:// for the rest.
    public func load(_ text: String) {
        guard let url = Self.url(from: text) else { return }
        address.stringValue = url.absoluteString
        message.isHidden = true
        web.load(URLRequest(url: url))
    }

    /// The tab of a local server's address; blank tabs never match.
    public static func identity(for url: String) -> String {
        url.isEmpty ? "preview:" + UUID().uuidString : "preview:" + url
    }

    static func url(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let full = trimmed.contains("://") ? trimmed : (isLocal(trimmed) ? "http://" : "https://") + trimmed
        guard let url = URL(string: full), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else { return nil }
        return url
    }

    /// localhost, 127.x, 0.0.0.0, [::1], *.local and private IPs: dev
    /// servers, which rarely speak https. "bkdg.center" went out as http
    /// and the system refused it (owner, 2026-10-19).
    static func isLocal(_ address: String) -> Bool {
        let host = URL(string: "http://" + address)?.host?.lowercased() ?? ""
        if ["localhost", "0.0.0.0", "::1"].contains(host) || host.hasSuffix(".local") { return true }
        return ["127.", "10.", "192.168."].contains { host.hasPrefix($0) }
    }

    public func reload() { web.reload() }
    public func goBack() { web.goBack() }
    public func goForward() { web.goForward() }

    // MARK: Navigation

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let url = webView.url { address.stringValue = url.absoluteString }
        showDot(loading: false, failed: false)
        onChange?()
        agentController?.navigationEnded(error: nil)
        if noteCount > 0 { notes.refresh() }
    }

    /// A page started showing: an older error no longer applies (it stayed
    /// over the next page, 2026-10-19).
    public func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        message.isHidden = true
        picker.pageChanged()
        agentController?.pageChanged()
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        // Cancelled: a new address replaced it, not a failure.
        if (error as NSError).code == NSURLErrorCancelled { return }
        agentController?.navigationEnded(error: "could not load \(address.stringValue): \(error.localizedDescription)")
        showDot(loading: false, failed: true)
        message.stringValue = T("Couldn't connect to \(address.stringValue)\n\(error.localizedDescription)", "Não foi possível conectar a \(address.stringValue)\n\(error.localizedDescription)")
        message.isHidden = false
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        if (error as NSError).code == NSURLErrorCancelled { return }
        agentController?.navigationEnded(error: "the page failed: \(error.localizedDescription)")
    }

    /// Only http and https stay in the preview; mailto:, file: and other
    /// schemes go to the system.
    public func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url, let scheme = url.scheme?.lowercased() else { return decisionHandler(.cancel) }
        if ["http", "https", "about", "blob", "data"].contains(scheme) { return decisionHandler(.allow) }
        decisionHandler(.cancel)
        if scheme != "file" { NSWorkspace.shared.open(url) }
    }

    /// A link that opens a new window goes to the browser.
    public func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                        for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url { NSWorkspace.shared.open(url) }
        return nil
    }

    public func controlTextDidEndEditing(_ notification: Notification) {
        guard (notification.userInfo?["NSTextMovement"] as? Int) == NSTextMovement.return.rawValue else { return }
        load(address.stringValue)
        focus()
    }

    // MARK: View

    private func showProgress(_ value: Double, loading: Bool) {
        progress.doubleValue = value * 100
        progress.isHidden = !loading
        if loading { showDot(loading: true, failed: false) }
    }
}
