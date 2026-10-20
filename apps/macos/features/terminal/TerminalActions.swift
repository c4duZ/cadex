import AppKit
import CommandPalette
import Strings

/// The terminal's commands (ADR 0005). Each one is an action the focused
/// TerminalView answers through the responder chain, so it runs on the
/// terminal with focus and is unavailable when no terminal has it.
public enum TerminalCommands {
    private static let noTerminal = T("No terminal has focus", "Nenhum terminal com foco")
    private static let noImage = T("No image was pasted in this terminal", "Nenhuma imagem colada neste terminal")

    @MainActor
    public static var all: [Command] {
        [
            .responder("terminal.clear", T("Clear Terminal", "Limpar o terminal"), keywords: ["clear", "cls", "tela", "screen"],
                       category: .terminal, shortcut: "cmd+l",
                       selector: #selector(TerminalView.terminalClear(_:)), reason: noTerminal),
            .responder("terminal.scroll-top", T("Scroll to Top", "Ir ao topo do histórico"), keywords: ["scroll", "rolar", "início", "top", "history"],
                       category: .terminal, shortcut: "cmd+up",
                       selector: #selector(TerminalView.terminalScrollToTop(_:)), reason: noTerminal),
            .responder("terminal.scroll-bottom", T("Scroll to Bottom", "Ir ao fim do histórico"), keywords: ["scroll", "rolar", "final", "bottom", "history"],
                       category: .terminal, shortcut: "cmd+down",
                       selector: #selector(TerminalView.terminalScrollToBottom(_:)), reason: noTerminal),
            .responder("terminal.open-pasted-image-beside", T("Open Last Pasted Image Beside", "Abrir a última imagem colada ao lado"),
                       keywords: ["image", "imagem", "paste", "colar", "print", "screenshot"], category: .terminal,
                       selector: #selector(TerminalView.openLastPastedImageBeside(_:)), reason: noImage),
            .responder("terminal.open-pasted-image-in-tab", T("Open Last Pasted Image in New Tab", "Abrir a última imagem colada em nova aba"),
                       keywords: ["image", "imagem", "paste", "colar", "print", "screenshot"], category: .terminal,
                       selector: #selector(TerminalView.openLastPastedImageInTab(_:)), reason: noImage),
        ]
    }
}

/// The actions behind the commands, and the standard edit actions (copy,
/// paste, select all) that the Edit menu and ⌘C/⌘V/⌘A send.
extension TerminalView {
    /// Clear screen (docs/spec/terminal.md): Ctrl+L, which shells redraw.
    @objc public func terminalClear(_ sender: Any?) {
        session?.write("\u{0C}")
    }

    /// edit.find (⌘F) with the terminal focused.
    @objc public func showFind(_ sender: Any?) {
        showFindBar()
    }

    @objc public func terminalScrollToTop(_ sender: Any?) {
        session?.scrollToTop()
        needsDisplay = true
    }

    @objc public func terminalScrollToBottom(_ sender: Any?) {
        session?.scrollToBottom()
        needsDisplay = true
    }

    @objc public func copy(_ sender: Any?) {
        copySelection()
    }

    @objc public func paste(_ sender: Any?) {
        pasteFromClipboard()
    }

    public override func selectAll(_ sender: Any?) {
        session?.selectAll()
        needsDisplay = true
    }
}
