import Foundation

// MARK: Memory off (plan 35 I; docs/spec/memory.md, "Desligar")

extension ProjectsController {
    /// The folders with the project memory off on this Mac, kept in projects.json whether the
    /// project is open or not.
    public var memoryOff: Set<String> { memoryOffFolders }

    public func isMemoryOff(_ folder: String) -> Bool { memoryOffFolders.contains(folder) }

    /// "Memory in this project": off or back on; saved, and told to the app (which writes the
    /// memory's off-projects.json for the engine and the kit).
    public func setMemoryOff(_ off: Bool, for folder: String) {
        guard isMemoryOff(folder) != off else { return }
        if off { memoryOffFolders.insert(folder) } else { memoryOffFolders.remove(folder) }
        onMemoryOffChange?(memoryOffFolders)
        scheduleSave()
    }
}
