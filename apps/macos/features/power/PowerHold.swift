import Foundation
import Strings
import IOKit.pwr_mgt

/// What keeps the computer awake: the system's own power requests (IOKit
/// assertions), which the system drops by itself if Cadex quits or
/// crashes, so the computer is never left held. Not the `caffeinate`
/// command (docs/spec/power.md).
@MainActor
protocol PowerHold: AnyObject {
    /// Holds the computer (and the display, if asked); false when the
    /// system refused.
    func hold(display: Bool) -> Bool
    func release()
}

@MainActor
final class SystemPowerHold: PowerHold {
    private var ids: [IOPMAssertionID] = []
    private static let reason = T("Cadex: keeping the computer awake", "Cadex: manter o computador acordado") as CFString

    /// PreventSystemSleep keeps a Mac on the power adapter running with
    /// the lid closed, as `caffeinate -s` does; on battery macOS sleeps on
    /// closing the lid whatever is asked (only `pmset disablesleep`, as
    /// root, overrides it). PreventUserIdleSystemSleep covers idle sleep on
    /// battery; the display one keeps the screen on.
    func hold(display: Bool) -> Bool {
        release()
        var types = [kIOPMAssertionTypePreventSystemSleep, kIOPMAssertionTypePreventUserIdleSystemSleep]
        if display { types.append(kIOPMAssertionTypePreventUserIdleDisplaySleep) }
        for type in types {
            var id = IOPMAssertionID(0)
            if IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), Self.reason, &id) == kIOReturnSuccess {
                ids.append(id)
            }
        }
        return !ids.isEmpty
    }

    func release() {
        ids.forEach { IOPMAssertionRelease($0) }
        ids = []
    }
}
