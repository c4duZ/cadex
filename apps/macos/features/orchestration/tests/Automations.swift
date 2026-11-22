import Checks
import Foundation
@testable import Orchestration

// Scheduled automations (plan 24 E): the agenda, the missed runs, the
// LaunchAgent's plist, the checks before a run and its history.

let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

func at(_ text: String) -> Date {
    let format = DateFormatter()
    format.dateFormat = "yyyy-MM-dd HH:mm"
    format.timeZone = TimeZone(identifier: "UTC")
    return format.date(from: text)!
}

func automation(_ recurrence: Recurrence, enabledAt: String = "2026-11-16 08:00", missed: MissedRun = .runOnWake) -> Automation {
    var a = Automation(id: "a1", name: "nightly", prompt: "check \"it\" $(x)", recurrence: recurrence, target: .folder("/repo"),
                       agent: AgentChoice(account: "/acct/bkdg", model: "haiku"), permissionMode: "acceptEdits", allowedTools: ["Read", " Bash(git:*) "],
                       caps: Caps(budgetUsd: 0.5, maxMinutes: 5))
    a.missed = missed
    a.enabled = true
    a.enabledAt = at(enabledAt)
    return a
}

let automationTests: [(name: String, body: Checks.Body)] = [
    ("next: weekdays skip the weekend, every N hours from midnight, every N minutes from the hour, once only ahead", {
        // 2026-11-20 is a Friday.
        expect(AutomationSchedule.next(.weekdays(hour: 9, minute: 0), after: at("2026-11-20 10:00"), calendar: utc) == at("2026-11-23 09:00"))
        expect(AutomationSchedule.next(.daily(hour: 9, minute: 30), after: at("2026-11-20 09:30"), calendar: utc) == at("2026-11-21 09:30"))
        expect(AutomationSchedule.next(.everyHours(4), after: at("2026-11-20 09:10"), calendar: utc) == at("2026-11-20 12:00"))
        expect(AutomationSchedule.next(.everyHours(7), after: at("2026-11-20 22:00"), calendar: utc) == at("2026-11-21 00:00"), "an uneven step restarts at midnight")
        expect(AutomationSchedule.next(.everyMinutes(2), after: at("2026-11-20 09:59"), calendar: utc) == at("2026-11-20 10:00"))
        expect(AutomationSchedule.next(.everyMinutes(2), after: at("2026-11-20 10:00"), calendar: utc) == at("2026-11-20 10:02"))
        expect(AutomationSchedule.next(.once(at("2026-11-20 10:00")), after: at("2026-11-20 10:00"), calendar: utc) == nil)
    }),
    ("due: on time runs; several missed become one; a missed one is skipped when so marked; a running one is still running", {
        let a = automation(.everyMinutes(2))
        expect(AutomationSchedule.due(a, lastScheduled: nil, running: false, now: at("2026-11-16 08:01"), calendar: utc) == .nothing)
        expect(AutomationSchedule.due(a, lastScheduled: nil, running: false, now: at("2026-11-16 08:02"), calendar: utc) == .run(at("2026-11-16 08:02")))
        expect(AutomationSchedule.due(a, lastScheduled: at("2026-11-16 08:02"), running: false, now: at("2026-11-16 08:03"), calendar: utc) == .nothing)
        expect(AutomationSchedule.due(a, lastScheduled: at("2026-11-16 08:02"), running: false, now: at("2026-11-16 09:00"), calendar: utc) == .run(at("2026-11-16 09:00")))
        expect(AutomationSchedule.due(a, lastScheduled: at("2026-11-16 08:02"), running: false, now: at("2026-11-16 08:59"), calendar: utc) == .run(at("2026-11-16 08:58")),
               "asleep for an hour: one run, for the latest time")
        let skipping = automation(.daily(hour: 9, minute: 0), missed: .skip)
        expect(AutomationSchedule.due(skipping, lastScheduled: nil, running: false, now: at("2026-11-16 12:00"), calendar: utc) == .skip(at("2026-11-16 09:00"), "missed"))
        expect(AutomationSchedule.due(skipping, lastScheduled: nil, running: false, now: at("2026-11-16 09:01"), calendar: utc) == .run(at("2026-11-16 09:00")), "within the grace")
        expect(AutomationSchedule.due(a, lastScheduled: nil, running: true, now: at("2026-11-16 08:04"), calendar: utc) == .skip(at("2026-11-16 08:04"), "still running"))
        var off = a
        off.enabled = false
        expect(AutomationSchedule.due(off, lastScheduled: nil, running: false, now: at("2026-11-16 09:00"), calendar: utc) == .nothing)
    }),
    ("the LaunchAgent: launchd's dates, the plist without KeepAlive or RunAtLoad, written and loaded, removed with no date", {
        expect(AutomationSchedule.launchdDates(.weekdays(hour: 9, minute: 0)) == (1...5).map { ["Weekday": $0, "Hour": 9, "Minute": 0] })
        expect(AutomationSchedule.launchdDates(.everyMinutes(15)) == [["Minute": 0], ["Minute": 15], ["Minute": 30], ["Minute": 45]])
        expect(AutomationSchedule.launchdDates(.everyHours(8)).count == 3)
        let dir = tempDir()
        defer { try? fm.removeItem(atPath: dir) }
        var calls: [[String]] = []
        var agent = AutomationAgent(folder: dir, label: "test.cadex.automations")
        agent.launchctl = { calls.append($0); return true }
        let plist = agent.plist(cadex: "/H/cadex", dates: [["Minute": 0], ["Minute": 0], ["Hour": 9, "Minute": 0]], environment: ["CADEX_APP_BIN": "/x"])
        expect(plist["KeepAlive"] == nil && plist["RunAtLoad"] == nil && plist["StartInterval"] == nil)
        expect((plist["ProgramArguments"] as? [String]) == ["/H/cadex", "automations", "due"])
        expect((plist["StartCalendarInterval"] as? [[String: Int]])?.count == 2, "repeats dropped")
        expect(agent.sync(cadex: "/H/cadex", dates: [["Minute": 0]], environment: [:]) == nil && agent.isInstalled)
        expect(calls.last?.first == "bootstrap" && calls.last?.last == agent.path, "\(calls)")
        expect(agent.sync(cadex: "/H/cadex", dates: [], environment: [:]) == nil && !agent.isInstalled, "the last one off removes it")
        expect(calls.last?.first == "bootout")
        expect(agent.sync(cadex: nil, dates: [["Minute": 0]], environment: [:]) != nil, "no cadex, no agent")
    }),
    ("before a run: off, prompt, folder, trust, and the API key unless on the subscription; the words after claude", {
        var a = automation(.daily(hour: 9, minute: 0))
        let ok = AutomationLaunch.check(a, enabled: true, folderExists: { _ in true }, trusts: { _, _ in true }, hasApiKeyHelper: { _ in true })
        expect(ok == nil)
        expect(AutomationLaunch.check(a, enabled: false, folderExists: { _ in true }, trusts: { _, _ in true }, hasApiKeyHelper: { _ in true }) == .off)
        expect(AutomationLaunch.check(a, enabled: true, folderExists: { _ in false }, trusts: { _, _ in true }, hasApiKeyHelper: { _ in true }) == .noFolder("/repo"))
        expect(AutomationLaunch.check(a, enabled: true, folderExists: { _ in true }, trusts: { _, _ in false }, hasApiKeyHelper: { _ in true }) == .notTrusted("bkdg"))
        expect(AutomationLaunch.check(a, enabled: true, folderExists: { _ in true }, trusts: { _, _ in true }, hasApiKeyHelper: { _ in false }) == .noApiKey("bkdg"))
        a.useSubscription = true
        expect(AutomationLaunch.check(a, enabled: true, folderExists: { _ in true }, trusts: { _, _ in true }, hasApiKeyHelper: { _ in false }) == nil)
        expect(AutomationLaunch.arguments(a) == ["--model", "haiku", "--permission-mode=acceptEdits", "--allowedTools=Read,Bash(git:*)"], "\(AutomationLaunch.arguments(a))")
        a.permissionMode = "default"
        a.allowedTools = []
        expect(AutomationLaunch.arguments(a) == ["--model", "haiku", "--permission-mode=default"], "default is said too")
        let dir = tempDir()
        defer { try? fm.removeItem(atPath: dir) }
        expect(!AutomationLaunch.hasApiKeyHelper(configDir: dir))
        try Data(#"{"apiKeyHelper": "~/bin/key"}"#.utf8).write(to: URL(fileURLWithPath: dir + "/settings.json"))
        expect(AutomationLaunch.hasApiKeyHelper(configDir: dir))
    }),
    ("its history: turned on from now, a run started and finished, a skipped time, newest first with the result", {
        let book = AutomationBook(store: try OrchestrationStore(path: ":memory:"), folder: NSTemporaryDirectory() + "cadex-automations-" + UUID().uuidString)
        var a = automation(.everyMinutes(2))
        a.enabled = false
        try book.save(a)
        try book.turn(a.id, on: true, now: at("2026-11-16 10:00"))
        expect(try book.automation(a.id)?.enabledAt == at("2026-11-16 10:00") && book.enabled().count == 1)
        let run = try book.start(a, scheduledAt: at("2026-11-16 10:02"), now: at("2026-11-16 10:02"))
        expect(try book.running(a.id)?.id == run.id)
        try book.skip(a.id, at: at("2026-11-16 10:04"), reason: "still running", now: at("2026-11-16 10:04"))
        try book.finish(run.id, automation: a.id, result: .hitTheCap, cost: 0.6, now: at("2026-11-16 10:07"))
        expect(try book.running(a.id) == nil && book.lastScheduled(a.id) == at("2026-11-16 10:04"))
        let lines = AutomationLines.make(try book.history(of: a.id))
        expect(lines.map(\.result) == ["Skipped: still running", "Hit the cap"] && lines[1].text.hasSuffix("US$ 0.60"), "\(lines)")
        expect(NewAutomationForm.parse(kind: 3, text: "2") == .everyMinutes(2) && NewAutomationForm.parse(kind: 0, text: "25:00") == nil)
        expect(AutomationLaunch.taskName(a, at: at("2026-11-16 10:02")).hasPrefix("nightly-20261116-"))
    }),
    ("automations are JSON files: one per id, readable, edited by hand, a broken one left out, the database's moved once", {
        let fm = FileManager.default
        let dir = NSTemporaryDirectory() + "cadex-automations-" + UUID().uuidString
        defer { try? fm.removeItem(atPath: dir) }
        let store = try OrchestrationStore(path: ":memory:")
        // An automation from before the files, still a row: it moves to a file and out of the table.
        var old = automation(.daily(hour: 9, minute: 30))
        old.id = "old"
        try store.put(.automations, id: "old", old)
        let book = AutomationBook(store: store, folder: dir)
        let rows: [Automation] = try store.all(.automations)
        expect(fm.fileExists(atPath: dir + "/old.json") && rows.isEmpty, "moved to its file")
        expect(try book.automation("old") == old, "the file reads back the same")
        let text = try String(contentsOfFile: dir + "/old.json", encoding: .utf8)
        expect(text.contains("\"enabledAt\" : \"2026-11-16T") && text.contains("\"daily\""), "dates in ISO 8601, keys a person reads: \(text)")
        // By hand: a new file with no id takes its name; a broken one is left out; the others count.
        var hand = old
        hand.name = "by hand"
        var object = try JSONSerialization.jsonObject(with: AutomationFiles.encoder.encode(hand)) as! [String: Any]
        object["id"] = nil
        try JSONSerialization.data(withJSONObject: object).write(to: URL(fileURLWithPath: dir + "/weekly-review.json"))
        try Data("{ not json".utf8).write(to: URL(fileURLWithPath: dir + "/broken.json"))
        let all = try book.automations()
        expect(Set(all.map(\.id)) == ["old", "weekly-review"] && book.files.get("weekly-review")?.name == "by hand", "\(all.map(\.id))")
        try book.delete("weekly-review")
        expect(!fm.fileExists(atPath: dir + "/weekly-review.json") && book.files.get("../x") == nil, "deleted; a name outside the folder is not read")
    }),
    ("the agents' settings guide's automation example is an automation that reads from its file", {
        let guidePath = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../../core/features/agent-tools/guides/settings.md").standardized.path
        let guide = try String(contentsOfFile: guidePath, encoding: .utf8)
        guard let section = guide.range(of: "## Automations"), let start = guide.range(of: "```json\n", range: section.upperBound..<guide.endIndex),
              let end = guide.range(of: "```", range: start.upperBound..<guide.endIndex) else { return expect(false, "no example") }
        let dir = NSTemporaryDirectory() + "cadex-automations-" + UUID().uuidString
        defer { try? FileManager.default.removeItem(atPath: dir) }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try Data(guide[start.upperBound..<end.lowerBound].utf8).write(to: URL(fileURLWithPath: dir + "/morning-triage.json"))
        let read = AutomationFiles(folder: dir).get("morning-triage")
        expect(read?.recurrence == .weekdays(hour: 9, minute: 0) && read?.target == .folder("/Users/me/code/app") && read?.enabled == false,
               "\(String(describing: read))")
    }),
]
