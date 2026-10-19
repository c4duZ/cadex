import AppKit
import CCadex
import Checks
@testable import Terminal

// Tests of the terminal feature. Run with `make macos-test` (see
// shared/checks/Checks.swift for why this is an executable).

let exitCode = await Checks.run([
    ("special keys go to the core's encoder", {
        expect(KeyEncoding.route(keyCode: 36, modifiers: [], optionAsMeta: false) == .core(key: UInt16(CADEX_KEY_ENTER), mods: 0))
        expect(KeyEncoding.route(keyCode: 126, modifiers: [], optionAsMeta: false) == .core(key: UInt16(CADEX_KEY_UP), mods: 0))
        expect(KeyEncoding.route(keyCode: 122, modifiers: [], optionAsMeta: false) == .core(key: UInt16(CADEX_KEY_F1), mods: 0))
        expect(KeyEncoding.route(keyCode: 111, modifiers: [], optionAsMeta: false) == .core(key: UInt16(CADEX_KEY_F12), mods: 0))
        let ctrlRight = KeyEncoding.route(keyCode: 124, modifiers: .control, optionAsMeta: false)
        expect(ctrlRight == .core(key: UInt16(CADEX_KEY_RIGHT), mods: UInt8(CADEX_MOD_CTRL)), "\(ctrlRight)")
    }),
    ("Option moves and deletes by word", {
        expect(KeyEncoding.route(keyCode: 123, modifiers: .option, optionAsMeta: false) == .macEditing("\u{1B}b"))
        expect(KeyEncoding.route(keyCode: 124, modifiers: .option, optionAsMeta: true) == .macEditing("\u{1B}f"))
        expect(KeyEncoding.route(keyCode: 51, modifiers: .option, optionAsMeta: false) == .macEditing("\u{1B}\u{7F}"))
    }),
    ("Command jumps and deletes to the ends of the line", {
        expect(KeyEncoding.route(keyCode: 123, modifiers: .command, optionAsMeta: false) == .macEditing("\u{01}"))
        expect(KeyEncoding.route(keyCode: 124, modifiers: .command, optionAsMeta: false) == .macEditing("\u{05}"))
        expect(KeyEncoding.route(keyCode: 51, modifiers: .command, optionAsMeta: false) == .macEditing("\u{15}"))
        // Other ⌘ shortcuts (⌘V, ⌘K) are not line editing.
        expect(KeyEncoding.route(keyCode: 9, modifiers: .command, optionAsMeta: false) == .text)
    }),
    ("control combinations go to the core as text with Ctrl", {
        expect(KeyEncoding.route(keyCode: 8, modifiers: .control, optionAsMeta: false) == .core(key: UInt16(CADEX_KEY_NONE), mods: UInt8(CADEX_MOD_CTRL)))
    }),
    ("left Option is Meta only when configured", {
        let leftOption = NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.option.rawValue | 0x20)
        let rightOption = NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.option.rawValue | 0x40)
        expect(KeyEncoding.route(keyCode: 11, modifiers: leftOption, optionAsMeta: false) == .text)
        expect(KeyEncoding.route(keyCode: 11, modifiers: leftOption, optionAsMeta: true) == .core(key: UInt16(CADEX_KEY_NONE), mods: UInt8(CADEX_MOD_ALT)))
        expect(KeyEncoding.route(keyCode: 11, modifiers: rightOption, optionAsMeta: true) == .text)
    }),
    ("text goes to the input system so accents compose", {
        expect(KeyEncoding.route(keyCode: 0, modifiers: [], optionAsMeta: false) == .text)
        expect(KeyEncoding.route(keyCode: 0, modifiers: .shift, optionAsMeta: false) == .text)
    }),
    ("position to cell with padding and Retina scale", {
        // 8 pt padding at scale 2 is 16 px; cells 16x32 px; a 400x300 pt view.
        let g = TerminalGeometry(viewSize: CGSize(width: 400, height: 300), scale: 2, padding: 8,
                                 cellWidth: 16, cellHeight: 32, cols: 48, rows: 17)
        // Top-left cell: AppKit's y grows upward, so the top is y = 300.
        let first = g.pointer(at: CGPoint(x: 9, y: 291))
        expect(first.col == 0 && first.row == 0, "\(first.col),\(first.row)")
        expect(first.x == 18 && first.y == 18, "\(first.x),\(first.y)")
        // Column 3 spans 16 + 3*16 = 64 px to 80 px (32..40 pt); row 2 spans
        // 16 + 2*32 = 80 px to 112 px (40..56 pt down).
        let inner = g.pointer(at: CGPoint(x: 34, y: 300 - 41))
        expect(inner.col == 3 && inner.row == 2, "\(inner.col),\(inner.row)")
        // Outside the grid clamps to the edge cells.
        let outside = g.pointer(at: CGPoint(x: -20, y: -50))
        expect(outside.col == 0 && outside.row == 16, "\(outside.col),\(outside.row)")
        expect(first.padding_left == 16 && first.view_height == 600 && first.cell_width == 16)
    }),
    ("trackpad and wheel deltas become whole rows", {
        var acc = ScrollAccumulator()
        // Trackpad: 10 pt rows; 4 pt per event moves nothing until it adds up.
        expect(acc.rows(deltaY: 4, precise: true, cellHeightPoints: 10) == 0)
        expect(acc.rows(deltaY: 4, precise: true, cellHeightPoints: 10) == 0)
        expect(acc.rows(deltaY: 4, precise: true, cellHeightPoints: 10) == -1)
        // Wheel: lines; negative delta goes down (toward the bottom).
        acc.reset()
        expect(acc.rows(deltaY: -3, precise: false, cellHeightPoints: 10) == 3)
    }),
    ("cell metrics are whole pixels and scale with the display", {
        let retina = TerminalFont(scale: 2).metrics
        let standard = TerminalFont(scale: 1).metrics
        expect(retina.width > 0 && retina.height > retina.width, "\(retina)")
        expect(retina.width >= standard.width * 2 - 1 && retina.width <= standard.width * 2 + 1, "\(retina) vs \(standard)")
        expect(retina.baseline < retina.height)
    }),
    ("GPU quad layout matches the shader", {
        expect(MemoryLayout<QuadInstance>.stride == QuadInstance.shaderStride, "stride \(MemoryLayout<QuadInstance>.stride)")
    }),
    ("a session runs a shell through the core", {
        let session = try TerminalSession(cols: 80, rows: 24, shell: "/bin/sh")
        defer { session.close() }
        session.write("echo swift-$((20+3))\n")

        var found = false
        for _ in 0..<250 where !found {
            try await Task.sleep(for: .milliseconds(20))
            if let frame = session.currentFrame(), let text = frame.pointee.text {
                let bytes = UnsafeBufferPointer(start: text, count: Int(frame.pointee.text_len))
                found = String(decoding: bytes, as: UTF8.self).contains("swift-23")
            }
        }
        expect(found, "shell output never reached the frame")
    }),
    ("select all and copy through the core; typing clears the selection", {
        let session = try TerminalSession(cols: 80, rows: 24, shell: "/bin/sh")
        defer { session.close() }
        expect(session.selectedText() == nil, "no selection copies nothing")
        session.write("echo copy-$((3+4))\n")

        var copied = ""
        for _ in 0..<250 where !copied.contains("copy-7") {
            try await Task.sleep(for: .milliseconds(20))
            session.selectAll()
            copied = session.selectedText() ?? ""
        }
        expect(copied.contains("copy-7"), copied)
        session.write(" ")
        expect(!session.hasSelection)
    }),
    ("arrow keys reach the shell through the core", {
        let session = try TerminalSession(cols: 80, rows: 24, shell: "/bin/sh")
        defer { session.close() }
        // od shows the bytes the shell got: ESC [ A is 033 [ A.
        session.write("stty raw -echo; head -c 3 | od -c; stty sane\n")
        try await Task.sleep(for: .milliseconds(200))
        session.key(UInt16(CADEX_KEY_UP), mods: 0)

        var found = false
        for _ in 0..<250 where !found {
            try await Task.sleep(for: .milliseconds(20))
            if let frame = session.currentFrame(), let text = frame.pointee.text {
                let bytes = UnsafeBufferPointer(start: text, count: Int(frame.pointee.text_len))
                found = String(decoding: bytes, as: UTF8.self).contains("033")
            }
        }
        expect(found, "the arrow key never reached the shell")
    }),
])
exit(exitCode)
