import Checks
import AppKit
import Customize
import Icons
import Foundation
@testable import StatusBar

// Tests of the status-bar feature. Run with `make macos-test` (see
// shared/checks/Checks.swift for why this is an executable).

let exitCode = await Checks.run([
    ("an item that grows makes the next one slide to its place, not jump", {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 30), styleMask: [.borderless], backing: .buffered, defer: false)
        let stack = SlidingStack()
        stack.frame = NSRect(x: 0, y: 0, width: 600, height: 30)
        window.contentView?.addSubview(stack)
        let first = StatusLabel(icon: nil), second = StatusLabel(icon: nil)
        first.text = "main"
        second.text = "bhband"
        stack.addArrangedSubview(first)
        stack.addArrangedSubview(second)
        stack.layoutSubtreeIfNeeded()
        let before = second.frame.minX
        first.text = "feature/a-very-long-branch-name"
        stack.layoutSubtreeIfNeeded()
        expect(second.frame.minX > before, "\(before) → \(second.frame.minX)")
        expect(second.layer?.animation(forKey: "slide") != nil, "it slides from where it was")
        first.maxTextWidth = 60
        stack.layoutSubtreeIfNeeded()
        expect(first.frame.width < 90, "a long text is capped: \(first.frame.width)")
    }),
    ("a folder under home starts at Home", {
        let titles = Breadcrumb.segments(of: "/Users/cadu/Trabalho/cadex", home: "/Users/cadu").map(\.title)
        expect(titles == ["Home", "Trabalho", "cadex"], "\(titles)")
        let paths = Breadcrumb.segments(of: "/Users/cadu/Trabalho", home: "/Users/cadu").map(\.path)
        expect(paths == ["/Users/cadu", "/Users/cadu/Trabalho"], "\(paths)")
    }),
    ("a folder elsewhere starts at /", {
        let segments = Breadcrumb.segments(of: "/private/tmp", home: "/Users/cadu")
        expect(segments.map(\.title) == ["/", "private", "tmp"])
        expect(segments.last?.path == "/private/tmp")
        expect(Breadcrumb.segments(of: "/Users/cadu", home: "/Users/cadu").map(\.title) == ["Home"])
    }),
    ("long paths keep the root and the current folder", {
        let segments = Breadcrumb.segments(of: "/a/b/c/d/e/f/g/h", home: "/Users/cadu", maxSegments: 5)
        expect(segments.map(\.title) == ["/", "…", "f", "g", "h"], "\(segments.map(\.title))")
        expect(segments[1].path == nil)
    }),
    ("subfolders are listed by name, hidden ones left out", {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cadex-bc-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["b", "a", ".oculta"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        try Data().write(to: root.appendingPathComponent("arquivo.txt"))
        expect(Breadcrumb.subfolders(of: root.path) == ["a", "b"])
        expect(Breadcrumb.subfolders(of: "/nao/existe") == nil)
    }),
    ("the saved sides keep their order and drop unknown and repeated ids", {
        let placed = StatusBarLayout.placed(left: ["folder", "nope"], right: ["ram", "folder", "cpu"], known: ["folder", "environment", "ram", "cpu"])
        expect(placed.left == ["folder"] && placed.right == ["ram", "cpu"] && placed.problems.count == 2, "\(placed)")
    }),
    ("showing an item puts it at the end of its usual side; hiding takes it from either", {
        let shown = StatusBarLayout.toggled(left: ["folder"], right: ["environment"], "ram", side: .right)
        expect(shown.left == ["folder"] && shown.right == ["environment", "ram"])
        let hidden = StatusBarLayout.toggled(left: ["folder", "ram"], right: [], "ram", side: .right)
        expect(hidden.left == ["folder"] && hidden.right.isEmpty)
    }),
    ("with nothing set the bar is the one from before: folder left, environment right", {
        let bar = StatusBarView()
        expect(bar.left == ["folder"] && bar.right == ["environment"], "\(bar.left) \(bar.right)")
    }),
    ("Customize lists Left and Right with the hidden ones under their side, and gives the sides back", {
        let bar = StatusBarView()
        bar.add(SystemItems.all {})
        bar.setLayout(left: ["folder", "cpu"], right: ["environment"])
        let entries = StatusBarLayout.entries(left: bar.left, right: bar.right, catalog: bar.catalogItems)
        let sections = CustomizeLayout.sections(entries).map { $0.map(\.id) }
        expect(sections == [["folder", "cpu"], ["environment", "ram", "cadexMemory"]], "\(sections)")
        let back = StatusBarLayout.sides(from: entries)
        expect(back.left == ["folder", "cpu"] && back.right == ["environment"], "\(back)")
    }),
    ("nothing hidden weighs: no stats timer for hidden items or a bar off screen", {
        let bar = StatusBarView()
        bar.add(SystemItems.all {})
        expect(!SystemStats.shared.isRunning, "hidden RAM, CPU and memory read nothing")
        bar.setLayout(left: ["folder"], right: ["ram", "cpu"])
        expect(!SystemStats.shared.isRunning, "shown, but in no window on screen: still nothing")
        let item = bar.catalogItems.first { $0.id == "ram" }
        expect(item?.isVisible == false)
    }),
    ("the ports a process group listens on, read from the kernel", {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0
        _ = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        listen(fd, 1)
        var bound = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &bound) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) } }
        let port = UInt16(bigEndian: bound.sin_port)
        let ports = ListeningPorts.ports(inGroups: [getpgrp()])
        expect(ports.contains(port), "\(port) in \(ports)")
        expect(ListeningPorts.ports(inGroups: [0, -1]).isEmpty)
    }),
    ("a closing window stops every item's reading", {
        let bar = StatusBarView()
        var seen: [Bool] = []
        let item = StatusItem(id: "probe", title: "Probe", view: NSView())
        item.onVisible = { seen.append($0) }
        bar.add([item])
        bar.setLayout(left: [], right: ["probe"])
        item.setVisible(true)
        bar.stopReading()
        expect(seen == [true, false] && !item.isVisible, "\(seen)")
    }),
    ("the stats run while something watches and stop with the last one", {
        var readings: [SystemStats.Reading] = []
        let token = SystemStats.shared.watch { readings.append($0) }
        expect(SystemStats.shared.isRunning && readings.count == 1)
        let first = readings.first
        expect((first?.ramTotal ?? 0) > 0 && (first?.ramUsed ?? 0) > 0 && (first?.own ?? 0) > 0, "\(String(describing: first))")
        expect(first?.cpu == nil, "no interval yet on the first reading")
        SystemStats.shared.stop(token)
        expect(!SystemStats.shared.isRunning)
        expect(SystemStats.memoryText(12 * 1_073_741_824 + 429_496_730, of: 16 * 1_073_741_824) == "12.4 / 16 GB")
        expect(SystemStats.sizeText(61 * 1_048_576) == "61 MB" && SystemStats.sizeText(1_288_490_189) == "1.2 GB")
    }),
    ("a picture of a full bar, with CADEX_SNAPSHOT_DIR", {
        guard let dir = ProcessInfo.processInfo.environment["CADEX_SNAPSHOT_DIR"] else { return }
        let bar = StatusBarView(frame: NSRect(x: 0, y: 0, width: 900, height: StatusBarView.height))
        @MainActor func label(_ id: String, _ icon: Icon, _ text: String, tint: NSColor? = nil) -> StatusItem {
            let view = StatusLabel(icon: icon)
            view.text = text
            view.tint = tint
            return StatusItem(id: id, title: id, icon: icon, view: view)
        }
        bar.add([label("branch", .gitBranch, "main ↑2"), label("terminals", .terminalWindow, "4"),
                 label("ram", .memory, "12.4 / 16 GB"), label("cpu", .cpu, "18%"), label("cadexMemory", .appWindow, "61 MB", tint: nil)])
        bar.style = .init(text: .white, secondaryText: NSColor(white: 0.62, alpha: 1))
        bar.path = NSHomeDirectory() + "/Cadu/Trabalho/cadu/cadex"
        bar.setLayout(left: ["folder", "branch"], right: ["terminals", "ram", "cpu", "cadexMemory", "environment"])
        let window = NSWindow(contentRect: bar.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        let root = NSView(frame: bar.frame)
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(white: 0.08, alpha: 1).cgColor
        root.addSubview(bar)
        window.contentView = root
        root.layoutSubtreeIfNeeded()
        if let bitmap = root.bitmapImageRepForCachingDisplay(in: root.bounds) {
            root.cacheDisplay(in: root.bounds, to: bitmap)
            try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir + "/status-bar.png"))
        }
    }),
])
exit(exitCode)
