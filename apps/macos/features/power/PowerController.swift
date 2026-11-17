import Foundation

/// Entry point of the power feature (docs/spec/power.md): keeps the
/// computer awake always, or only while a terminal runs a program, until
/// turned off or Cadex closes. One for the app, shared by every window.
@MainActor
public final class PowerController {
    public enum Mode: String, CaseIterable, Sendable {
        case off, always, running
    }

    public private(set) var mode: Mode = .off
    /// Whether the computer is held now: always, or running with a program
    /// running. False while running mode waits.
    public private(set) var isHolding = false
    /// power.keepDisplayOn: the screen stays on too. Counts at once.
    public var keepDisplayOn = false {
        didSet { if keepDisplayOn != oldValue, isHolding { holdNow() } }
    }
    /// What toggle() turns on: power.mode in settings.json.
    public var defaultMode: Mode = .always
    /// The mode or the hold changed (the title bar's icon).
    public var onChange: (() -> Void)?

    private let anyRunning: () -> Bool
    private let holder: PowerHold
    private var timer: Timer?
    /// How often running mode looks at the terminals: a program that ends
    /// lets the computer sleep within this.
    static let checkInterval: TimeInterval = 5

    /// anyRunning: whether a terminal in any window runs a program.
    public convenience init(anyRunning: @escaping () -> Bool) {
        self.init(anyRunning: anyRunning, holder: SystemPowerHold())
    }

    init(anyRunning: @escaping () -> Bool, holder: PowerHold) {
        self.anyRunning = anyRunning
        self.holder = holder
    }

    public func set(_ mode: Mode) {
        guard mode != self.mode else { return }
        self.mode = mode
        timer?.invalidate()
        timer = nil
        if mode == .running {
            timer = Timer.scheduledTimer(withTimeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.check() }
            }
        }
        check(force: true)
    }

    /// ⇧⌘A, the coffee and the menu bar symbol: off turns on the default
    /// mode, on turns off (owner, 2026-10-20).
    public func toggle() {
        set(mode == .off ? defaultMode : .off)
    }

    /// The jobs of other features holding the computer awake now (an
    /// automation running, docs/spec/power.md): their own power request,
    /// apart from the mode, so the coffee does not change.
    public private(set) var jobs: Set<String> = []
    private lazy var jobHolder: PowerHold = makeJobHolder()
    var makeJobHolder: () -> PowerHold = { SystemPowerHold() }

    /// Keeps the computer awake while the job runs; false when the system refused.
    @discardableResult
    public func hold(job: String) -> Bool {
        let first = jobs.isEmpty
        jobs.insert(job)
        return first ? jobHolder.hold(display: false) : true
    }

    /// The job ended: the request goes with the last one.
    public func release(job: String) {
        guard jobs.remove(job) != nil, jobs.isEmpty else { return }
        jobHolder.release()
    }

    /// Holds or releases as the mode and the terminals say now.
    func check(force: Bool = false) {
        let should = mode == .always || (mode == .running && anyRunning())
        guard force || should != isHolding else { return }
        if should {
            holdNow()
        } else {
            holder.release()
            isHolding = false
        }
        onChange?()
    }

    private func holdNow() {
        isHolding = holder.hold(display: keepDisplayOn)
        // Refused by the system: back to off, without the icon (spec).
        if !isHolding, mode == .always { mode = .off }
    }
}
