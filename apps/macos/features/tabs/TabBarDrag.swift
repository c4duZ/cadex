import AppKit

/// Dragging a tab along the strip (docs/spec/tabs.md, "Abas"): the dragged
/// tab follows the pointer on top of the others, and the others slide to
/// their new places as it passes them (0.15 s), as the sidebar's icons do;
/// it lands where its middle is. Only the strip moves: the tabs reorder on
/// release (the owner saw the dragged tab hold still and the order change
/// only when let go, 2026-10-22). The window does not move meanwhile:
/// TitleBarHold locks it while the pointer is on the strip.
extension TabBarView {
    static let slideDuration: CFTimeInterval = 0.15

    func beginDrag(_ id: Int, at x: CGFloat) {
        dragging = (id, x, 0)
        dragOrder = items.map(\.id)
        slideFrom = [:]
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
            needsDisplay = true
        }
        guard let drag = dragging, abs(drag.offset) > 4, let from = items.firstIndex(where: { $0.id == drag.id }),
              let to = dropOrder().firstIndex(of: drag.id), to != from else { return }
        onMove?(drag.id, to)
    }

    /// The order if the dragged tab were dropped now: at the slot its middle is over.
    func dropOrder() -> [Int] {
        guard let drag = dragging, let from = items.firstIndex(where: { $0.id == drag.id }) else { return items.map(\.id) }
        // Tabs are as wide as their titles: the dragged one goes past each other tab whose middle
        // its own middle has crossed (counting by left edges dropped a wide tab a slot early).
        let all = frames
        let center = all[from].midX + drag.offset
        var order = items.map(\.id)
        order.remove(at: from)
        let others = items.indices.filter { $0 != from }
        let to = others.filter { all[$0].midX < center }.count
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
        guard let target = positions(dragOrder)[id] else { return 0 }
        guard let start = slideFrom[id] else { return target }
        let t = min(max((CACurrentMediaTime() - slideStart) / Self.slideDuration, 0), 1)
        let eased = 1 - pow(1 - t, 3)
        return start + (target - start) * CGFloat(eased)
    }

    /// The others in their sliding places, then the dragged one on top,
    /// under the pointer, kept inside the strip.
    func drawWhileDragging() {
        guard let drag = dragging, let from = items.firstIndex(where: { $0.id == drag.id }) else { return }
        // Tabs are as wide as their titles: each keeps its own width at its sliding place.
        let widths = widths
        for item in items where item.id != drag.id {
            let rect = NSRect(x: shownX(item.id), y: 0, width: widths[item.id] ?? 0, height: bounds.height)
            drawTab(item, in: rect, hovered: false)
        }
        var rect = frame(at: from)
        rect.origin.x = min(max(rect.minX + drag.offset, 0), bounds.width - rect.width)
        drawTab(items[from], in: rect, hovered: true)
    }
}
