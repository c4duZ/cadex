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
    ("mouse events for programs are in pixels from the top-left", {
        let g = TerminalGeometry(viewSize: CGSize(width: 400, height: 300), scale: 2, padding: 8,
                                 cellWidth: 16, cellHeight: 32, cols: 48, rows: 17)
        let e = g.mouseEvent(at: CGPoint(x: 10, y: 290), action: CADEX_MOUSE_PRESS,
                             button: CADEX_MOUSE_BUTTON_LEFT, mods: 0)
        expect(e.x == 20 && e.y == 20, "\(e.x),\(e.y)")
        expect(e.view_width == 800 && e.view_height == 600 && e.padding == 16)
        expect(e.cell_width == 16 && e.cell_height == 32 && e.button == UInt8(CADEX_MOUSE_BUTTON_LEFT))
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
    ("⌘V order: files, then image, then text", {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("cadex-test-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        expect(PasteContent.read(from: pasteboard) == nil, "empty clipboard pastes nothing")

        pasteboard.clearContents()
        pasteboard.setString("só texto", forType: .string)
        expect(PasteContent.read(from: pasteboard) == .text("só texto"))

        // An image and text together (a browser copy): the image wins.
        let image = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8,
                                     samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        pasteboard.clearContents()
        pasteboard.setData(image.tiffRepresentation, forType: .tiff)
        pasteboard.setString("https://exemplo.com/foto.png", forType: .string)
        if case .image(let png) = PasteContent.read(from: pasteboard) {
            expect(png.starts(with: [0x89, 0x50, 0x4E, 0x47]), "not a PNG")
        } else {
            expect(false, "image did not win over text")
        }

        // Files copied in Finder come with their names as text: files win.
        let file = URL(fileURLWithPath: "/tmp/Meus Arquivos/a b.txt")
        pasteboard.clearContents()
        pasteboard.writeObjects([file as NSURL])
        expect(PasteContent.read(from: pasteboard) == .files([file]))
    }),
    ("pasted paths are escaped by the core", {
        expect(TerminalSession.quotePaths(["/tmp/a b.txt", "/tmp/c"]) == "'/tmp/a b.txt' /tmp/c")
        expect(TerminalSession.quotePaths(["/tmp/it's"]) == "'/tmp/it'\\''s'")
        expect(TerminalSession.quotePaths([]) == "")
    }),
    ("pasted images are saved as PNG and removed after a week", {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cadex-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let old = try PastedImageStore.save(Data([0x89, 0x50]), in: dir)
        let recent = try PastedImageStore.save(Data([0x89, 0x50]), in: dir)
        let eightDaysAgo = Date().addingTimeInterval(-8 * 24 * 60 * 60)
        try FileManager.default.setAttributes([.modificationDate: eightDaysAgo], ofItemAtPath: old.path)
        expect(old != recent && old.pathExtension == "png")

        PastedImageStore.removeOld(in: dir)
        expect(!FileManager.default.fileExists(atPath: old.path), "old image stayed")
        expect(FileManager.default.fileExists(atPath: recent.path), "recent image removed")
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
    ("several lines into a shell without bracketed paste are not safe", {
        let session = try TerminalSession(cols: 80, rows: 24, shell: "/bin/sh")
        defer { session.close() }
        expect(session.isPasteSafe("uma linha"))
        expect(!session.isPasteSafe("ls\nrm -rf x\n"))
    }),
    ("find counts matches and links resolve through the core", {
        let session = try TerminalSession(cols: 80, rows: 24, shell: "/bin/sh")
        defer { session.close() }
        session.write("clear; echo 'achar https://cadex.dev/docs'\n")
        var link: TerminalSession.Link?
        for _ in 0..<250 where link == nil {
            try await Task.sleep(for: .milliseconds(20))
            // The echo output is on the row after the command.
            for row in 0..<4 where link == nil {
                link = session.link(atCol: 10, row: row)
            }
        }
        expect(link?.target == "https://cadex.dev/docs", "\(String(describing: link))")
        expect(link?.kind == .url && link?.start.col == 6)

        session.searchStart("cadex.dev")
        var counts = session.searchCounts()
        // `clear` wiped the command line (and the history): only the output.
        expect(counts.total == 1, "\(counts)")
        session.searchSelect(forward: true)
        counts = session.searchCounts()
        expect(counts.current == 1, "\(counts)")
        session.searchStop()
        expect(session.searchCounts().total == 0)
    }),
    ("the title a program sets reaches the app", {
        let session = try TerminalSession(cols: 80, rows: 24, shell: "/bin/sh")
        defer { session.close() }
        var titled = false
        session.onTitle = { titled = true }
        session.write("printf '\\033]2;titulo-cadex\\007'\n")
        for _ in 0..<250 where !titled {
            try await Task.sleep(for: .milliseconds(20))
        }
        expect(titled, "on_title never came")
        expect(session.title() == "titulo-cadex", session.title())
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
