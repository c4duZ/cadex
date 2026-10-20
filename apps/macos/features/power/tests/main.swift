import AppKit
import Checks
@testable import Power

// Tests of the power feature. Run with `make macos-test` (see
// shared/checks/Checks.swift for why this is an executable).

@MainActor
final class FakeHold: PowerHold {
    var held = false
    var display = false
    var refuse = false
    func hold(display: Bool) -> Bool {
        held = !refuse
        self.display = display
        return held
    }
    func release() { held = false }
}

let exitCode = await Checks.run([
    ("always holds until allowed to sleep, the display only when asked", {
        let hold = FakeHold()
        let power = PowerController(anyRunning: { false }, holder: hold)
        power.set(.always)
        expect(hold.held && !hold.display && power.isHolding)
        power.keepDisplayOn = true
        expect(hold.held && hold.display)
        power.set(.off)
        expect(!hold.held && !power.isHolding && power.mode == .off)
    }),
    ("running holds only while a program runs", {
        let hold = FakeHold()
        var running = false
        let power = PowerController(anyRunning: { running }, holder: hold)
        power.set(.running)
        expect(!hold.held && !power.isHolding && power.mode == .running)
        running = true
        power.check()
        expect(hold.held && power.isHolding)
        running = false
        power.check()
        expect(!hold.held && !power.isHolding && power.mode == .running)
        power.set(.off)
    }),
    ("a request the system refuses goes back to off", {
        let hold = FakeHold()
        hold.refuse = true
        let power = PowerController(anyRunning: { false }, holder: hold)
        var changes = 0
        power.onChange = { changes += 1 }
        power.set(.always)
        expect(power.mode == .off && !power.isHolding && changes == 1)
    }),
    ("each command shows only when it changes something", {
        let power = PowerController(anyRunning: { false }, holder: FakeHold())
        let commands = Dictionary(uniqueKeysWithValues: PowerCommands.all(power).map { ($0.id, $0) })
        expect(commands["power.allow-sleep"]?.unavailableReason() != nil && commands["power.keep-awake"]?.unavailableReason() == nil)
        power.set(.always)
        expect(commands["power.keep-awake"]?.unavailableReason() != nil && commands["power.allow-sleep"]?.unavailableReason() == nil)
        expect(commands["power.keep-awake-while-running"]?.unavailableReason() == nil)
        power.set(.off)
    }),
])
exit(exitCode)
