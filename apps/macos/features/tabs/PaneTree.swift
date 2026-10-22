import CoreGraphics

/// How a tab is divided into panes (docs/spec/tabs.md, "Divisões"): a
/// binary tree whose leaves are panes (by id) and whose nodes split their
/// space side by side or one above the other. Pure, so splitting, closing
/// and moving the focus are testable without views.
indirect enum PaneTree: Equatable {
    /// Side by side (⌘D) or stacked (⌘⇧D).
    enum Axis: Equatable { case horizontal, vertical }
    enum Direction { case left, right, up, down }

    case leaf(Int)
    /// `ratio` is the share of the first child, between 0 and 1.
    case split(Axis, PaneTree, PaneTree, ratio: CGFloat)

    /// The panes in reading order: left before right, top before bottom.
    var leaves: [Int] {
        switch self {
        case .leaf(let id): [id]
        case .split(_, let a, let b, _): a.leaves + b.leaves
        }
    }

    /// Splits pane `id` in two, the new pane after it, half and half.
    func splitting(_ id: Int, axis: Axis, newPane: Int) -> PaneTree {
        switch self {
        case .leaf(id): .split(axis, .leaf(id), .leaf(newPane), ratio: 0.5)
        case .leaf: self
        case .split(let ax, let a, let b, let r):
            .split(ax, a.splitting(id, axis: axis, newPane: newPane), b.splitting(id, axis: axis, newPane: newPane), ratio: r)
        }
    }

    /// Removes pane `id`; its sibling takes the space. Nil when it was the
    /// only pane.
    func removing(_ id: Int) -> PaneTree? {
        switch self {
        case .leaf(id): return nil
        case .leaf: return self
        case .split(let ax, let a, let b, let r):
            guard let newA = a.removing(id) else { return b }
            guard let newB = b.removing(id) else { return a }
            return .split(ax, newA, newB, ratio: r)
        }
    }

    /// Where each pane goes inside `rect`, with `gap` between siblings for
    /// the divider.
    func frames(in rect: CGRect, gap: CGFloat = 0) -> [Int: CGRect] {
        switch self {
        case .leaf(let id):
            return [id: rect]
        case .split(let axis, let a, let b, let ratio):
            let (first, second) = Self.divide(rect, axis: axis, ratio: ratio, gap: gap)
            return a.frames(in: first, gap: gap).merging(b.frames(in: second, gap: gap)) { x, _ in x }
        }
    }

    static func divide(_ rect: CGRect, axis: Axis, ratio: CGFloat, gap: CGFloat) -> (CGRect, CGRect) {
        switch axis {
        case .horizontal:
            let firstWidth = ((rect.width - gap) * ratio).rounded()
            let first = CGRect(x: rect.minX, y: rect.minY, width: firstWidth, height: rect.height)
            let second = CGRect(x: first.maxX + gap, y: rect.minY, width: rect.width - firstWidth - gap, height: rect.height)
            return (first, second)
        case .vertical:
            // Top first: y grows downward in the views that use this.
            let firstHeight = ((rect.height - gap) * ratio).rounded()
            let first = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: firstHeight)
            let second = CGRect(x: rect.minX, y: first.maxY + gap, width: rect.width, height: rect.height - firstHeight - gap)
            return (first, second)
        }
    }

    /// ⌘] and ⌘[: the next or previous pane in reading order, wrapping.
    func cycling(from id: Int, by step: Int) -> Int? {
        let all = leaves
        guard let i = all.firstIndex(of: id) else { return nil }
        return all[(i + step + all.count) % all.count]
    }

    /// ⌘⌥ + arrow: the pane next to `id` in that direction, the one facing
    /// it most, nearest first. Nil at the edge.
    func neighbor(of id: Int, _ direction: Direction, in rect: CGRect) -> Int? {
        let frames = frames(in: rect)
        guard let from = frames[id] else { return nil }
        let candidates = frames.filter { other, frame in
            guard other != id else { return false }
            switch direction {
            case .left: return frame.maxX <= from.minX + 1 && overlap(frame, from, vertical: true) > 0
            case .right: return frame.minX >= from.maxX - 1 && overlap(frame, from, vertical: true) > 0
            case .up: return frame.maxY <= from.minY + 1 && overlap(frame, from, vertical: false) > 0
            case .down: return frame.minY >= from.maxY - 1 && overlap(frame, from, vertical: false) > 0
            }
        }
        return candidates.min { a, b in
            let da = distance(a.value, from, direction), db = distance(b.value, from, direction)
            if da != db { return da < db }
            let vertical = direction == .left || direction == .right
            return overlap(a.value, from, vertical: vertical) > overlap(b.value, from, vertical: vertical)
        }?.key
    }

    /// The same tree with every pane in a row (or a column) the same size:
    /// each split gives its sides space by how many panes they put side by
    /// side in its direction. Splitting the focused pane in half left three
    /// terminals at 50, 25 and 25 % (owner, 2026-10-19).
    func balanced() -> PaneTree {
        guard case .split(let axis, let a, let b, _) = self else { return self }
        let wa = a.count(along: axis), wb = b.count(along: axis)
        return .split(axis, a.balanced(), b.balanced(), ratio: CGFloat(wa) / CGFloat(wa + wb))
    }

    /// Balanced, except that a pane docked at one side of the outermost
    /// split keeps its share: an opened file keeps half the tab while the
    /// panes beside it split and close (issue #5, 2026-10-21).
    func balanced(keeping docked: Int?) -> PaneTree {
        guard let docked, case .split(let axis, let a, let b, let ratio) = self else { return balanced() }
        if a == .leaf(docked) { return .split(axis, a, b.balanced(), ratio: ratio) }
        if b == .leaf(docked) { return .split(axis, a.balanced(), b, ratio: ratio) }
        return balanced()
    }

    /// `pane` docked beside the whole tree, half and half: first (left) or
    /// second (right).
    func docking(_ pane: Int, first: Bool) -> PaneTree {
        first ? .split(.horizontal, .leaf(pane), self, ratio: 0.5) : .split(.horizontal, self, .leaf(pane), ratio: 0.5)
    }

    /// How many panes this subtree lines up along `axis`: a split the same
    /// way adds its sides; anything else is one slot.
    private func count(along axis: Axis) -> Int {
        guard case .split(let own, let a, let b, _) = self, own == axis else { return 1 }
        return a.count(along: axis) + b.count(along: axis)
    }

    /// Sets the ratio of the split node at `path` (false: first child,
    /// true: second child, from the root). Dragging a divider does this.
    /// The tree with pane `id` moved to the `edge` side of `target`,
    /// halving the target's space (a pane header dragged onto another).
    func moving(_ id: Int, beside target: Int, edge: Direction) -> PaneTree {
        guard id != target, leaves.contains(id), let rest = removing(id), rest.leaves.contains(target) else { return self }
        return rest.replacing(target) {
            switch edge {
            case .left: .split(.horizontal, .leaf(id), .leaf(target), ratio: 0.5)
            case .right: .split(.horizontal, .leaf(target), .leaf(id), ratio: 0.5)
            case .up: .split(.vertical, .leaf(id), .leaf(target), ratio: 0.5)
            case .down: .split(.vertical, .leaf(target), .leaf(id), ratio: 0.5)
            }
        }
    }

    private func replacing(_ id: Int, with node: () -> PaneTree) -> PaneTree {
        switch self {
        case .leaf(id): node()
        case .leaf: self
        case .split(let axis, let a, let b, let ratio): .split(axis, a.replacing(id, with: node), b.replacing(id, with: node), ratio: ratio)
        }
    }

    /// The same layout whatever the ratios: what a drop changes or not.
    var shape: PaneTree {
        guard case .split(let axis, let a, let b, _) = self else { return self }
        return .split(axis, a.shape, b.shape, ratio: 0.5)
    }

    /// The tree with panes `a` and `b` in each other's place.
    func swapping(_ a: Int, _ b: Int) -> PaneTree {
        switch self {
        case .leaf(a): .leaf(b)
        case .leaf(b): .leaf(a)
        case .leaf: self
        case .split(let axis, let x, let y, let ratio): .split(axis, x.swapping(a, b), y.swapping(a, b), ratio: ratio)
        }
    }

    /// The side of `frame` nearest to `point`, by its share of the width
    /// or height: where a pane dropped there goes.
    static func dropEdge(at point: CGPoint, in frame: CGRect) -> Direction {
        let x = (point.x - frame.minX) / max(frame.width, 1)
        let y = (point.y - frame.minY) / max(frame.height, 1)
        let sides: [(Direction, CGFloat)] = [(.left, x), (.right, 1 - x), (.up, y), (.down, 1 - y)]
        return sides.min { $0.1 < $1.1 }!.0
    }

    func settingRatio(_ ratio: CGFloat, at path: [Bool]) -> PaneTree {
        guard case .split(let ax, let a, let b, let r) = self else { return self }
        guard let step = path.first else { return .split(ax, a, b, ratio: ratio) }
        let rest = Array(path.dropFirst())
        return step ? .split(ax, a, b.settingRatio(ratio, at: rest), ratio: r)
                    : .split(ax, a.settingRatio(ratio, at: rest), b, ratio: r)
    }
}

private func overlap(_ a: CGRect, _ b: CGRect, vertical: Bool) -> CGFloat {
    vertical ? min(a.maxY, b.maxY) - max(a.minY, b.minY) : min(a.maxX, b.maxX) - max(a.minX, b.minX)
}

private func distance(_ a: CGRect, _ from: CGRect, _ direction: PaneTree.Direction) -> CGFloat {
    switch direction {
    case .left: from.minX - a.maxX
    case .right: a.minX - from.maxX
    case .up: from.minY - a.maxY
    case .down: a.minY - from.maxY
    }
}
