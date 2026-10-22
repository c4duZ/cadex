import CoreGraphics

/// Where a pane dragged by its header lands (docs/spec/tabs.md, "Arrastar
/// um painel"), measured on the layout as it was when the drag began: the
/// cards that show the result move, but what the pointer means does not
/// (live hit-testing on moving panes made the layout shake, 2026-10-22).
/// The zones follow what Zed, yabai and VS Code do: the sides of a pane cut
/// by its diagonals, its center and its header to swap.
struct PaneDrop: Equatable {
    /// The pane under the pointer.
    let target: Int
    /// The side the dragged pane goes to; nil swaps the two.
    let side: PaneTree.Direction?

    /// The center's half size, as a share of the content's half sizes.
    static let center: CGFloat = 0.4
    /// How far the pointer must go before the zone changes.
    static let hysteresis: CGFloat = 8

    /// The zone under `point` among `frames` (the drag's start), or nil
    /// over the dragged pane, a divider or outside.
    static func at(_ point: CGPoint, dragged: Int, frames: [Int: CGRect], header: CGFloat) -> PaneDrop? {
        guard let (target, frame) = frames.first(where: { $0.key != dragged && $0.value.contains(point) }) else { return nil }
        // The target's header never splits: it swaps, as a tab bar joins in VS Code.
        if point.y < frame.minY + header { return PaneDrop(target: target, side: nil) }
        let content = CGRect(x: frame.minX, y: frame.minY + header, width: frame.width, height: max(frame.height - header, 1))
        let nx = (point.x - content.midX) / (content.width / 2)
        let ny = (point.y - content.midY) / (content.height / 2)
        if abs(nx) < center, abs(ny) < center { return PaneDrop(target: target, side: nil) }
        // Diagonals: the larger normalized distance picks the side, so the
        // corners split evenly in wide and tall panes alike.
        if abs(nx) >= abs(ny) { return PaneDrop(target: target, side: nx < 0 ? .left : .right) }
        return PaneDrop(target: target, side: ny < 0 ? .up : .down)
    }

    /// The tree after dropping `dragged` here. A drop that would change
    /// nothing (beside its own neighbor, on the side it already is) swaps.
    func applied(to tree: PaneTree, dragged: Int) -> PaneTree {
        guard let side else { return tree.swapping(dragged, target) }
        let moved = tree.moving(dragged, beside: target, edge: side)
        return moved.shape == tree.shape ? tree.swapping(dragged, target) : moved
    }
}
