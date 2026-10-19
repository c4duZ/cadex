import AppKit

/// ⌘F on the terminal: shows the find bar and drives the core's search.
extension TerminalView {
    /// Space between the bar and the view's top-right corner, in points.
    private static let findBarInset: CGFloat = 10

    func showFindBar() {
        let bar = findBar ?? makeFindBar()
        bar.isHidden = false
        bar.focus()
        if !bar.text.isEmpty { session?.searchStart(bar.text) }
        refreshFindCounts()
    }

    func closeFindBar() {
        guard let bar = findBar, !bar.isHidden else { return }
        bar.isHidden = true
        session?.searchStop()
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    /// Keeps "3 de 12" current while output arrives.
    func refreshFindCounts() {
        guard let bar = findBar, !bar.isHidden, let session else { return }
        let counts = session.searchCounts()
        bar.showCounts(total: counts.total, current: counts.current)
    }

    private func makeFindBar() -> TerminalFindBar {
        let bar = TerminalFindBar()
        bar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bar)
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: topAnchor, constant: Self.findBarInset),
            bar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.findBarInset),
        ])
        bar.onChange = { [weak self] text in
            self?.session?.searchStart(text)
            self?.findMoved()
        }
        bar.onNext = { [weak self] in
            self?.session?.searchSelect(forward: true)
            self?.findMoved()
        }
        bar.onPrevious = { [weak self] in
            self?.session?.searchSelect(forward: false)
            self?.findMoved()
        }
        bar.onClose = { [weak self] in self?.closeFindBar() }
        findBar = bar
        return bar
    }

    private func findMoved() {
        refreshFindCounts()
        needsDisplay = true
    }
}
