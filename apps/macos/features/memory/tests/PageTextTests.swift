import Checks
import Foundation
@testable import Memory

// A memory page read for showing it rendered (plan 34 D and E): the body after the frontmatter as
// headings, paragraphs and items, and the tags in both forms.

func pageTextTests() -> [(name: String, body: Checks.Body)] { [
    ("a page's body: no frontmatter, no title heading, headings, joined paragraphs, items, marks as plain text", {
        let text = "---\ntitle: X\ntags:\n- ai-memory\n- cadex\n---\n# X\n\n## Contexto\n\nO usuário pediu\numa passada pelo `AI Memory`.\n\n- Apagadas **6** páginas\n- [handoff](a.md) escrito\n"
        let blocks = MemoryPageText.blocks(text)
        expect(blocks == [.heading("Contexto"), .paragraph("O usuário pediu uma passada pelo AI Memory."),
                          .item("Apagadas 6 páginas"), .item("handoff escrito")], "\(blocks)")
        expect(MemoryPageText.tags(text) == ["ai-memory", "cadex"])
    }),
    ("tags inline, and none without a frontmatter", {
        expect(MemoryPageText.tags("---\ntags: [a, \"b c\"]\n---\nbody") == ["a", "b c"])
        expect(MemoryPageText.tags("no frontmatter\ntags: [a]").isEmpty)
        expect(MemoryPageText.blocks("plain line") == [.paragraph("plain line")])
    }),
] }
