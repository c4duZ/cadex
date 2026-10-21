import Foundation

/// The frames of a JavaScript stack, as React 19 keeps it in _debugStack
/// (plan 16, phase C). WebKit writes "name@url:line:column", Chrome
/// "at name (url:line:column)"; both end in url:line:column. Pure.
struct StackFrame: Equatable {
    var url: String
    /// 1-based, as the engine writes them.
    var line: Int
    var column: Int

    /// The frames whose url is the app's code, top first: the first one is
    /// where the JSX was written. React, the dev server's runtime and
    /// packages are left out.
    static func appFrames(in stack: String) -> [StackFrame] {
        stack.split(whereSeparator: \.isNewline).compactMap { parse(String($0)) }.filter { !isLibrary($0.url) }
    }

    static func parse(_ line: String) -> StackFrame? {
        guard let start = ["http://", "https://", "webpack-internal://"].compactMap({ line.range(of: $0)?.lowerBound }).min()
        else { return nil }
        var tail = String(line[start...]).trimmingCharacters(in: .whitespaces)
        if tail.hasSuffix(")") { tail.removeLast() }
        let parts = tail.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count >= 3, let column = Int(parts[parts.count - 1]), let row = Int(parts[parts.count - 2]) else { return nil }
        return StackFrame(url: parts.dropLast(2).joined(separator: ":"), line: row, column: column)
    }

    static let libraryMarks = ["/node_modules/", "/.vite/deps/", "/@vite/", "/@react-refresh", "react-dom",
                               "react_jsx", "jsx-dev-runtime", "jsx-runtime", "react.development", "/next/dist/"]

    static func isLibrary(_ url: String) -> Bool { libraryMarks.contains { url.contains($0) } }

    /// A file path the url itself names, for when no map answers: Vite
    /// serves /src/App.tsx and /@fs/<absolute path>; webpack writes
    /// webpack-internal:///(app-pages-browser)/./src/app/page.tsx.
    var pathInURL: String? {
        if url.hasPrefix("webpack-internal://") {
            guard let dot = url.range(of: "/./") else { return nil }
            return String(url[dot.upperBound...])
        }
        guard let path = URL(string: url)?.path, !path.isEmpty, !path.hasPrefix("/_next/") else { return nil }
        if path.hasPrefix("/@fs/") { return String(path.dropFirst(4)) }
        let name = (path as NSString).lastPathComponent
        let sourceTypes = ["js", "jsx", "ts", "tsx", "mjs", "vue", "svelte", "astro"]
        return sourceTypes.contains((name as NSString).pathExtension) ? String(path.dropFirst()) : nil
    }
}
