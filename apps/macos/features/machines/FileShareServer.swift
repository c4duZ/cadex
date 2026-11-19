import Darwin
import Foundation

/// `cadex share <file>` (plan 39 E, docs/plans/39-terminals-from-the-phone.md):
/// the shared files over HTTP on this Mac's tailnet address only (port 47101,
/// a listener of its own beside the app's 47100), each connection let in by
/// WhoIs as the owner's own device, as TailnetListener does. Paths:
/// `/s/<token>/` the page, `/s/<token>/raw/<file>` the file (an HTML page's
/// neighbours too), `/s/<token>/download` the file to save.
public final class FileShareServer: @unchecked Sendable {
    public static let shared = FileShareServer()
    public static let port: UInt16 = 47_101

    public let store = FileShareStore()
    let listener = TailnetListener()
    /// Markdown into HTML (the markdown feature's, set by the app).
    public var markdown: (@Sendable (String) -> String)?
    private let queue = DispatchQueue(label: "cadex.fileshare", qos: .utility, attributes: .concurrent)

    init() {
        listener.onAccepted = { [weak self] fd in self?.queue.async { self?.serve(fd) } }
    }

    /// Listening on `ip` for `owner`'s devices; the link's start, or nil.
    public func start(ip: String, owner: String, port: UInt16 = FileShareServer.port) -> String? {
        guard listener.start(ip: ip, owner: owner, port: port) else { return nil }
        return "http://\(ip):\(port)"
    }

    public func stop() { listener.stop() }

    // MARK: HTTP

    func serve(_ fd: Int32) {
        defer { close(fd) }
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        guard let request = Self.readHead(fd), let line = request.split(separator: "\r\n").first else { return }
        let words = line.split(separator: " ")
        guard words.count >= 2, words[0] == "GET" || words[0] == "HEAD" else { return reply(fd, 405, "text/plain", Data("no".utf8)) }
        let head = words[0] == "HEAD"
        let path = String(words[1].split(separator: "?").first ?? "")
        let range = Self.header("range", in: request)
        switch route(path) {
        case .page(let share):
            let size = (try? FileManager.default.attributesOfItem(atPath: share.path)[.size] as? Int64) ?? 0
            reply(fd, 200, "text/html; charset=utf-8", Data(FileSharePage.page(share, size: size, markdown: markdown).utf8), head: head)
        case .file(let file, let download):
            sendFile(fd, file, download: download, range: range, head: head)
        case .redirect(let to):
            reply(fd, 301, "text/plain", Data(), extra: "Location: \(to)\r\n", head: head)
        case .missing:
            reply(fd, 404, "text/plain; charset=utf-8", Data("Not shared, or the hour is over.\n".utf8), head: head)
        }
    }

    enum Route: Equatable { case page(FileShareStore.Share), file(String, download: Bool), redirect(String), missing }

    func route(_ path: String) -> Route {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        // "", "s", token, rest…
        guard parts.count >= 3, parts[0].isEmpty, parts[1] == "s", let share = store.share(parts[2]) else { return .missing }
        if parts.count == 3 { return .redirect(path + "/") }
        let rest = parts[3...].joined(separator: "/")
        if rest.isEmpty { return .page(share) }
        if rest == "download" { return .file(share.path, download: true) }
        guard rest.hasPrefix("raw/"), let file = store.file(share, relative: String(rest.dropFirst(4))) else { return .missing }
        return .file(file, download: false)
    }

    private func sendFile(_ fd: Int32, _ path: String, download: Bool, range: String?, head: Bool) {
        guard let handle = FileHandle(forReadingAtPath: path),
              let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64) else {
            return reply(fd, 404, "text/plain", Data())
        }
        defer { try? handle.close() }
        var extra = "Accept-Ranges: bytes\r\n"
        if download {
            let name = (path as NSString).lastPathComponent
            let ascii = name.unicodeScalars.map { $0.isASCII && $0 != "\"" ? String($0) : "_" }.joined()
            extra += "Content-Disposition: attachment; filename=\"\(ascii)\"; filename*=UTF-8''\(name.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ascii)\r\n"
        }
        // Safari asks a video in ranges; one range is enough for it.
        var start: Int64 = 0, end = size - 1, status = 200
        if let range, let bounds = Self.range(range, size: size) {
            (start, end, status) = (bounds.0, bounds.1, 206)
            extra += "Content-Range: bytes \(start)-\(end)/\(size)\r\n"
        }
        let length = max(0, end - start + 1)
        guard writeHead(fd, status, FileSharePage.mime(of: path), length: length, extra: extra), !head else { return }
        try? handle.seek(toOffset: UInt64(start))
        var left = length
        while left > 0 {
            let chunk = handle.readData(ofLength: Int(min(left, 256 * 1024)))
            if chunk.isEmpty || !Self.writeAll(fd, chunk) { return }
            left -= Int64(chunk.count)
        }
    }

    private func reply(_ fd: Int32, _ status: Int, _ type: String, _ body: Data, extra: String = "", head: Bool = false) {
        guard writeHead(fd, status, type, length: Int64(body.count), extra: extra), !head else { return }
        _ = Self.writeAll(fd, body)
    }

    private func writeHead(_ fd: Int32, _ status: Int, _ type: String, length: Int64, extra: String) -> Bool {
        let reason = [200: "OK", 206: "Partial Content", 301: "Moved Permanently", 404: "Not Found", 405: "Method Not Allowed"][status] ?? "OK"
        let head = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: \(type)\r\nContent-Length: \(length)\r\n"
            + "Cache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nConnection: close\r\n\(extra)\r\n"
        return Self.writeAll(fd, Data(head.utf8))
    }

    static func range(_ header: String, size: Int64) -> (Int64, Int64)? {
        guard header.hasPrefix("bytes="), size > 0 else { return nil }
        let spec = header.dropFirst(6).split(separator: ",").first.map(String.init) ?? ""
        let ends = spec.split(separator: "-", omittingEmptySubsequences: false).map { Int64($0.trimmingCharacters(in: .whitespaces)) }
        guard ends.count == 2 else { return nil }
        switch (ends[0], ends[1]) {
        case let (s?, e?) where s <= e && s < size: return (s, min(e, size - 1))
        case let (s?, nil) where s < size: return (s, size - 1)
        case let (nil, n?) where n > 0: return (max(0, size - n), size - 1)
        default: return nil
        }
    }

    static func header(_ name: String, in request: String) -> String? {
        for line in request.split(separator: "\r\n").dropFirst() {
            let pair = line.split(separator: ":", maxSplits: 1)
            if pair.count == 2, pair[0].lowercased() == name { return pair[1].trimmingCharacters(in: .whitespaces) }
        }
        return nil
    }

    /// The request's head (up to the blank line), at most 16 KB.
    static func readHead(_ fd: Int32) -> String? {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while data.count < 16 * 1024 {
            let n = read(fd, &buffer, buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
            if data.range(of: Data("\r\n\r\n".utf8)) != nil { break }
        }
        return data.isEmpty ? nil : String(data: data, encoding: .utf8)
    }

    static func writeAll(_ fd: Int32, _ data: Data) -> Bool {
        data.withUnsafeBytes { raw in
            var sent = 0
            while sent < raw.count {
                let n = write(fd, raw.baseAddress! + sent, raw.count - sent)
                if n <= 0 { return false }
                sent += n
            }
            return true
        }
    }
}
