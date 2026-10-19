import AppKit
import Checks
@testable import Terminal

// Tests of the terminal feature. Run with `make macos-test` (see
// shared/checks/Checks.swift for why this is an executable).

let exitCode = await Checks.run([
    ("special keys send their sequences", {
        expect(KeyEncoding.sequence(keyCode: 36, modifiers: [], characters: "\r") == "\r")
        expect(KeyEncoding.sequence(keyCode: 126, modifiers: [], characters: nil) == "\u{1B}[A")
        expect(KeyEncoding.sequence(keyCode: 51, modifiers: [], characters: nil) == "\u{7F}")
    }),
    ("Option moves and deletes by word", {
        expect(KeyEncoding.sequence(keyCode: 123, modifiers: .option, characters: nil) == "\u{1B}b")
        expect(KeyEncoding.sequence(keyCode: 124, modifiers: .option, characters: nil) == "\u{1B}f")
        expect(KeyEncoding.sequence(keyCode: 51, modifiers: .option, characters: nil) == "\u{1B}\u{7F}")
    }),
    ("Command jumps and deletes to the ends of the line", {
        expect(KeyEncoding.sequence(keyCode: 123, modifiers: .command, characters: nil) == "\u{01}")
        expect(KeyEncoding.sequence(keyCode: 124, modifiers: .command, characters: nil) == "\u{05}")
        expect(KeyEncoding.sequence(keyCode: 51, modifiers: .command, characters: nil) == "\u{15}")
        // Other ⌘ shortcuts (⌘V, ⌘K) are not line editing.
        expect(KeyEncoding.sequence(keyCode: 9, modifiers: .command, characters: "v") == nil)
    }),
    ("control combinations pass through", {
        expect(KeyEncoding.sequence(keyCode: 8, modifiers: .control, characters: "\u{03}") == "\u{03}")
    }),
    ("text goes to the input system so accents compose", {
        expect(KeyEncoding.sequence(keyCode: 0, modifiers: [], characters: "a") == nil)
        expect(KeyEncoding.sequence(keyCode: 0, modifiers: .option, characters: "å") == nil)
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
])
exit(exitCode)
