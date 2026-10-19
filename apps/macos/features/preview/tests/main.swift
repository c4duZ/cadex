import AppKit
import Checks
@testable import Preview

// Tests of the preview feature. Run with `make macos-test` (see
// shared/checks/Checks.swift for why this is an executable).

let exitCode = await Checks.run([
    ("addresses: http by default, only web schemes", {
        expect(PreviewDocument.url(from: "localhost:5173")?.absoluteString == "http://localhost:5173")
        expect(PreviewDocument.url(from: " https://example.com/x ")?.absoluteString == "https://example.com/x")
        expect(PreviewDocument.url(from: "file:///etc/hosts") == nil)
        expect(PreviewDocument.url(from: "javascript:alert(1)") == nil)
        expect(PreviewDocument.url(from: "") == nil)
    }),
    ("the same server opens the same tab; blank tabs are each new", {
        expect(PreviewDocument.identity(for: "http://localhost:8000/") == PreviewDocument.identity(for: "http://localhost:8000/"))
        expect(PreviewDocument.identity(for: "") != PreviewDocument.identity(for: ""))
    }),
    ("the page has no bridge to the app", {
        let doc = PreviewDocument(url: "")
        expect(doc.web.configuration.userContentController.userScripts.isEmpty)
        expect(!doc.web.configuration.websiteDataStore.isPersistent)
    }),
])
exit(exitCode)
