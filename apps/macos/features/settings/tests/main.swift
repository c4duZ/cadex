import Checks
import Foundation
@testable import Settings

// Tests of the settings feature. Run with `make macos-test` (see
// shared/checks/Checks.swift for why this is an executable).

let exitCode = await Checks.run([
    ("settings saved and read back are the same", {
        var settings = Settings()
        settings.terminal.fontSize = 15
        settings.terminal.cursor = "block"
        settings.appearance.theme = "tokyo-night"
        settings.appearance.backgroundImage = "/tmp/fundo.png"
        settings.shortcuts = ["cmd+shift+t": "tab.new", "cmd+t": nil]
        let (read, problems) = SettingsFile.read(SettingsFile.write(settings))
        expect(problems.isEmpty, "\(problems)")
        expect(read == settings, "\(read)")
    }),
    ("a broken file gives the defaults and says why", {
        let (read, problems) = SettingsFile.read(Data("{ quebrado".utf8))
        expect(read == Settings())
        expect(problems.count == 1)
    }),
    ("a wrong field falls back alone; the rest still counts", {
        let json = #"{"terminal": {"fontSize": "grande", "cursor": "losango", "copyOnSelect": true}}"#
        let (read, problems) = SettingsFile.read(Data(json.utf8))
        expect(read.terminal.fontSize == 13 && read.terminal.cursor == "bar")
        expect(read.terminal.copyOnSelect)
        expect(problems.count == 2, "\(problems)")
    }),
    ("sizes and history are kept within the limits", {
        let json = #"{"terminal": {"fontSize": 99, "historyLines": 5000000}}"#
        let (read, _) = SettingsFile.read(Data(json.utf8))
        expect(read.terminal.fontSize == 32)
        expect(read.terminal.historyLines == 100_000)
    }),
    ("the store saves on change and reads a hand edit back", {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("cadex-settings-\(UUID())/settings.json")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = SettingsStore(file: file)
        var seen: [Double] = []
        store.observe { seen.append($0.terminal.fontSize) }
        store.update { $0.terminal.fontSize = 16 }
        expect(SettingsFile.read(try Data(contentsOf: file)).0.terminal.fontSize == 16)

        var edited = store.settings
        edited.terminal.fontSize = 18
        try SettingsFile.write(edited).write(to: file)
        store.load()
        expect(store.settings.terminal.fontSize == 18)
        expect(seen == [13, 16, 18], "\(seen)")
    }),
])
exit(exitCode)
