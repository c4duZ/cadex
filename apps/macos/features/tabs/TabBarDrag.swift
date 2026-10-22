import AppKit

/// Dragging a tab along the strip (docs/spec/tabs.md, "Abas"): the dragged
/// tab follows the pointer on top of the others, and the others slide to
/// their new places as it passes them (0.15 s), as the sidebar's icons do;
/// it lands where its middle is. Only the strip moves: the tabs reorder on
/// release (the owner saw the dragged tab hold still and the order change
/// only when let go, 2026-10-22). While a tab is held the window cannot be
/// moved: in the title bar, macOS took the drag to move the whole window.
extension TabBarView {
    static let slideDuration: CFTimeInterval = 0.15

    func beginDrag(_ id: Int, at x: CGFloat) {
        dragging = (id, x, 0)
        dragOrder = items.map(\.id)
        slideFrom = [:]
        window?.isMovable = false
    }

    func moveDrag(to x: CGFloat) {
        guard var drag = dragging else { return }
        drag.offset = x - drag.startX
        dragging = drag
        let order = dropOrder()
        if order != dragOrder { slide(to: order) }
        needsDisplay = true
    }

    func endDrag() {
        defer {
            dragging = nil
            slideTimer?.invalidate()
            slideTimer = nil
            slideFrom = [:]
            window?.isMovable = true
            needsDisplay = true
        }
        guard let drag = dragging, abs(drag.offset) > 4, let from = items.firstIndex(where: { $0.id == drag.id }),
              let to = dropOrder().firstIndex(of: drag.id), to != from else { return }
        onMove?(drag.id, to)
    }

    /// The order if the dragged tab were dropped now: at the slot its middle is over.
    func dropOrder() -> [Int] {
        guard let drag = dragging, let from = items.firstIndex(where: { $0.id == drag.id }) else { return items.map(\.id) }
        let center = frame(at: from).midX + drag.offset
        let to = frames.lastIndex { $0.minX <= center } ?? 0
        var order = items.map(\.id)
        order.remove(at: from)
        order.insert(drag.id, at: min(max(to, 0), order.count))
        return order
    }

    /// The other tabs start from where they show now toward their new slots.
    private func slide(to order: [Int]) {
        for id in order where id != dragging?.id { slideFrom[id] = shownX(id) }
        dragOrder = order
        slideStart = CACurrentMediaTime()
        slideTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.needsDisplay = true
                if CACurrentMediaTime() - self.slideStart >= Self.slideDuration {
                    self.slideFrom = [:]
                    self.slideTimer?.invalidate()
                    self.slideTimer = nil
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        slideTimer = timer
    }

    /// Where tab `id` shows now: on its way from where it was to its slot.
    private func shownX(_ id: Int) -> CGFloat {
        let all = frames
        guard let slot = dragOrder.firstIndex(of: id), slot < all.count else { return 0 }
        let target = all[slot].minX
        guard let start = slideFrom[id] else { return target }
        let t = min(max((CACurrentMediaTime() - slideStart) / Self.slideDuration, 0), 1)
        let eased = 1 - pow(1 - t, 3)
        return start + (target - start) * CGFloat(eased)
    }

    /// The others in their sliding places, then the dragged one on top,
    /// under the pointer, kept inside the strip.
    func drawWhileDragging() {
        guard let drag = dragging, let from = items.firstIndex(where: { $0.id == drag.id }) else { return }
        let all = frames
        for item in items where item.id != drag.id {
            guard let slot = dragOrder.firstIndex(of: item.id), slot < all.count else { continue }
            var rect = all[slot]
            rect.origin.x = shownX(item.id)
            drawTab(item, in: rect, hovered: false)
        }
        var rect = frame(at: from)
        rect.origin.x = min(max(rect.minX + drag.offset, 0), bounds.width - rect.width)
        drawTab(items[from], in: rect, hovered: true)
    }
}
