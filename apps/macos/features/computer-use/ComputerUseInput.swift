import AppKit
import CoreGraphics

/// The agent's mouse and keyboard in another app, for when an element has
/// no accessibility action (docs/adr/0026-computer-use.md): system events at
/// the element's point, the app in front first.
@MainActor
enum ComputerUseInput {
    /// A click at a point of the screen (top-left origin, as accessibility gives).
    static func click(at point: CGPoint) {
        let source = CGEventSource(stateID: .hidSystemState)
        for (type, button) in [(CGEventType.mouseMoved, CGMouseButton.left), (.leftMouseDown, .left), (.leftMouseUp, .left)] {
            CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: button)?.post(tap: .cghidEventTap)
        }
    }

    /// Text typed as keys, a character at a time (the element has the focus).
    static func type(_ text: String) {
        let source = CGEventSource(stateID: .hidSystemState)
        for character in text {
            let units = Array(String(character).utf16)
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else { continue }
                event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
                event.post(tap: .cghidEventTap)
            }
        }
    }

    /// The wheel over a point: "up" or "down" a few lines.
    static func scroll(at point: CGPoint, down: Bool) {
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
        CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: down ? -5 : 5, wheel2: 0, wheel3: 0)?.post(tap: .cghidEventTap)
    }
}
