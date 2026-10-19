import Checks
import Foundation
@testable import StatusBar

// Tests of the status-bar feature. Run with `make macos-test` (see
// shared/checks/Checks.swift for why this is an executable).

let exitCode = await Checks.run([
    ("a folder under home starts at Home", {
        let titles = Breadcrumb.segments(of: "/Users/cadu/Trabalho/cadex", home: "/Users/cadu").map(\.title)
        expect(titles == ["Home", "Trabalho", "cadex"], "\(titles)")
        let paths = Breadcrumb.segments(of: "/Users/cadu/Trabalho", home: "/Users/cadu").map(\.path)
        expect(paths == ["/Users/cadu", "/Users/cadu/Trabalho"], "\(paths)")
    }),
    ("a folder elsewhere starts at /", {
        let segments = Breadcrumb.segments(of: "/private/tmp", home: "/Users/cadu")
        expect(segments.map(\.title) == ["/", "private", "tmp"])
        expect(segments.last?.path == "/private/tmp")
        expect(Breadcrumb.segments(of: "/Users/cadu", home: "/Users/cadu").map(\.title) == ["Home"])
    }),
    ("long paths keep the root and the current folder", {
        let segments = Breadcrumb.segments(of: "/a/b/c/d/e/f/g/h", home: "/Users/cadu", maxSegments: 5)
        expect(segments.map(\.title) == ["/", "…", "f", "g", "h"], "\(segments.map(\.title))")
        expect(segments[1].path == nil)
    }),
    ("subfolders are listed by name, hidden ones left out", {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cadex-bc-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["b", "a", ".oculta"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        try Data().write(to: root.appendingPathComponent("arquivo.txt"))
        expect(Breadcrumb.subfolders(of: root.path) == ["a", "b"])
        expect(Breadcrumb.subfolders(of: "/nao/existe") == nil)
    }),
])
exit(exitCode)
