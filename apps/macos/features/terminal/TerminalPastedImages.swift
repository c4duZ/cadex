import AppKit
import CCadex

/// Seeing a pasted image again (docs/spec/terminal.md, Ver a imagem
/// colada): the "[Image #N]" tag an agent shows for a ⌘V'd image points to
/// the PNG this terminal saved; hovering shows it, clicking opens it.
extension TerminalView {
    /// Called by ⌘V after the image's path went to the program.
    func notePastedImage(_ file: URL) {
        pastedImages.pasted(file, visible: PastedImageTag.counts(session?.visibleImageTags() ?? []))
    }

    /// New output while a paste waits for its tag. Coalesced: a burst of
    /// output reads the screen once.
    func matchPastedImagesSoon() {
        guard pastedImages.isWaiting, !pastedImageMatchScheduled else { return }
        pastedImageMatchScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            self.pastedImageMatchScheduled = false
            self.pastedImages.screenChanged(visible: PastedImageTag.counts(self.session?.visibleImageTags() ?? []))
        }
    }

    /// The tag under the pointer whose file still exists.
    func pastedImage(at location: CGPoint) -> (tag: PastedImageTag, file: URL)? {
        guard bounds.contains(location), !pastedImages.files.isEmpty, let session else { return nil }
        let p = geometry.pointer(at: location)
        let col = Int(p.col)
        let row = Int(p.row)
        guard let tag = session.visibleImageTags(rows: row...row).first(where: { $0.firstCol <= col && col <= $0.lastCol }),
              let file = pastedImages.file(for: tag.number),
              FileManager.default.fileExists(atPath: file.path)
        else { return nil }
        return (tag, file)
    }

    /// Shows or hides the thumbnail as the pointer moves. True while the
    /// pointer is on a tag, so the link code leaves the cursor alone.
    @discardableResult
    func refreshImageHover(at location: CGPoint) -> Bool {
        guard let hit = pastedImage(at: location) else {
            hideImageHover()
            return false
        }
        NSCursor.pointingHand.set()
        if imageHover?.file == hit.file { return true }
        hideImageHover()
        guard let hover = PastedImageHover(file: hit.file) else { return false }
        addSubview(hover)
        hover.place(below: tagRect(hit.tag), in: bounds)
        imageHover = hover
        return true
    }

    func hideImageHover() {
        imageHover?.removeFromSuperview()
        imageHover = nil
    }

    /// A click on a tag opens its image; false lets the click select.
    func openPastedImage(at location: CGPoint) -> Bool {
        guard let onOpenFile, let hit = pastedImage(at: location) else { return false }
        hideImageHover()
        onOpenFile(hit.file.path, nil)
        return true
    }

    /// The commands: the newest image pasted here, beside or in a new tab.
    @objc public func openLastPastedImageBeside(_ sender: Any?) { openLastPastedImage(beside: true) }
    @objc public func openLastPastedImageInTab(_ sender: Any?) { openLastPastedImage(beside: false) }

    private func openLastPastedImage(beside: Bool) {
        guard let file = pastedImages.latest else { return }
        onOpenFile?(file.path, beside)
    }

    /// The commands exist only for a terminal that pasted an image (the
    /// palette hides what cannot run).
    public override func responds(to selector: Selector!) -> Bool {
        if selector == #selector(openLastPastedImageBeside(_:)) || selector == #selector(openLastPastedImageInTab(_:)) {
            guard onOpenFile != nil, let file = pastedImages.latest else { return false }
            return FileManager.default.fileExists(atPath: file.path)
        }
        return super.responds(to: selector)
    }

    /// The tag's cells in view points (AppKit's y grows upward).
    private func tagRect(_ tag: PastedImageTag) -> CGRect {
        let g = geometry
        let w = CGFloat(g.cellWidth) / g.scale
        let h = CGFloat(g.cellHeight) / g.scale
        let top = bounds.height - g.padding - CGFloat(tag.row) * h
        return CGRect(x: g.padding + CGFloat(tag.firstCol) * w, y: top - h,
                      width: CGFloat(tag.lastCol - tag.firstCol + 1) * w, height: h)
    }
}

extension TerminalSession {
    /// The image tags on screen, in `rows` or all of them. Refreshes the
    /// frame: call it outside draw.
    func visibleImageTags(rows wanted: ClosedRange<Int>? = nil) -> [PastedImageTag] {
        guard let frame = currentFrame()?.pointee, let cells = frame.cells, let text = frame.text else { return [] }
        let cols = Int(frame.cols)
        let all = 0...max(Int(frame.rows) - 1, 0)
        let rows = wanted.map { $0.clamped(to: all) } ?? all
        guard frame.rows > 0 else { return [] }
        var tags: [PastedImageTag] = []
        for row in rows {
            let line = (0..<cols).map { col -> String in
                let cell = cells[row * cols + col]
                return String(decoding: UnsafeBufferPointer(start: text + Int(cell.text_offset), count: Int(cell.text_len)), as: UTF8.self)
            }
            tags += PastedImageTag.find(inRow: line, row: row)
        }
        return tags
    }
}
