import AppKit
import UILooks
import Icons
import Menus
import Tabs
import WebKit
import Strings

/// A web page in a tab (docs/spec/preview.md): the server an agent started
/// in the terminal, next to the code. The page is isolated: no bridge to
/// the app, no file: URLs, website data only while the app runs.
@MainActor
public final class PreviewDocument: NSObject, TabDocument, WKNavigationDelegate, WKUIDelegate, NSTextFieldDelegate {
    public let view = NSView()
    public var onChange: (() -> Void)?
    let web: WKWebView
    let address = NSTextField()
    private let progress = NSProgressIndicator()
    private let back: NSButton
    private let forward: NSButton
    private let message = NSTextField(labelWithString: "")
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
        web = WKWebView(frame: .zero, configuration: configuration)
        back = Self.button(.arrowLeft, T("Back", "Voltar"))
        forward = Self.button(.arrowRight, T("Forward", "Avançar"))
        super.init()
        web.navigationDelegate = self
        web.uiDelegate = self
        // "Inspecionar elemento" in the page's context menu (macOS 13.3+).
        if #available(macOS 13.3, *) { web.isInspectable = true }
        layout()
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
    public func close() { web.stopLoading() }

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
        onChange?()
    }

    /// A page started showing: an older error no longer applies (it stayed
    /// over the next page, 2026-10-19).
    public func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        message.isHidden = true
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        // Cancelled: a new address replaced it, not a failure.
        if (error as NSError).code == NSURLErrorCancelled { return }
        message.stringValue = T("Couldn't connect to \(address.stringValue)\n\(error.localizedDescription)", "Não foi possível conectar a \(address.stringValue)\n\(error.localizedDescription)")
        message.isHidden = false
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
    }

    private static func button(_ icon: Icon, _ tip: String) -> NSButton {
        let b = NSButton(image: icon.image(size: 14), target: nil, action: nil)
        b.isBordered = false
        HoverTip.attach(tip, to: b)
        b.widthAnchor.constraint(equalToConstant: 24).isActive = true
        return b
    }

    private func layout() {
        let reload = Self.button(.arrowClockwise, T("Reload", "Recarregar"))
        back.target = self
        back.action = #selector(backPressed)
        forward.target = self
        forward.action = #selector(forwardPressed)
        reload.target = self
        reload.action = #selector(reloadPressed)
        back.isEnabled = false
        forward.isEnabled = false
        address.delegate = self
        address.placeholderString = "http://localhost:3000"
        address.font = UILooks.font(12)
        address.bezelStyle = .roundedBezel
        progress.style = .bar
        progress.isIndeterminate = false
        progress.controlSize = .small
        progress.isHidden = true
        message.alignment = .center
        message.textColor = .secondaryLabelColor
        message.isHidden = true
        let bar = NSStackView(views: [back, forward, reload, address])
        bar.spacing = 4
        bar.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 4, right: 8)
        for v in [bar, progress, web, message] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(v)
        }
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: view.topAnchor),
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progress.topAnchor.constraint(equalTo: bar.bottomAnchor),
            progress.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progress.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progress.heightAnchor.constraint(equalToConstant: 2),
            web.topAnchor.constraint(equalTo: progress.bottomAnchor),
            web.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            web.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            message.centerXAnchor.constraint(equalTo: web.centerXAnchor),
            message.centerYAnchor.constraint(equalTo: web.centerYAnchor),
            message.widthAnchor.constraint(lessThanOrEqualTo: web.widthAnchor, constant: -40),
        ])
    }

    @objc private func backPressed() { goBack() }
    @objc private func forwardPressed() { goForward() }
    @objc private func reloadPressed() { reload() }
}
