import AppKit
import Checks
@testable import Editor
@testable import Explorer

// Tests of the editor feature. Run with `make macos-test` (see
// shared/checks/Checks.swift for why this is an executable).

@MainActor
func sandbox(_ files: [String: String]) -> String {
    let path = NSTemporaryDirectory() + "cadex-editor-\(UUID().uuidString)"
    try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    for (name, text) in files { FileManager.default.createFile(atPath: path + "/" + name, contents: Data(text.utf8)) }
    let folder = WorkspaceFolder(arguments: ["Cadex"], cwd: "/")
    folder.open(path)
    return folder.root
}

let exitCode = await Checks.run([
    ("a wrapped Markdown note keeps its height while scrolling and typing (issue #2)", {
        var text = ""
        for n in 0..<150 {
            text += "## Seção \(n)\n\n" + String(repeating: "Um parágrafo longo de nota que quebra em várias linhas. ", count: 8 + n % 5) + "\n\n"
        }
        let root = sandbox(["nota.md": text])
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
        let doc = EditorDocument(path: root + "/nota.md")
        doc.view.frame = window.contentView!.bounds
        window.contentView!.addSubview(doc.view)
        doc.view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        guard let tv = doc.textView, let scroll = tv.enclosingScrollView else { return expect(false, "no text view") }
        var heights = Set<Int>()
        for step in 0...8 {
            scroll.contentView.scroll(to: NSPoint(x: 0, y: tv.frame.height * CGFloat(step) / 10))
            scroll.reflectScrolledClipView(scroll.contentView)
            tv.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
            heights.insert(Int(tv.frame.height))
        }
        expect(heights.count == 1, "the height changed while scrolling: \(heights.sorted())")
        let mid = (tv.string as NSString).length / 2
        tv.setSelectedRange(NSRange(location: mid, length: 0))
        tv.scrollRangeToVisible(NSRange(location: mid, length: 0))
        let top = scroll.contentView.bounds.origin.y
        for _ in 0..<5 { tv.insertText("x", replacementRange: tv.selectedRange()) }
        try await Task.sleep(for: .milliseconds(50))
        expect(scroll.contentView.bounds.origin.y == top, "the view moved while typing")
    }),
    ("line index: lines, ranges and whole lines", {
        let index = LineIndex("ab\ncd\n\nef" as NSString)
        expect(index.count == 4)
        expect(index.line(at: 0) == 0 && index.line(at: 3) == 1 && index.line(at: 6) == 2 && index.line(at: 9) == 3)
        expect(index.range(lines: 1, through: 2) == NSRange(location: 3, length: 4))
        expect(index.wholeLines(NSRange(location: 4, length: 1)) == NSRange(location: 3, length: 3))
    }),
    ("indent unit from the file", {
        expect(CodeTextView.detectIndent("a\n\tb\n\tc\n") == "\t")
        expect(CodeTextView.detectIndent("a\n  b\n    c\n  d\n") == "  ")
        expect(CodeTextView.detectIndent("a\n    b\n        c\n") == "    ")
    }),
    ("opens a Zig file with colors and folds, saves, and follows the disk", {
        EditorAppearance.current.tokens = EditorAppearance.tokens(ansi: (0..<16).map { UInt32($0) * 0x0F0F0F }, foreground: 0xFFFFFF)
        let root = sandbox(["a.zig": "fn a() void {\n    return;\n}\n"])
        let doc = EditorDocument(path: root + "/a.zig")
        expect(doc.language == "Zig")
        expect(doc.folding.isFoldStart(0))
        let storage = doc.codeView!.textStorage!
        let color = storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        expect(color != nil && color != EditorAppearance.current.foreground, "fn should be colored")
        doc.codeView!.insertText("// x\n", replacementRange: NSRange(location: 0, length: 0))
        expect(doc.hasUnsavedChanges)
        expect(doc.save())
        expect(!doc.hasUnsavedChanges)
        let saved = try String(contentsOfFile: root + "/a.zig", encoding: .utf8)
        expect(saved.hasPrefix("// x\nfn a()"), saved)
        try "const b = 1;\n".write(toFile: root + "/a.zig", atomically: true, encoding: .utf8)
        doc.diskMayHaveChanged()
        expect(doc.codeView!.string == "const b = 1;\n", doc.codeView!.string)
        try? FileManager.default.removeItem(atPath: root)
    }),
    ("binary files show a message instead of the text", {
        let root = sandbox([:])
        FileManager.default.createFile(atPath: root + "/x.bin", contents: Data([0x50, 0x00, 0x01]))
        let doc = EditorDocument(path: root + "/x.bin")
        expect(doc.codeView == nil)
        try? FileManager.default.removeItem(atPath: root)
    }),
])
exit(exitCode)
