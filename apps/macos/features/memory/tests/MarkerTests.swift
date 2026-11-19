import Checks
import Foundation
@testable import Memory

// The project's .ai-memory.toml on the settings screen (plan 32 D): what a file says, and writing
// keeps every line the screen does not own.

func markerTests() -> [(name: String, body: Checks.Body)] { [
    ("a marker reads as the engine does: tables, quoted and bare flags, an array on several lines", {
        let text = """
        # our team's memory
        workspace = "team"
        project = "app"   # pinned
        drop_subagent_captures = "true"

        [capture]
        ignore_paths = [
          "*.env",
          "secrets/**",
        ]

        [briefing]
        inject_on_session_start = "false"
        max_chars = 6000
        [handoff]
        deliver_on_session_start = no
        [profile]
        consume = 0
        [routes.path."~/x"]
        route_project = "keep"
        """
        let marker = MemoryMarker.read(text)
        expect(marker.workspace == "team" && marker.project == "app", "\(marker)")
        expect(marker.ignorePaths == ["*.env", "secrets/**"], "\(marker.ignorePaths)")
        expect(marker.dropSubagents && !marker.briefing && marker.briefingChars == 6000)
        expect(!marker.handoff && marker.recovery && !marker.consume && marker.contribute && !marker.searchAll)
        expect(MemoryMarker.read("") == MemoryMarker(), "no file: upstream's defaults")
        expect(!MemoryMarker().briefing, "the brief is off unless the file says so (plan 35 B)")
    }),
    ("writing changes only the screen's keys: comments, other tables and unknown keys stay", {
        let text = """
        # our team's memory
        workspace = "team"
        identity = "github.com/acme/app"

        [capture]
        ignore_paths = [
          "*.env",
        ]
        # keep me
        [routes.path."~/x"]
        route_project = "keep"
        """
        var marker = MemoryMarker.read(text)
        marker.workspace = ""
        marker.project = "app"
        marker.ignorePaths = ["*.env", "build/**"]
        marker.searchAll = true
        marker.briefingChars = 99_999
        let out = marker.written(over: text)
        for kept in ["# our team's memory", "identity = \"github.com/acme/app\"", "# keep me", "[routes.path.\"~/x\"]", "route_project = \"keep\""] {
            expect(out.contains(kept), "kept: \(kept)\n\(out)")
        }
        expect(!out.contains("workspace"), "an empty workspace removes the line, the repository's counts again\n\(out)")
        expect(out.contains("ignore_paths = [\"*.env\", \"build/**\"]"), out)
        expect(out.contains("[recall]\ndefault_global = true"), out)
        expect(out.contains("max_chars = 20000"), "clamped as the engine does\n\(out)")
        expect(!out.contains("inject_on_session_start"), "a default not in the file is not written\n\(out)")
        let again = MemoryMarker.read(out)
        expect(again.project == "app" && again.searchAll && again.ignorePaths == ["*.env", "build/**"], "reads back\n\(out)")
        // The project's line goes with the other top-level keys, before the first table.
        let lines = out.components(separatedBy: "\n")
        let project = lines.firstIndex { $0.hasPrefix("project = ") } ?? .max
        let firstTable = lines.firstIndex { $0.hasPrefix("[") } ?? 0
        expect(project < firstTable, out)
    }),
    ("a new file holds only what differs from the defaults", {
        var marker = MemoryMarker()
        expect(marker.written(over: "").isEmpty, "nothing to say")
        marker.briefing = true
        expect(marker.written(over: "") == "[briefing]\ninject_on_session_start = true", marker.written(over: ""))
    }),
] }
