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
