import AppKit
import Checks
@testable import StateGlyph
import UILooks

// Tests of the state glyph. Run with `make macos-test` (see shared/checks/Checks.swift for why
// this is an executable).

/// Every glyph of the tokens' sizes, in a row per state: the snapshot to put beside Anatomy.
@MainActor
func glyphSheet() -> NSView {
    let sizes = DesignTokens.StateGlyph.sizes
    let cell: CGFloat = 40
    let sheet = NSView(frame: NSRect(x: 0, y: 0, width: cell * CGFloat(sizes.count), height: cell * CGFloat(GlyphState.allCases.count)))
    sheet.wantsLayer = true
    sheet.layer?.backgroundColor = DesignTokens.Color.bgSidebar.cgColor
    for (row, state) in GlyphState.allCases.enumerated() {
        for (column, size) in sizes.enumerated() {
            let glyph = StateGlyphView(size: size, state: state)
            let side = glyph.intrinsicContentSize.width
            glyph.frame = NSRect(x: CGFloat(column) * cell + (cell - side) / 2,
                                 y: sheet.bounds.height - CGFloat(row + 1) * cell + (cell - side) / 2, width: side, height: side)
            sheet.addSubview(glyph)
        }
    }
    return sheet
}

let exitCode = await Checks.run([
    ("each state has the color of its token", {
        await MainActor.run {
            let expected: [GlyphState: NSColor] = [
                .working: DesignTokens.Color.stateWorking, .needs: DesignTokens.Color.stateNeeds,
                .done: DesignTokens.Color.stateDone, .failed: DesignTokens.Color.stateFailed,
                .idle: DesignTokens.Color.stateIdle, .review: DesignTokens.Color.stateReview,
            ]
            for state in GlyphState.allCases {
                expect(StateGlyphLook.color(state) == expected[state], state.rawValue)
            }
            expect(GlyphState.allCases.count == 6)
        }
    }),
    ("the ring is thinner at 7, 2 pt at 9 and 10, 2.5 at 14; idle keeps its thin outline", {
        await MainActor.run {
            expect(StateGlyphLook.stroke(.working, size: 7) == DesignTokens.Stroke.glyphSmall)
            expect(StateGlyphLook.stroke(.working, size: 9) == DesignTokens.Stroke.glyph)
            expect(StateGlyphLook.stroke(.working, size: 10) == DesignTokens.Stroke.glyph)
            expect(StateGlyphLook.stroke(.working, size: 14) == DesignTokens.Stroke.glyphLarge)
            expect(StateGlyphLook.stroke(.idle, size: 10) == DesignTokens.Stroke.glyphSmall)
        }
    }),
    ("the halo of needs-you is 3 pt, 4 at 14, and the view keeps room for it", {
        await MainActor.run {
            UILooks.configure(zoom: 1, compact: false, fontFamily: "", fontSize: 13)
            expect(StateGlyphLook.halo(size: 10) == 3 && StateGlyphLook.halo(size: 14) == 4)
            expect(StateGlyphView(size: 10).intrinsicContentSize.width == 16)
        }
    }),
    ("the ring does not spin out of a window, nor when the state is not working", {
        await MainActor.run {
            let glyph = StateGlyphView(size: 10, state: .working)
            expect(!glyph.spins, "not in a window")
            glyph.state = .done
            expect(!glyph.spins)
        }
    }),
    ("the glyph sheet draws (CADEX_SNAPSHOT_DIR: state-glyphs.png)", {
        await MainActor.run {
            let sheet = glyphSheet()
            expect(sheet.subviews.count == 24)
            snapshot(sheet, "state-glyphs")
        }
    }),
])

/// With CADEX_SNAPSHOT_DIR set, saves a picture of `view` there, to see the glyphs beside the
/// mockup without capturing the screen.
@MainActor func snapshot(_ view: NSView, _ name: String) {
    guard let dir = ProcessInfo.processInfo.environment["CADEX_SNAPSHOT_DIR"] else { return }
    let window = NSWindow(contentRect: view.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: .darkAqua)
    window.contentView = view
    view.layoutSubtreeIfNeeded()
    guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
    view.cacheDisplay(in: view.bounds, to: bitmap)
    try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
}
exit(exitCode)
