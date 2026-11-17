import Checks
import Foundation

// Tests of the sidebar feature (the work's tree, `Tree.swift`). Run with `make macos-test` (see
// shared/checks/Checks.swift for why this is an executable).

let treeExit = await Checks.run(treeChecks + jumpChecks)
exit(treeExit)
