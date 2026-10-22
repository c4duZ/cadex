import AppKit
import Strings

/// Settings › General › Agents: a row per kind of notification, its sound
/// and its switch side by side (docs/spec/agents.md, Notificações). Picking
/// a sound plays it, so you hear what you chose; "Choose File…" takes one of
/// yours (.aiff, .wav, .caf: what macOS plays in a notification).
@MainActor
enum NotificationRows {
    static func make(_ store: SettingsStore) -> [NSView] {
        let agents = store.settings.agents
        return [
            row(T("Notify when an agent asks permission", "Avisar quando um agente pede permissão"),
                T("A notification from macOS with the command or file; a click goes to its terminal. Not while you look at that terminal.",
                  "Uma notificação do macOS com o comando ou o arquivo; o clique leva ao terminal dele. Não enquanto você olha aquele terminal."),
                on: agents.notifyPermission, sound: agents.soundPermission,
                switched: { on in store.update { $0.agents.notifyPermission = on } },
                picked: { value in store.update { $0.agents.soundPermission = value } }),
            row(T("Notify when an agent asks a question", "Avisar quando um agente faz uma pergunta"),
                T("With the question, when the agent's log has it.", "Com a pergunta, quando o log do agente a tem."),
                on: agents.notifyQuestion, sound: agents.soundQuestion,
                switched: { on in store.update { $0.agents.notifyQuestion = on } },
                picked: { value in store.update { $0.agents.soundQuestion = value } }),
            row(T("Notify when an agent finishes", "Avisar quando um agente termina"),
                T("With the first line of its last reply.", "Com a primeira linha da última resposta."),
                on: agents.notifyFinished, sound: agents.soundFinished,
                switched: { on in store.update { $0.agents.notifyFinished = on } },
                picked: { value in store.update { $0.agents.soundFinished = value } }),
        ]
    }

    private static func row(_ label: String, _ detail: String, on: Bool, sound: String,
                            switched: @escaping (Bool) -> Void, picked: @escaping (String) -> Void) -> NSView {
        let control = NSStackView(views: [soundPopup(sound, picked: picked), SettingsPage.toggle(on, switched)])
        control.spacing = 10
        return SettingsPage.row(label, detail, control: control)
    }

    static let chooseFile = "choose-file"

    /// None, the system's alert, every macOS sound, your file if one is
    /// chosen, and "Choose File…".
    static func options(selected: String) -> [(title: String, value: String)] {
        var options: [(title: String, value: String)] = [(T("No Sound", "Sem som"), "none"), (T("Default", "Padrão"), "default")]
        options += systemSounds().map { ($0, $0) }
        if selected.hasPrefix("/") { options.append(((selected as NSString).lastPathComponent, selected)) }
        options.append((T("Choose File…", "Escolher arquivo…"), chooseFile))
        return options
    }

    /// The sounds macOS ships, by name ("Basso" … "Tink").
    static func systemSounds(folder: String = "/System/Library/Sounds") -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? [])
            .filter { $0.hasSuffix(".aiff") }.map { String($0.dropLast(5)) }.sorted()
    }

    private static func soundPopup(_ selected: String, picked: @escaping (String) -> Void) -> NSPopUpButton {
        var popup: NSPopUpButton?
        let control = SettingsPage.popup(options(selected: selected), selected: selected) { value in
            guard value == chooseFile else {
                play(value)
                return picked(value)
            }
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.aiff, .wav, .init(filenameExtension: "caf")].compactMap { $0 }
            panel.message = T("A short sound: macOS plays up to 30 seconds of it.", "Um som curto: o macOS toca até 30 segundos dele.")
            guard panel.runModal() == .OK, let url = panel.url else {
                // Cancelled: back to what was chosen.
                popup?.selectItem(at: options(selected: selected).firstIndex { $0.value == selected } ?? 0)
                return
            }
            play(url.path)
            picked(url.path)
        }
        popup = control
        return control
    }

    /// The sound now, as it will play.
    static func play(_ value: String) {
        switch value {
        case "none": return
        case "default": NSSound.beep()
        default:
            let path = value.hasPrefix("/") ? value : "/System/Library/Sounds/\(value).aiff"
            NSSound(contentsOfFile: path, byReference: true)?.play()
        }
    }
}
