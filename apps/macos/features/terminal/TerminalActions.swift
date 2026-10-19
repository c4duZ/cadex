import AppKit
import CommandPalette

/// The terminal's commands (ADR 0005). Each one is an action the focused
/// TerminalView answers through the responder chain, so it runs on the
/// terminal with focus and is unavailable when no terminal has it.
public enum TerminalCommands {
    private static let noTerminal = "Nenhum terminal com foco"

    @MainActor
    public static var all: [Command] {
        [
            .responder("terminal.clear", "Limpar o terminal", keywords: ["clear", "cls", "tela"],
                       category: .terminal, shortcut: "cmd+l",
                       selector: #selector(TerminalView.terminalClear(_:)), reason: noTerminal),
            .responder("terminal.scroll-top", "Ir ao topo do histórico", keywords: ["scroll", "rolar", "início"],
                       category: .terminal, shortcut: "cmd+up",
                       selector: #selector(TerminalView.terminalScrollToTop(_:)), reason: noTerminal),
            .responder("terminal.scroll-bottom", "Ir ao fim do histórico", keywords: ["scroll", "rolar", "final"],
                       category: .terminal, shortcut: "cmd+down",
                       selector: #selector(TerminalView.terminalScrollToBottom(_:)), reason: noTerminal),
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
