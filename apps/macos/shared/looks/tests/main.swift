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
    ("out-of-range values are clamped", {
        UILooks.configure(zoom: 9, compact: false, fontFamily: "", fontSize: 1)
        expect(UILooks.zoom == 1.5 && UILooks.fontSize == 9)
        UILooks.configure(zoom: 1, compact: false, fontFamily: "", fontSize: 13)
    }),
])
exit(exitCode)
