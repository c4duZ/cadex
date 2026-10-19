import AppKit
import Checks
@testable import Editor
@testable import Explorer
@testable import Markdown

// Tests of the markdown feature. Run with `make macos-test` (see
// shared/checks/Checks.swift for why this is an executable).

@MainActor
func sandbox(_ files: [String: String]) -> String {
    let path = NSTemporaryDirectory() + "cadex-markdown-\(UUID().uuidString)"
    for (name, text) in files {
        let full = path + "/" + name
        try? FileManager.default.createDirectory(atPath: (full as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: full, contents: Data(text.utf8))
    }
    let folder = WorkspaceFolder(arguments: ["Cadex"], cwd: "/")
    folder.open(path)
    return folder.root
}

@MainActor
func eventually(_ body: () -> Bool) async -> Bool {
    for _ in 0..<100 {
        if body() { return true }
        try? await Task.sleep(nanoseconds: 50_000_000)
    }
    return false
}

let exitCode = await Checks.run([
    ("what to complete: path, heading, note", {
        let text = "Veja [a](docs/sp" as NSString
        expect(CompletionTrigger.detect(in: text, cursor: text.length) == .path(query: "docs/sp", range: NSRange(location: 9, length: 7)))
        let heading = "[a](spec.md#crit" as NSString
        expect(CompletionTrigger.detect(in: heading, cursor: heading.length) == .heading(file: "spec.md", query: "crit", range: NSRange(location: 12, length: 4)))
        let note = "ver [[Ide" as NSString
        expect(CompletionTrigger.detect(in: note, cursor: note.length) == .note(query: "Ide", range: NSRange(location: 6, length: 3)))
        let done = "[a](b.md) e mais" as NSString
        expect(CompletionTrigger.detect(in: done, cursor: done.length) == nil)
    }),
    ("paths relative to the note", {
        expect(CompletionTrigger.relativePath(to: "docs/spec/search.md", from: "docs/plans/4.md") == "../spec/search.md")
        expect(CompletionTrigger.relativePath(to: "README.md", from: "docs/a.md") == "../README.md")
        expect(CompletionTrigger.relativePath(to: "docs/b.md", from: "docs/a.md") == "b.md")
        expect(MarkdownController.normalize("docs/./plans/../spec/a.md") == "docs/spec/a.md")
    }),
    ("the rendered page has no script and a strict policy", {
        let page = MarkdownPreview.page(body: MarkdownIndex.render("# Oi\n\n<script>alert(1)</script>\n"), look: EditorAppearance.current)
        expect(!page.contains("<script"), page)
        expect(page.contains("default-src 'none'"))
        expect(page.contains("<h1 id=\"oi\">Oi</h1>"))
    }),
    ("a note's broken links, completion of notes and backlinks", {
        let root = sandbox([
            "README.md": "# Cadex\n\n[spec](docs/spec.md#plano) e [[Ideias]]\n",
            "docs/spec.md": "# Spec\n\n## Plano\n",
            "docs/Ideias.md": "# Ideias\n\n[volta](../README.md)\n",
        ])
        let markdown = MarkdownController(root: root, findFiles: { _ in [] }, open: { _, _ in })
        let ready = await eventually { markdown.index.notes().count == 3 }
        expect(ready)
        let links = markdown.index.links(in: "[ok](docs/spec.md#plano) [x](falta.md)", of: root + "/README.md")
        expect(links.count == 2 && !links[0].broken && links[1].broken, "\(links)")
        expect(links[0].line == 3, "\(links)")
        let notes = markdown.suggestions(for: .note(query: "ide", range: NSRange()), from: "README.md")
        expect(notes.map(\.insert) == ["Ideias]]"], "\(notes)")
        let headings = markdown.suggestions(for: .heading(file: "docs/spec.md", query: "", range: NSRange()), from: "README.md")
        expect(headings.map(\.insert) == ["spec", "plano"], "\(headings)")
        let back = markdown.index.backlinks(to: root + "/README.md")
        expect(back.count == 1 && back[0].path.hasSuffix("docs/Ideias.md"), "\(back)")
        try? FileManager.default.removeItem(atPath: root)
    }),
    ("an open note gets its broken links and follows them", {
        let root = sandbox(["a.md": "[ok](b.md) e [x](falta.md)\n", "b.md": "# B\n"])
        var opened: [String] = []
        let markdown = MarkdownController(root: root, findFiles: { _ in [] }, open: { path, _ in opened.append(path) })
        let doc = EditorDocument(path: root + "/a.md")
        markdown.attach(doc)
        let ready = await eventually { markdown.index.isReady }
        expect(ready)
        try? await Task.sleep(nanoseconds: 500_000_000)
        let session = markdown.session(for: doc)
        expect(session?.links.map(\.broken) == [false, true], "\(session?.links ?? [])")
        let storage = doc.textView!.textStorage!
        let broken = (doc.textView!.string as NSString).range(of: "[x](falta.md)")
        expect(storage.attribute(.underlineStyle, at: broken.location, effectiveRange: nil) != nil, "no underline")
        expect(storage.attribute(.underlineStyle, at: 1, effectiveRange: nil) == nil)
        expect(session?.follow(at: 2) == true)
        expect(opened == [root + "/b.md"], "\(opened)")
        try? FileManager.default.removeItem(atPath: root)
    }),
    ("back to the text, the rendered page is freed; rendering again makes a new one", {
        let root = sandbox(["a.md": "# A\n\ntexto\n"])
        let markdown = MarkdownController(root: root, findFiles: { _ in [] }, open: { _, _ in })
        let doc = EditorDocument(path: root + "/a.md")
        weak var first: NSView?
        autoreleasepool {
            markdown.togglePreview(doc)
            first = doc.alternate
        }
        expect(first is RenderedNoteView, "\(String(describing: first))")
        autoreleasepool { markdown.togglePreview(doc) }
        expect(doc.alternate == nil)
        let freed = await eventually { first == nil }
        expect(freed, "a página continuou na memória")
        markdown.togglePreview(doc)
        expect(doc.alternate is RenderedNoteView)
        try? FileManager.default.removeItem(atPath: root)
    }),
])
exit(exitCode)
