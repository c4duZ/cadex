import Darwin
import Foundation

/// The machine's memory and processor and Cadex's own memory, read every
/// 2 s, once for the whole app, and only while an item that shows them can
/// be seen in some window: with none, there is no timer at all (the
/// owner's rule for plan 17, 2026-10-21: nothing hidden may weigh).
@MainActor
public final class SystemStats {
    public struct Reading: Equatable, Sendable {
        /// Memory in use, as Activity Monitor counts it: app memory, wired
        /// and compressed.
        public var ramUsed: UInt64
        public var ramTotal: UInt64
        /// The processor busy over the last interval, 0 to 100; nil on the
        /// first reading, which has no interval yet.
        public var cpu: Double?
        /// Cadex's footprint, the number Activity Monitor shows for it.
        public var own: UInt64
    }

    public static let shared = SystemStats()
    static let interval: TimeInterval = 2

    private var watchers: [UUID: (Reading) -> Void] = [:]
    private var timer: Timer?
    private var lastTicks: (busy: UInt64, total: UInt64)?
    private(set) var last: Reading?

    /// Whether anything reads now: false means no timer.
    var isRunning: Bool { timer != nil }

    /// Starts reading for `handler` (at once, then every 2 s); the token
    /// stops it.
    public func watch(_ handler: @escaping (Reading) -> Void) -> UUID {
        let id = UUID()
        watchers[id] = handler
        if timer == nil {
            lastTicks = nil
            read()
            let timer = Timer(timeInterval: Self.interval, repeats: true) { _ in MainActor.assumeIsolated { SystemStats.shared.read() } }
            // A late tick may wait: these numbers are not urgent.
            timer.tolerance = 0.5
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        } else if let last {
            handler(last)
        }
        return id
    }

    public func stop(_ id: UUID) {
        watchers[id] = nil
        guard watchers.isEmpty else { return }
        timer?.invalidate()
        timer = nil
        last = nil
    }

    private func read() {
        let reading = Reading(ramUsed: Self.memoryUsed(), ramTotal: ProcessInfo.processInfo.physicalMemory,
                              cpu: cpuBusy(), own: Self.footprint())
        last = reading
        for handler in watchers.values { handler(reading) }
    }

    private static func memoryUsed() -> UInt64 {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        guard result == KERN_SUCCESS else { return 0 }
        let page = UInt64(getpagesize())
        let app = UInt64(stats.internal_page_count) - UInt64(min(stats.purgeable_count, stats.internal_page_count))
        return (app + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page
    }

    private func cpuBusy() -> Double? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count) }
        }
        guard result == KERN_SUCCESS else { return nil }
        let t = info.cpu_ticks
        let user = UInt64(t.0), system = UInt64(t.1), idle = UInt64(t.2), nice = UInt64(t.3)
        let ticks = (busy: user + system + nice, total: user + system + idle + nice)
        defer { lastTicks = ticks }
        guard let lastTicks, ticks.total > lastTicks.total else { return nil }
        return Double(ticks.busy - lastTicks.busy) / Double(ticks.total - lastTicks.total) * 100
    }

    private static func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }

    /// "12.4 / 16 GB"
    public static func memoryText(_ used: UInt64, of total: UInt64) -> String {
        let gb = 1_073_741_824.0
        return String(format: "%.1f / %.0f GB", Double(used) / gb, Double(total) / gb)
    }

    /// "61 MB", "1.2 GB"
    public static func sizeText(_ bytes: UInt64) -> String {
        let mb = Double(bytes) / 1_048_576
        return mb < 1024 ? String(format: "%.0f MB", mb) : String(format: "%.1f GB", mb / 1024)
    }
}
