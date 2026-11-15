import Checks
import Foundation
import TextIndex

// Tests of the text index. Run with `make macos-test` (see
// shared/checks/Checks.swift for why this is an executable).

let exitCode = await Checks.run([
    ("records, texts and meta; a search finds every word as a prefix, accents ignored", {
        let index = try TextIndex(path: ":memory:")
        try index.setRecord("a", Data("{\"t\":1}".utf8))
        try index.addText("a", "Ação de deploy no servidor")
        try index.addText("a", "segunda parte")
        try index.setRecord("b", Data("{}".utf8))
        try index.addText("b", "deploy local")
        expect(try index.search("acao depl") == ["a"])
        expect(Set(try index.search("deploy")) == ["a", "b"])
        expect(try index.search("segunda serv") == [], "words in different pieces are not one match")
        expect(try index.search("   ") == [] && (try index.search("\"; DROP")).isEmpty, "odd input is only words")
        expect(try index.record("a") == Data("{\"t\":1}".utf8))
        try index.setRecord("a", Data("{\"t\":2}".utf8))
        expect(try index.records().count == 2 && (try index.record("a")) == Data("{\"t\":2}".utf8))
        try index.setMeta("offset:a", "120")
        expect(try index.meta("offset:a") == "120")
        try index.setMeta("offset:a", nil)
        expect(try index.meta("offset:a") == nil)
        try index.remove("a")
        expect(try index.search("acao") == [] && (try index.record("a")) == nil)
    }),
    ("a file keeps what it was given; a failed batch leaves nothing", {
        let path = NSTemporaryDirectory() + "cadex-index-\(UUID().uuidString)/i.sqlite"
        defer { try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent) }
        do {
            let index = try TextIndex(path: path)
            try index.batch { try index.setRecord("x", Data("1".utf8)); try index.addText("x", "kept") }
            try? index.batch {
                try index.setRecord("y", Data("2".utf8))
                throw TextIndexError.sql("stop")
            }
        }
        let again = try TextIndex(path: path)
        expect(try again.search("kept") == ["x"] && (try again.record("y")) == nil)
    }),
])
exit(exitCode)
