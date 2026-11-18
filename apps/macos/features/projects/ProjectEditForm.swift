import AppKit
import Strings
import UILooks

/// The form of the "Edit project" sheet (plan 36 phase B; docs/adr/0038-rail-and-side-column.md):
/// the name, the picture (an image of the Mac, or an emoji, or the letter), the color, and when
/// creating, the folder. The app shows it in the frame's sheet and applies what it says.
@MainActor
public final class ProjectEditForm: NSView {
    typealias NT = DesignTokens.NewTask
    public let nameField = NSTextField()
    let emojiField = NSTextField()
    private let preview = ProjectPreview()
    private let folderLabel = FrameField.text("")
    private var swatches: [(name: String?, view: ColorSwatch)] = []
    /// A new picture picked (a file of the Mac); applied on Save.
    public private(set) var pickedImage: URL?
    /// The picture there was is taken away on Save.
    public private(set) var removesImage = false
    public private(set) var color: String?
    public private(set) var folder: String?
    private let currentImage: String?

    /// `colors`: the work colors by name and how they look; `image`: the current picture's file;
    /// `folder`: nil edits, a path (or "") creates and shows the folder row.
    public init(name: String, color: String?, colors: [(name: String, color: NSColor)], image: String?, emoji: String?,
                folder: String?) {
        self.color = color
        self.folder = folder
        currentImage = image
        super.init(frame: .zero)
        nameField.stringValue = name
        nameField.placeholderString = T("The project's name", "O nome do projeto")
        emojiField.stringValue = emoji ?? ""
        emojiField.placeholderString = T("Emoji", "Emoji")
        emojiField.target = self
        emojiField.action = #selector(emojiChanged)
        nameField.delegate = self
        emojiField.delegate = self
        var rows: [NSView] = [FrameField.labeled(T("Name", "Nome"), FrameField.field(nameField)), pictureRow(), colorRow(colors)]
        if let folder {
            folderLabel.stringValue = folder.isEmpty ? T("No folder chosen", "Nenhuma pasta escolhida") : folder
            let choose = DesignButton.make(T("Choose…", "Escolher…"), .secondary) { [weak self] in self?.chooseFolder() }
            rows.append(FrameField.labeled(T("Folder", "Pasta"), line([folderLabel, choose])))
        }
        let column = FrameField.column(rows, gap: NT.Frame.labelTop)
        addSubview(column)
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: topAnchor), column.bottomAnchor.constraint(equalTo: bottomAnchor),
            column.leadingAnchor.constraint(equalTo: leadingAnchor), column.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        for row in rows { row.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true }
        refreshPreview()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("ProjectEditForm is created in code") }

    public var emoji: String { emojiField.stringValue.trimmingCharacters(in: .whitespaces) }

    private func pictureRow() -> NSView {
        let choose = DesignButton.make(T("Choose Image…", "Escolher imagem…"), .secondary) { [weak self] in self?.chooseImage() }
        let remove = DesignButton.make(T("Remove", "Tirar"), .secondary) { [weak self] in
            self?.pickedImage = nil
            self?.removesImage = true
            self?.refreshPreview()
        }
        emojiField.widthAnchor.constraint(equalToConstant: UILooks.pt(DesignTokens.Rail.width)).isActive = true
        let row = line([preview, choose, remove, FrameField.field(emojiField)])
        let hint = FrameField.wrapping(T("An image of the Mac (or dropped on the project in the rail), an emoji, or the name's letter.",
                                         "Uma imagem do Mac (ou solta no projeto, no trilho), um emoji ou a letra do nome."))
        return FrameField.labeled(T("Picture", "Imagem"), FrameField.column([row, hint], gap: NT.Frame.labelBottom))
    }

    private func colorRow(_ colors: [(name: String, color: NSColor)]) -> NSView {
        let all: [(String?, NSColor?)] = [(nil, nil)] + colors.map { ($0.name, $0.color) }
        swatches = all.map { name, color in
            let swatch = ColorSwatch(color: color, tip: name ?? T("No color", "Sem cor"))
            swatch.onPress = { [weak self] in
                self?.color = name
                self?.refreshPreview()
            }
            return (name, swatch)
        }
        return FrameField.labeled(T("Color", "Cor"), line(swatches.map(\.view)))
    }

    private func line(_ views: [NSView]) -> NSView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = UILooks.pt(NT.Option.gap)
        return stack
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.canChooseDirectories = false
        guard let window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            MainActor.assumeIsolated {
                guard response == .OK, let url = panel.url, let self else { return }
                self.pickedImage = url
                self.removesImage = false
                self.refreshPreview()
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        guard let window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            MainActor.assumeIsolated {
                guard response == .OK, let path = panel.url?.path, let self else { return }
                self.folder = path
                self.folderLabel.stringValue = path
                if self.nameField.stringValue.isEmpty { self.nameField.stringValue = (path as NSString).lastPathComponent }
                self.refreshPreview()
            }
        }
    }

    @objc private func emojiChanged() { refreshPreview() }

    /// The tile as the rail will show it.
    func refreshPreview() {
        let image = pickedImage.flatMap { NSImage(contentsOf: $0) } ?? (removesImage ? nil : currentImage.flatMap { NSImage(contentsOfFile: $0) })
        let swatch = swatches.first { $0.name == color }?.view.color
        let letter = nameField.stringValue.first { $0.isLetter || $0.isNumber }.map { String($0).uppercased() } ?? "•"
        preview.show(image: image, mark: emoji.isEmpty ? letter : emoji, emoji: !emoji.isEmpty, color: swatch)
        for (name, view) in swatches { view.chosen = name == color }
    }

}

extension ProjectEditForm: NSTextFieldDelegate {
    public func controlTextDidChange(_ notification: Notification) { refreshPreview() }
}
