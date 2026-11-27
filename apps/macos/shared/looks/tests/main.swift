import AppKit
import Checks
@testable import UILooks

// Tests of the interface's zoom, density and font. Run with `make macos-test`
// (see shared/checks/Checks.swift for why this is an executable).

/// Counts the actions a framed popup sends.
@MainActor final class PopupProbe: NSObject {
    var fired = 0
    @objc func fire() { fired += 1 }
}

let exitCode = await Checks.run([
    ("under glass the quiet texts rise toward the primary, so they read over a light wallpaper", {
        // The owner, 2026-11-27: New Project…, the sidebar's foot and the status bar's left vanished
        // in full screen over a light wallpaper.
        defer { DesignTokens.applyTheme(chrome: nil, text: nil, glass: false) }
        func brightness(_ c: NSColor) -> CGFloat { (c.usingColorSpace(.sRGB) ?? c).brightnessComponent }
        DesignTokens.applyTheme(chrome: nil, text: nil, glass: false)
        let solid = (brightness(DesignTokens.Color.textMuted), brightness(DesignTokens.Color.textTertiary))
        DesignTokens.applyTheme(chrome: nil, text: nil, glass: true)
        let glass = (brightness(DesignTokens.Color.textMuted), brightness(DesignTokens.Color.textTertiary))
        expect(glass.0 > solid.0 + 0.1 && glass.1 > solid.1 + 0.1, "muted \(solid.0)→\(glass.0), tertiary \(solid.1)→\(glass.1)")
        expect(glass.1 < brightness(DesignTokens.Color.textPrimary), "still below the primary")
    }),
    ("the window opacity slider is the glass's strength: its floor is the strong glass as it was, its top a solid window", {
        // The owner, 2026-11-27: "os 10% do vidro forte sejam os 10% aqui"; the strong glass held
        // 0.62 at every slider position before.
        defer { Glass.set(opacity: nil) }
        var tints: [CGFloat] = []
        for opacity in [0.1, 0.5, 0.999] as [CGFloat] {
            Glass.set(opacity: opacity, strong: true)
            tints.append(Glass.tint ?? 0)
        }
        expect(abs(tints[0] - 0.62) < 0.001, "10% is the old strong glass: \(tints[0])")
        expect(tints[0] < tints[1] && tints[1] < tints[2], "each position its own glass: \(tints)")
        expect(tints[2] > 0.99, "the top nearly solid: \(tints[2])")
    }),
    ("under the strong glass a borderless rounded panel keeps its frost cut to its corners, and only a titled window takes the square window blur", {
        // The owner's screenshot, 2026-11-27: a blurred square around ⌘K's rounded corners.
        Glass.set(opacity: 0.3, strong: true)
        defer { Glass.set(opacity: nil) }
        let titled = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled], backing: .buffered, defer: true)
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.borderless], backing: .buffered, defer: true)
        titled.isReleasedWhenClosed = false
        panel.isReleasedWhenClosed = false
        expect(Glass.blursWindow(titled) && !Glass.blursWindow(panel), "the window blur only in a titled window")
        let box = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        box.wantsLayer = true
        box.layer?.cornerRadius = 14
        panel.contentView = box
        Glass.dress(box, .black)
        guard let pane = box.subviews.first(where: { $0 is GlassPane }) as? GlassPane else { return expect(false, "no glass") }
        expect(!pane.frost.isHidden, "the panel keeps its frost under the strong glass")
        expect(pane.frost.maskImage != nil, "cut to the box's corners")
        Glass.set(opacity: 0.3, strong: false)
        expect(!Glass.blursWindow(titled), "no window blur without the strong glass")
    }),
    ("a popup framed after its target and action were set still sends its action", {
        // The cell holds them; the frame's cell dropped them and every popup in Settings and the
        // project's memory place did nothing (the owner, 2026-11-27).
        let probe = PopupProbe()
        let popup = NSPopUpButton()
        popup.addItems(withTitles: ["a", "b"])
        popup.selectItem(at: 1)
        popup.target = probe
        popup.action = #selector(PopupProbe.fire)
        _ = FrameField.popup(popup)
        expect(popup.target === probe && popup.action == #selector(PopupProbe.fire), "target and action kept")
        expect(popup.indexOfSelectedItem == 1, "the selection kept")
        popup.sendAction(popup.action, to: popup.target)
        expect(probe.fired == 1, "the action reaches its target")
    }),
    ("by default every design size comes back unchanged", {
        UILooks.configure(zoom: 1, compact: false, fontFamily: "", fontSize: 13)
        expect(UILooks.font(13).pointSize == 13 && UILooks.pt(38) == 38 && UILooks.rowHeight(22) == 22)
        expect(UILooks.font(12, weight: .medium) == NSFont.systemFont(ofSize: 12, weight: .medium))
    }),
    ("zoom 1.25 scales fonts and sizes", {
        UILooks.configure(zoom: 1.25, compact: false, fontFamily: "", fontSize: 13)
        expect(UILooks.font(13).pointSize == 16.25, "\(UILooks.font(13).pointSize)")
        expect(UILooks.pt(38) == 47.5)
        expect(UILooks.monospaced(11).pointSize == 13.75)
    }),
    ("compact tightens heights only", {
        UILooks.configure(zoom: 1, compact: true, fontFamily: "", fontSize: 13)
        expect(UILooks.rowHeight(20) == 17 && UILooks.pt(20) == 20)
    }),
    ("the base font size scales the design sizes", {
        UILooks.configure(zoom: 1, compact: false, fontFamily: "", fontSize: 19.5)
        expect(UILooks.font(12).pointSize == 18)
    }),
    ("a chosen family keeps the weight; a missing one is the system font", {
        UILooks.configure(zoom: 1, compact: false, fontFamily: "Helvetica Neue", fontSize: 13)
        let bold = UILooks.font(13, weight: .bold)
        expect(bold.familyName == "Helvetica Neue" && bold.fontDescriptor.symbolicTraits.contains(.bold))
        UILooks.configure(zoom: 1, compact: false, fontFamily: "No Such Font", fontSize: 13)
        expect(UILooks.font(13) == NSFont.systemFont(ofSize: 13))
    }),
    ("the frame follows a theme: Cadex Night keeps the mockups' colors; another theme's repaints a built view", {
        let night = DesignTokens.Color.bgSidebar
        expect(ColorKey(night) == ColorKey(DesignTokens.rgb(0x131417)), "Cadex Night: the mockup's value")
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
        view.wantsLayer = true
        view.layer?.backgroundColor = DesignTokens.Color.bgSidebar.cgColor
        let label = NSTextField(labelWithString: "x")
        label.textColor = DesignTokens.Color.textMuted
        view.addSubview(label)
        let before = DesignTokens.themedColors()
        // A light theme: white frame, near-black text.
        expect(DesignTokens.applyTheme(chrome: DesignTokens.rgb(0xFFFFFF), text: DesignTokens.rgb(0x1F2328)))
        DesignTokens.repaint(view, from: before)
        let sidebar = DesignTokens.Color.bgSidebar
        expect(ColorKey(sidebar) != ColorKey(night) && sidebar.usingColorSpace(.sRGB)!.redComponent > 0.9, "a light sidebar: \(sidebar)")
        expect(view.layer?.backgroundColor.map { ColorKey($0) } == ColorKey(sidebar.cgColor), "the built layer repainted")
        expect(ColorKey(label.textColor!) == ColorKey(DesignTokens.Color.textMuted), "the built label repainted")
        expect(ColorKey(DesignTokens.Color.stateNeeds) == ColorKey(DesignTokens.rgb(0xF2A93B)), "a state keeps its color in every theme")
        expect(!DesignTokens.applyTheme(chrome: DesignTokens.rgb(0xFFFFFF), text: DesignTokens.rgb(0x1F2328)), "the same theme changes nothing")
        DesignTokens.applyTheme(chrome: nil, text: nil)
        expect(ColorKey(DesignTokens.Color.bgSidebar) == ColorKey(night), "back to Cadex Night")
    }),
    ("a label repainted once: its new color is not taken for another token's old one", {
        let label = NSTextField(labelWithString: "Uncommitted")
        label.textColor = DesignTokens.Color.textPrimary
        let before = DesignTokens.themedColors()
        // Cadex Day: its text #1D1F23 is Cadex Night's bg.chip.
        DesignTokens.applyTheme(chrome: DesignTokens.rgb(0xF9F9FA), text: DesignTokens.rgb(0x1D1F23))
        DesignTokens.repaint(label, from: before)
        expect(ColorKey(label.textColor!) == ColorKey(DesignTokens.Color.textPrimary), "\(label.textColor!)")
        DesignTokens.applyTheme(chrome: nil, text: nil)
    }),
    ("a plain label repainted still follows the color set after (the Work | Files switch, 2026-11-20)", {
        let label = NSTextField(labelWithString: "Work")
        label.textColor = DesignTokens.Color.textPrimary
        let before = DesignTokens.themedColors()
        DesignTokens.applyTheme(chrome: DesignTokens.rgb(0x101214), text: DesignTokens.rgb(0xE0E0E0))
        DesignTokens.repaint(label, from: before)
        label.textColor = DesignTokens.Color.textMuted
        var drawn: NSColor?
        label.attributedStringValue.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: 4)) { value, _, _ in drawn = value as? NSColor }
        expect(drawn.map { ColorKey($0) } == ColorKey(DesignTokens.Color.textMuted), "the word draws the new color: \(String(describing: drawn))")
        DesignTokens.applyTheme(chrome: nil, text: nil)
    }),
    ("a translucent window: the grounds turn to glass, cards and text in a ground's color stay solid", {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
        view.wantsLayer = true
        view.layer?.backgroundColor = DesignTokens.Color.bgChrome.cgColor
        let card = NSView(), label = NSTextField(labelWithString: "Open PR")
        card.wantsLayer = true
        card.layer?.backgroundColor = DesignTokens.Color.bgCard.cgColor
        label.textColor = DesignTokens.Color.bgPaneIdle
        view.addSubview(card); view.addSubview(label)
        var before = DesignTokens.themedColors()
        expect(DesignTokens.applyTheme(chrome: nil, text: nil, glass: true))
        DesignTokens.repaint(view, from: before)
        expect(DesignTokens.Color.bgChrome.alphaComponent < 0.05 && DesignTokens.Color.bgCard.alphaComponent == 1)
        expect(view.layer!.backgroundColor!.alpha < 0.05 && card.layer!.backgroundColor!.alpha == 1, "the ground is glass, the card solid")
        expect(label.textColor!.alphaComponent == 1, "the text stays solid")
        before = DesignTokens.themedColors()
        DesignTokens.applyTheme(chrome: nil, text: nil)
        DesignTokens.repaint(view, from: before)
        expect(ColorKey(view.layer!.backgroundColor!) == ColorKey(DesignTokens.Color.bgChrome.cgColor), "solid again")
    }),
    ("out-of-range values are clamped", {
        UILooks.configure(zoom: 9, compact: false, fontFamily: "", fontSize: 1)
        expect(UILooks.zoom == 1.5 && UILooks.fontSize == 9)
        UILooks.configure(zoom: 1, compact: false, fontFamily: "", fontSize: 13)
    }),
])
exit(exitCode)
