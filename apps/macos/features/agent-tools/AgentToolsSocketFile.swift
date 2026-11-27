import Darwin
import Foundation

/// The app.sock file kept alive. The file can go while the app runs: another Cadex removing it
/// (a `make run` beside the installed app, before 2026-11-27), or a clean-up of the folder. Then
/// nothing outside reached the app, `cadex` and the browser tools said Cadex was not running, and
/// only a reopen brought it back (the owner, 2026-11-27). The server watches its folder (the system
/// tells it of every change; no polling) and binds again when its file is gone or is not its own.
extension AgentToolsServer {
    func watchSocketFile() {
        guard folderWatch == nil else { return }
        let folder = (path as NSString).deletingLastPathComponent
        let fd = open(folder, O_EVTONLY)
        guard fd >= 0 else { return }
        let watch = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .delete, .rename], queue: .main)
        watch.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.socketFolderChanged() } }
        watch.setCancelHandler { close(fd) }
        watch.resume()
        folderWatch = watch
    }

    /// The folder changed: when the file is not this server's any more and nobody else answers
    /// there, this server takes it again.
    private func socketFolderChanged() {
        guard isListening, Self.inode(path) != boundInode else { return }
        // The folder itself went: a new one is watched once it is made again by bindSocket.
        if let watch = folderWatch, watch.data.contains(.delete) || watch.data.contains(.rename) {
            watch.cancel()
            folderWatch = nil
        }
        guard !Self.answers(path) else { return }
        unbind()
        do { try bindSocket() } catch { NSLog("Cadex: the app socket did not open again: %@", "\(error)") }
        watchSocketFile()
    }

    /// The file's inode; nil when there is none.
    static func inode(_ path: String) -> ino_t? {
        var info = stat()
        return lstat(path, &info) == 0 ? info.st_ino : nil
    }

    /// Whether a server answers on the socket at `path` (a connect succeeds).
    static func answers(_ path: String) -> Bool {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { return false }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in raw.copyBytes(from: bytes) }
        return withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        } == 0
    }
}
