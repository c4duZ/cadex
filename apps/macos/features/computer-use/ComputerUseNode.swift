import ApplicationServices
import CoreGraphics
import Foundation

/// One element of another app's window, as the accessibility API gives it
/// (docs/adr/0026-computer-use.md). A protocol so the tree's rules are
/// tested without the system's permission; `AXNode` is the real one.
@MainActor
protocol ComputerUseNode: AnyObject {
    var role: String { get }
    var title: String { get }
    var value: String? { get }
    var isEnabled: Bool { get }
    var isFocused: Bool { get }
    /// In screen points, top-left origin; nil when the app does not say.
    var frame: CGRect? { get }
    var actions: [String] { get }
    var children: [any ComputerUseNode] { get }
    /// A password field: its value is never read nor written.
    var isSecure: Bool { get }
    func perform(_ action: String) -> Bool
    func setValue(_ text: String) -> Bool
    func focus() -> Bool
}

/// The real element, over AXUIElement.
@MainActor
final class AXNode: ComputerUseNode {
    let element: AXUIElement
    init(_ element: AXUIElement) { self.element = element }

    private func attribute(_ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    var role: String { attribute(kAXRoleAttribute) as? String ?? "" }
    var subrole: String { attribute(kAXSubroleAttribute) as? String ?? "" }
    var title: String {
        for name in [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute, kAXPlaceholderValueAttribute] {
            if let text = attribute(name) as? String, !text.isEmpty { return text }
        }
        return ""
    }
    var value: String? {
        guard let raw = attribute(kAXValueAttribute) else { return nil }
        if let text = raw as? String { return text }
        if let number = raw as? NSNumber { return number.stringValue }
        return nil
    }
    var isEnabled: Bool { (attribute(kAXEnabledAttribute) as? Bool) ?? true }
    var isFocused: Bool { (attribute(kAXFocusedAttribute) as? Bool) ?? false }
    var frame: CGRect? {
        guard let p = attribute(kAXPositionAttribute), let s = attribute(kAXSizeAttribute) else { return nil }
        var point = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &point), AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }
    var actions: [String] {
        var names: CFArray?
        return AXUIElementCopyActionNames(element, &names) == .success ? (names as? [String] ?? []) : []
    }
    var children: [any ComputerUseNode] {
        (attribute(kAXChildrenAttribute) as? [AXUIElement] ?? []).map(AXNode.init)
    }
    var isSecure: Bool { subrole == (kAXSecureTextFieldSubrole as String) }

    func perform(_ action: String) -> Bool { AXUIElementPerformAction(element, action as CFString) == .success }
    func setValue(_ text: String) -> Bool {
        AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, text as CFString) == .success
    }
    func focus() -> Bool {
        AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success
    }

    /// The app's front window (focused, else the first), or nil.
    static func frontWindow(pid: pid_t) -> AXNode? {
        let app = AXNode(AXUIElementCreateApplication(pid))
        if let focused = app.attribute(kAXFocusedWindowAttribute) { return AXNode(focused as! AXUIElement) }
        return (app.attribute(kAXWindowsAttribute) as? [AXUIElement])?.first.map(AXNode.init)
    }
}
