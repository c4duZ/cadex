import Checks
import Darwin
import Foundation
@testable import Machines

// `cadex share` (plan 39 E): the links, the hour, nothing outside the shared
// page's folder, the page by kind, and the server on 127.0.0.1 (standing for
// the 100.x address) with a fake WhoIs.

/// One HTTP GET over a fresh connection; the whole answer, or "" when closed unheard.
func httpGet(_ port: UInt16, _ path: String, range: String? = nil) -> String {
    guard let fd = connectTCP("127.0.0.1", port) else { return "" }
    defer { close(fd) }
    var timeout = timeval(tv_sec: 2, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    let request = "GET \(path) HTTP/1.1\r\nHost: x\r\n" + (range.map { "Range: \($0)\r\n" } ?? "") + "\r\n"
    _ = Array(request.utf8).withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
    var answer = Data()
    var buffer = [UInt8](repeating: 0, count: 65536)
    while true {
        let n = read(fd, &buffer, buffer.count)
        if n <= 0 { break }
        answer.append(buffer, count: n)
    }
    return String(decoding: answer, as: UTF8.self)
}

let fileShareTests: [(name: String, body: Checks.Body)] = [
    ("a share: a token, the same link again, gone after the hour; never outside the page's folder", {
        let dir = tempDir()
        defer { try? fm.removeItem(atPath: dir) }
        try? fm.createDirectory(atPath: dir + "/site/img", withIntermediateDirectories: true)
        fm.createFile(atPath: dir + "/site/index.html", contents: data("<img src=img/a.png>"))
        fm.createFile(atPath: dir + "/site/img/a.png", contents: data("png"))
        fm.createFile(atPath: dir + "/secret.txt", contents: data("no"))
        fm.createFile(atPath: dir + "/site/notes.pdf", contents: data("%PDF"))
        try? fm.createSymbolicLink(atPath: dir + "/site/out.txt", withDestinationPath: dir + "/secret.txt")
        let store = FileShareStore()
        let page = store.add(dir + "/site/index.html")!
        expect(page.token.count == 32 && store.add(dir + "/site/index.html")?.token == page.token, "same file, same link")
        expect(store.add(dir + "/site") == nil && store.add(dir + "/none") == nil, "a folder or nothing is not shared")
        expect(store.file(page, relative: "img/a.png")?.hasSuffix("/site/img/a.png") == true, "the page's neighbours")
        expect(store.file(page, relative: "../secret.txt") == nil && store.file(page, relative: "img/../../secret.txt") == nil, "nothing above")
        expect(store.file(page, relative: "out.txt") == nil, "nor a link out of the folder")
        expect(store.file(page, relative: "/etc/hosts") == nil)
        let pdf = store.add(dir + "/site/notes.pdf")!
        expect(store.file(pdf, relative: "index.html") == nil, "a PDF shares only itself")
        let later = Date().addingTimeInterval(FileShareStore.lifetime + 1)
        store.now = { later }
        expect(store.share(page.token) == nil && store.list().isEmpty, "an hour later, gone")
    }),
    ("the page by kind: Office opens by Safari, Markdown rendered, text escaped; the media types", {
        expect(FileSharePage.kind(of: "a.DOCX") == .office && FileSharePage.kind(of: "a.md") == .markdown)
        expect(FileSharePage.mime(of: "a.docx") == "application/vnd.openxmlformats-officedocument.wordprocessingml.document")
        expect(FileSharePage.mime(of: "a.html").hasPrefix("text/html") && FileSharePage.mime(of: "x.bin") == "application/octet-stream")
        let dir = tempDir()
        defer { try? fm.removeItem(atPath: dir) }
        fm.createFile(atPath: dir + "/r.md", contents: data("# Hi"))
        fm.createFile(atPath: dir + "/c.txt", contents: data("<script>x</script>"))
        fm.createFile(atPath: dir + "/w.docx", contents: data("doc"))
        let store = FileShareStore()
        let md = FileSharePage.page(store.add(dir + "/r.md")!, size: 4, markdown: { "<h1>" + $0.dropFirst(2) + "</h1>" })
        expect(md.contains("<h1>Hi</h1>") && md.contains("href=\"download\""))
        let text = FileSharePage.page(store.add(dir + "/c.txt")!, size: 18, markdown: nil)
        expect(text.contains("&lt;script&gt;") && !text.contains("<script>x"), "text is escaped")
        let word = FileSharePage.page(store.add(dir + "/w.docx")!, size: 3, markdown: nil)
        expect(word.contains("href=\"raw/w.docx\">Open") && !word.contains("<iframe"))
    }),
    ("the server: the page, the file, a range, the download; a stranger's device closed unheard", {
        let dir = tempDir()
        defer { try? fm.removeItem(atPath: dir) }
        fm.createFile(atPath: dir + "/v.mp4", contents: data("0123456789"))
        let server = FileShareServer()
        let answer = Answer()
        server.listener.whois = { _ in answer.owner }
        let port = UInt16(40_000 + (Int(getpid()) + 7) % 20_000)
        expect(server.start(ip: "127.0.0.1", owner: "1", port: port) == "http://127.0.0.1:\(port)")
        defer { server.stop() }
        let token = server.store.add(dir + "/v.mp4")!.token
        let page = await Task.detached { httpGet(port, "/s/\(token)/") }.value
        expect(page.hasPrefix("HTTP/1.1 200") && page.contains("<video src=\"raw/v.mp4\""))
        let part = await Task.detached { httpGet(port, "/s/\(token)/raw/v.mp4", range: "bytes=2-5") }.value
        expect(part.hasPrefix("HTTP/1.1 206") && part.contains("Content-Range: bytes 2-5/10") && part.hasSuffix("\r\n\r\n2345"))
        let saved = await Task.detached { httpGet(port, "/s/\(token)/download") }.value
        expect(saved.contains("Content-Disposition: attachment; filename=\"v.mp4\"") && saved.hasSuffix("0123456789"))
        let bare = await Task.detached { httpGet(port, "/s/\(token)") }.value
        expect(bare.hasPrefix("HTTP/1.1 301") && bare.contains("Location: /s/\(token)/"))
        let wrong = await Task.detached { httpGet(port, "/s/0000/") }.value
        expect(wrong.hasPrefix("HTTP/1.1 404"))
        answer.owner = "2"
        let stranger = await Task.detached { httpGet(port, "/s/\(token)/") }.value
        expect(stranger.isEmpty, "another user's device")
        expect(FileShareServer.range("bytes=-3", size: 10)! == (7, 9) && FileShareServer.range("bytes=20-", size: 10) == nil)
    }),
]
