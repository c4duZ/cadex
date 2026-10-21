import Foundation

/// Where React 19 wrote an element, from the stack it keeps (plan 16,
/// phase C): the first frame of the app's code, mapped back by the Next dev
/// server or by the source map the script points to. Fetched from Swift,
/// so the page's CSP and CORS do not apply, and only from the page's own
/// origin: the app never fetches for the page elsewhere
/// (docs/adr/0018-element-picker.md).
enum SourceLookup {
    /// A click waits this long at most per fetch.
    static let timeout: TimeInterval = 1.5
    /// A map bigger than this is not read.
    static let maxBytes = 20_000_000

    /// "file:line:column", or the file alone when only the url names it.
    static func resolve(stack: String, page: URL?) async -> String? {
        guard let page else { return nil }
        let frames = Array(StackFrame.appFrames(in: stack).prefix(3))
        for frame in frames {
            var found = await fromNext(frame, page: page)
            if found == nil { found = await fromMap(frame, page: page) }
            if let found, !StackFrame.isLibrary(found) { return found }
        }
        return frames.first?.pathInURL
    }

    static func sameOrigin(_ url: URL, _ page: URL) -> Bool {
        url.scheme == page.scheme && url.host == page.host && url.port == page.port
    }

    /// The Next dev server maps its own frames (webpack and Turbopack).
    static func fromNext(_ frame: StackFrame, page: URL) async -> String? {
        guard frame.url.contains("/_next/") || frame.url.hasPrefix("webpack-internal:"),
              let endpoint = URL(string: "/__nextjs_original-stack-frames", relativeTo: page)?.absoluteURL else { return nil }
        let body: [String: Any] = [
            "frames": [["file": frame.url, "methodName": "", "arguments": [], "lineNumber": frame.line, "column": frame.column]],
            "isServer": false, "isEdgeServer": false, "isAppDirectory": true,
        ]
        var request = URLRequest(url: endpoint, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let data = await fetch(request, page: page),
              let list = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]],
              let value = list.first?["value"] as? [String: Any],
              let original = value["originalStackFrame"] as? [String: Any],
              let file = original["file"] as? String, !file.isEmpty else { return nil }
        let line = original["lineNumber"] as? Int
        let column = original["column"] as? Int
        return SourceMap.normalized(file) + (line.map { ":\($0)" + (column.map { ":\($0)" } ?? "") } ?? "")
    }

    /// The script's `//# sourceMappingURL`: inline (Vite) or a file beside it.
    static func fromMap(_ frame: StackFrame, page: URL) async -> String? {
        guard let script = URL(string: frame.url), let data = await fetch(URLRequest(url: script, timeoutInterval: timeout), page: page),
              let text = String(data: data, encoding: .utf8), let link = mapLink(in: text),
              let mapData = await mapData(link, script: script, page: page),
              let map = SourceMap(json: mapData),
              let found = map.original(line: frame.line - 1, column: frame.column - 1) else { return nil }
        return resolved(found.source, script: script) + ":\(found.line):\(found.column)"
    }

    /// The last sourceMappingURL comment of a script.
    static func mapLink(in script: String) -> String? {
        guard let range = script.range(of: "//# sourceMappingURL=", options: .backwards) else { return nil }
        let link = script[range.upperBound...].prefix { !$0.isWhitespace }
        return link.isEmpty ? nil : String(link)
    }

    static func mapData(_ link: String, script: URL, page: URL) async -> Data? {
        if link.hasPrefix("data:") {
            guard let comma = link.firstIndex(of: ",") else { return nil }
            let payload = String(link[link.index(after: comma)...])
            return link[..<comma].hasSuffix(";base64") ? Data(base64Encoded: payload) : payload.removingPercentEncoding?.data(using: .utf8)
        }
        guard let url = URL(string: link, relativeTo: script)?.absoluteURL else { return nil }
        return await fetch(URLRequest(url: url, timeoutInterval: timeout), page: page)
    }

    /// A map's source as a path: a bundler's scheme taken off (webpack,
    /// Turbopack, file), absolute as is, relative from the script's folder
    /// (Vite: /src/x.tsx as "src/x.tsx", /@fs/<path> as the absolute path).
    static func resolved(_ source: String, script: URL) -> String {
        if source.contains("://") || source.hasPrefix("/") { return SourceMap.normalized(source) }
        guard let path = URL(string: source, relativeTo: script)?.path else { return source }
        if path.hasPrefix("/@fs/") { return String(path.dropFirst(4)) }
        return String(path.dropFirst())
    }

    private static func fetch(_ request: URLRequest, page: URL) async -> Data? {
        guard let url = request.url, sameOrigin(url, page),
              let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200, data.count <= maxBytes else { return nil }
        return data
    }
}
