import AppKit
import Checks
@testable import UILooks

// Tests of the interface's zoom, density and font. Run with `make macos-test`
// (see shared/checks/Checks.swift for why this is an executable).

let exitCode = await Checks.run([
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
