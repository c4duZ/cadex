import AppKit
import Strings

/// The "About" page (docs/spec/settings.md); General's rows went to their sections
/// (`SectionRows.swift`, plan 32 B).
@MainActor
enum GeneralPages {
    static func about() -> NSView {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? T("development", "desenvolvimento")
        let credits = NSTextField(wrappingLabelWithString: T(
            "A terminal-centered development workspace, native, with its own code under the MIT license. The terminal model is libghostty-vt; the icons are Phosphor; the themes come from the official palettes of open themes, tweakcn and the base16 schemes of tinted-theming. Full credits in the NOTICE file.",
            "Workspace de desenvolvimento centrado no terminal, nativo, com código próprio sob a licença MIT. O modelo do terminal é a libghostty-vt; os ícones são Phosphor; os temas vêm das paletas oficiais de temas abertos, do tweakcn e dos esquemas base16 do tinted-theming. Créditos completos no arquivo NOTICE."))
        credits.textColor = SettingsColors.secondaryText
        return SettingsPage.make(title: "Cadex", subtitle: T("Version", "Versão") + " \(version)", rows: [credits])
    }
}
