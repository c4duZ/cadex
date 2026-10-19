import Foundation

/// The settings in memory and on disk: Application Support/Cadex/settings.json.
/// Changes save at once; the file edited by hand while the app runs is read
/// again (docs/spec/settings.md).
@MainActor
public final class SettingsStore {
    public private(set) var settings = Settings()
    public let file: URL
    private var observers: [(Settings) -> Void] = []
    private var watcher: DispatchSourceFileSystemObject?
    /// Set while saving, so our own write does not count as a hand edit.
    private var lastWritten: Data?

    public static var defaultFile: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Cadex/settings.json")
    }

    public init(file: URL = SettingsStore.defaultFile) {
        self.file = file
        load()
    }

    /// Calls `observer` now and after every change.
    public func observe(_ observer: @escaping (Settings) -> Void) {
        observers.append(observer)
        observer(settings)
    }

    /// Changes the settings and saves them. No-op when nothing changed.
    public func update(_ change: (inout Settings) -> Void) {
        var next = settings
        change(&next)
        guard next != settings else { return }
        settings = next
        save()
        observers.forEach { $0(next) }
    }

    /// Reads the file; a missing file keeps the defaults. Problems go to the
    /// log and the rest of the file counts.
    public func load() {
        guard let data = try? Data(contentsOf: file) else { return }
        let (read, problems) = SettingsFile.read(data)
        problems.forEach { NSLog("settings.json: %@", $0) }
        guard read != settings else { return }
        settings = read
        observers.forEach { $0(read) }
    }

    private func save() {
        let data = SettingsFile.write(settings)
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            lastWritten = data
        } catch {
            NSLog("settings.json: não deu para salvar: %@", error.localizedDescription)
        }
    }

    /// Watches the folder (an atomic save replaces the file, so watching the
    /// file itself would lose track after the first edit).
    public func watchForEdits() {
        let folder = file.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.fileChanged() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        watcher = source
    }

    private func fileChanged() {
        guard let data = try? Data(contentsOf: file), data != lastWritten else { return }
        load()
    }
}
