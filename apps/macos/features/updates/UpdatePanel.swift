import AppKit
import Strings

/// The small window of "Check for Updates" (docs/spec/updates.md): what was
/// found, the release notes, the download's progress, and buttons that run
/// the updates commands. Closing it changes nothing; a download goes on.
@MainActor
final class UpdatePanel: NSObject {
    private unowned let controller: UpdateController
    private var window: NSPanel?
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(wrappingLabelWithString: "")
    private let notes = NSTextView()
    private lazy var notesScroll = NSScrollView()
    private let progress = NSProgressIndicator()
    private let secondButton = NSButton(title: "", target: nil, action: nil)
    private let mainButton = NSButton(title: "", target: nil, action: nil)
    /// The command the main button runs, if any; otherwise it closes.
    private var mainCommand: String?

    init(controller: UpdateController) {
        self.controller = controller
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        render()
        if !window.isVisible { window.center() }
        window.makeKeyAndOrderFront(nil)
    }

    /// Follows the controller's state while open.
    func render() {
        guard let window else { return }
        let state = controller.state
        let current = controller.currentVersion
        var notesText = ""
        progress.isHidden = true
        mainCommand = nil
        secondButton.isHidden = true
        switch state {
        case .idle, .checking:
            set(T("Checking for updates…", "Procurando atualizações…"), "")
            showProgress(nil)
            mainButton.title = T("Close", "Fechar")
        case .upToDate:
            set(T("Cadex is up to date", "O Cadex está em dia"), T("Version \(current)", "Versão \(current)"))
            mainButton.title = T("Close", "Fechar")
        case .available(let release):
            set(T("Cadex \(release.version) is available", "Cadex \(release.version) disponível"),
                T("You are on \(current).", "Você está na \(current)."))
            notesText = release.notes
            secondButton.title = T("Later", "Depois")
            secondButton.isHidden = false
            mainButton.title = T("Install and Reopen", "Instalar e reabrir")
            mainCommand = "app.install-update"
        case .downloading(let done, let total):
            set(T("Downloading the update…", "Baixando a atualização…"), UpdateController.percent(done, total))
            showProgress(total.map { Double(done) / Double(max($0, 1)) })
            mainButton.title = T("Hide", "Esconder")
        case .installed(let version):
            set(T("Cadex \(version) is installed", "Cadex \(version) instalado"),
                T("Reopen Cadex to start using it.", "Reabra o Cadex para começar a usar."))
            secondButton.title = T("Later", "Depois")
            secondButton.isHidden = false
            mainButton.title = T("Reopen Now", "Reabrir agora")
            mainCommand = "app.install-update"
        case .failed(let message):
            set(T("The update did not work", "A atualização não deu certo"), message)
            secondButton.title = T("Close", "Fechar")
            secondButton.isHidden = false
            mainButton.title = T("Try Again", "Tentar de novo")
            mainCommand = "app.check-for-updates"
        }
        notes.string = notesText
        notesScroll.isHidden = notesText.isEmpty
        window.title = T("Cadex Update", "Atualização do Cadex")
    }

    private func set(_ title: String, _ detail: String) {
        titleLabel.stringValue = title
        detailLabel.stringValue = detail
        detailLabel.isHidden = detail.isEmpty
    }

    /// A bar with the fraction done, or a moving one when unknown.
    private func showProgress(_ fraction: Double?) {
        progress.isHidden = false
        progress.isIndeterminate = fraction == nil
        if let fraction {
            progress.stopAnimation(nil)
            progress.doubleValue = fraction
        } else {
            progress.startAnimation(nil)
        }
    }

    @objc private func mainPressed() {
        guard let command = mainCommand else { return close() }
        controller.runCommand?(command)
    }

    @objc private func close() {
        window?.orderOut(nil)
    }

    private func makeWindow() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 160),
                            styleMask: [.titled, .closable], backing: .buffered, defer: true)
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        titleLabel.font = .boldSystemFont(ofSize: 14)
        detailLabel.font = .systemFont(ofSize: 12)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.preferredMaxLayoutWidth = 400
        notes.isEditable = false
        notes.font = .systemFont(ofSize: 12)
        notes.textContainerInset = NSSize(width: 6, height: 6)
        notes.autoresizingMask = [.width]
        notesScroll.documentView = notes
        notesScroll.hasVerticalScroller = true
        notesScroll.borderType = .bezelBorder
        notesScroll.heightAnchor.constraint(equalToConstant: 150).isActive = true
        progress.style = .bar
        progress.minValue = 0
        progress.maxValue = 1
        secondButton.target = self
        secondButton.action = #selector(close)
        mainButton.target = self
        mainButton.action = #selector(mainPressed)
        mainButton.keyEquivalent = "\r"
        secondButton.keyEquivalent = "\u{1b}"
        let buttons = NSStackView(views: [NSView(), secondButton, mainButton])
        buttons.spacing = 8
        let stack = NSStackView(views: [titleLabel, detailLabel, notesScroll, progress, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 16, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            content.widthAnchor.constraint(equalToConstant: 440),
            notesScroll.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
            progress.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
        ])
        panel.contentView = content
        return panel
    }
}
