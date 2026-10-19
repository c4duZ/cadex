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
