import Foundation

/// One file downloaded with progress. A delegate session, because the async
/// `URLSession.download(from:)` reports no bytes on the way.
final class UpdateDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    /// Bytes so far and the total, when the server says it.
    typealias Progress = @Sendable (Int64, Int64?) -> Void

    private let destination: URL
    private let progress: Progress
    // Touched only from the session's serial delegate queue.
    private var continuation: CheckedContinuation<Void, Error>?
    private var failure: Error?

    private init(destination: URL, progress: @escaping Progress) {
        self.destination = destination
        self.progress = progress
    }

    /// Downloads `url` to `destination`, failing on an HTTP error.
    static func fetch(_ url: URL, to destination: URL, progress: @escaping Progress) async throws {
        let download = UpdateDownload(destination: destination, progress: progress)
        let session = URLSession(configuration: .ephemeral, delegate: download, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        try await withCheckedThrowingContinuation { continuation in
            session.delegateQueue.addOperation {
                download.continuation = continuation
                session.downloadTask(with: url).resume()
            }
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        progress(totalBytesWritten, totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil)
    }

    /// The file at `location` is gone once this returns: it moves now.
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            failure = UpdateError.server(http.statusCode)
            return
        }
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
        } catch {
            failure = error
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error ?? failure {
            continuation?.resume(throwing: error)
        } else {
            continuation?.resume()
        }
        continuation = nil
    }
}
