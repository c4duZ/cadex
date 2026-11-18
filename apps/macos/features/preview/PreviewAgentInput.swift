import AgentBand
import AppKit
import UILooks
import WebKit

/// The agent's mouse and keyboard on the page (docs/adr/0025-agent-drives-preview.md):
/// native events sent to the web view, as the system sends the owner's, so
/// the page gets trusted events (`isTrusted`); a click or key in JavaScript
/// would not be (tested 2026-11-15: click, keydown and input all trusted,
/// with the window in the background too). Pure where it can be.
@MainActor
enum PreviewAgentInput {
    /// A point in CSS pixels of the viewport, in the web view's coordinates
    /// (the view is flipped; its scale is the page's zoom).
    static func viewPoint(cssX: Double, cssY: Double, in web: WKWebView) -> NSPoint {
        let scale = web.pageZoom * web.magnification
        return NSPoint(x: cssX * scale, y: web.isFlipped ? cssY * scale : web.bounds.height - cssY * scale)
    }

    /// Move, press and release at `point` of the view.
    static func click(_ web: PickingWebView, at point: NSPoint) {
        guard let window = web.window else { return }
        let location = web.convert(point, to: nil)
        for type in [NSEvent.EventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
            guard let event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
                                                 timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                                 context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1) else { continue }
            switch type {
            case .mouseMoved: web.agentMouse(moved: event)
            case .leftMouseDown: web.agentMouse(down: event)
            default: web.agentMouse(up: event)
            }
        }
    }

    struct Key: Equatable {
        let keyCode: UInt16
        let characters: String
        let modifiers: NSEvent.ModifierFlags
    }

    /// "Enter", "Tab", "Escape", "Backspace", "Delete", "ArrowUp"…, "PageDown",
    /// "Home", "End", "Space" or one character, with "Meta+", "Control+",
    /// "Alt+" and "Shift+" before it. Nil for a name it does not know.
    static func key(_ name: String) -> Key? {
        var parts = name.split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        var base = parts.removeLast()
        if base.isEmpty, name.hasSuffix("+") { base = "+" }
        var modifiers: NSEvent.ModifierFlags = []
        for part in parts {
            switch part.lowercased() {
            case "meta", "cmd", "command": modifiers.insert(.command)
            case "control", "ctrl": modifiers.insert(.control)
            case "alt", "option": modifiers.insert(.option)
            case "shift": modifiers.insert(.shift)
            case "": continue
            default: return nil
            }
        }
        func scalar(_ value: Int) -> String { String(UnicodeScalar(UInt32(value)).map(Character.init) ?? " ") }
        let named: [String: (UInt16, String)] = [
            "enter": (36, "\r"), "return": (36, "\r"), "tab": (48, "\t"), "escape": (53, "\u{1b}"), "esc": (53, "\u{1b}"),
            "backspace": (51, "\u{7f}"), "delete": (117, scalar(NSDeleteFunctionKey)), "space": (49, " "),
            "arrowup": (126, scalar(NSUpArrowFunctionKey)), "arrowdown": (125, scalar(NSDownArrowFunctionKey)),
            "arrowleft": (123, scalar(NSLeftArrowFunctionKey)), "arrowright": (124, scalar(NSRightArrowFunctionKey)),
            "pageup": (116, scalar(NSPageUpFunctionKey)), "pagedown": (121, scalar(NSPageDownFunctionKey)),
            "home": (115, scalar(NSHomeFunctionKey)), "end": (119, scalar(NSEndFunctionKey)),
        ]
        if let (code, chars) = named[base.lowercased()] { return Key(keyCode: code, characters: chars, modifiers: modifiers) }
        guard base.count == 1 else { return nil }
        return Key(keyCode: 0, characters: modifiers.contains(.shift) ? base.uppercased() : base, modifiers: modifiers)
    }

    /// The key pressed and released in the web view, which must have the
    /// keyboard (the caller gives it and takes it back).
    static func press(_ key: Key, in web: PickingWebView) {
        guard let window = web.window else { return }
        let plain = key.characters.lowercased()
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: key.modifiers,
                                               timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                               context: nil, characters: key.characters, charactersIgnoringModifiers: plain,
                                               isARepeat: false, keyCode: key.keyCode) else { continue }
            if type == .keyDown { web.agentKey(down: event) } else { web.agentKey(up: event) }
        }
    }
}

/// The marks the owner sees while the agent drives the tab: the band on
/// top (`AgentBandView`, the same as computer use's, with an `esc` key cap)
/// and a dot where it clicks.
@MainActor
final class PreviewAgentMarks: NSView {
    private let band = AgentBandView(trailing: .key("esc"), inWindow: true)
    private let dot = NSView()

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        band.translatesAutoresizingMaskIntoConstraints = false
        addSubview(band)
        NSLayoutConstraint.activate([
            band.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            band.centerXAnchor.constraint(equalTo: centerXAnchor),
            band.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -24),
        ])
        dot.wantsLayer = true
        dot.layer?.backgroundColor = DesignTokens.Color.stateWorking.withAlphaComponent(0.55).cgColor
        dot.layer?.borderColor = NSColor.white.cgColor
        dot.layer?.borderWidth = 2
        dot.layer?.cornerRadius = 9
        dot.isHidden = true
        addSubview(dot)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("PreviewAgentMarks is created in code") }

    /// Clicks pass through to the page: the marks are only for the eyes.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var isFlipped: Bool { true }

    func show(_ text: String) {
        band.text = text
        isHidden = false
    }

    /// The agent's dot at a point of the web view (same coordinates).
    func point(at location: NSPoint) {
        dot.frame = NSRect(x: location.x - 9, y: location.y - 9, width: 18, height: 18)
        dot.isHidden = false
        dot.alphaValue = 1
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 1.2
            dot.animator().alphaValue = 0
        }
    }
}
