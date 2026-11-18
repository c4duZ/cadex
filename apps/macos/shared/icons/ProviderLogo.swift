import AppKit

/// The logo of the AI provider an account belongs to (Agents › Accounts,
/// the usage item): Lobe Icons (MIT), one color, so it takes the theme's
/// color like Phosphor (docs/adr/0020-provider-logos.md). PDFs built by
/// tools/icons/build_provider_logos.py. Only to name an account's provider.
public enum ProviderLogo: String, CaseIterable, Sendable {
    case claude
    case openai
    case codex
    case copilot = "githubcopilot"
    case cursor
    case gemini

    /// The provider's own color, where a list shows the logo as the provider's sign (the approved
    /// proposal's menus and account list, 2026-11-18: Claude's orange); nil keeps the theme's.
    public var brandColor: NSColor? {
        switch self {
        case .claude: NSColor(srgbRed: 0xD9 / 255, green: 0x77 / 255, blue: 0x57 / 255, alpha: 1)
        default: nil
        }
    }

    /// A template image: the view tints it.
    @MainActor
    public func image(size: CGFloat) -> NSImage {
        let source = Self.folder.flatMap { NSImage(contentsOf: $0.appendingPathComponent(rawValue + ".pdf")) }
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            source?.draw(in: rect)
            return true
        }
        image.isTemplate = true
        return image
    }

    /// In Cadex.app the folder is in Contents/Resources (packaging/build.sh);
    /// running from the build, SwiftPM's bundle.
    private static var folder: URL? {
        Bundle.main.url(forResource: "ProviderLogos", withExtension: nil) ?? Bundle.module.url(forResource: "ProviderLogos", withExtension: nil)
    }
}
