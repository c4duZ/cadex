import Foundation
import Checks
@testable import Explorer

// Tests of the explorer feature. Run with `make macos-test` (see
// shared/checks/Checks.swift for why this is an executable).

let exitCode = await Checks.run([
    ("the launch folder is the first folder argument, flags skipped", {
        let folder = WorkspaceFolder.launchDirectory(arguments: ["Cadex", "-psn_0_42", "bin"], cwd: "/usr")
        expect(folder == "/usr/bin", "\(folder ?? "nil")")
        expect(WorkspaceFolder.launchDirectory(arguments: ["Cadex"], cwd: "/usr") == nil)
    }),
    ("without a launch folder the root is the home folder", {
        let folder = WorkspaceFolder(arguments: ["Cadex"], cwd: "/")
        expect(folder.root == (NSHomeDirectory() as NSString).resolvingSymlinksInPath, folder.root)
    }),
    ("opening a folder authorizes it and changes the root once", {
        let folder = WorkspaceFolder(arguments: ["Cadex", "/usr"], cwd: "/")
        var changes: [String] = []
        folder.onChange = { changes.append($0) }
        expect(folder.open("/tmp"))
        expect(folder.root == "/private/tmp", folder.root)
        expect(folder.open("/private/tmp/."))
        expect(changes == ["/private/tmp"], "\(changes)")
        expect(!folder.open("/no/such/folder"))
        expect(folder.root == "/private/tmp")
    }),
])
exit(exitCode)
