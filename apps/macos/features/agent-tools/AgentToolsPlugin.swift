import Foundation

/// The Cadex plugin the session kit passes by `--plugin-dir`: short skills
/// that send the agent to `cadex skills get <topic>`, whose guides live in
/// the binary of the same version (docs/adr/0024-agent-tools.md). In the
/// bundle's Resources (packaging copies it); while developing, beside this
/// file.
public enum AgentToolsPlugin {
    public static var folder: String? {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("agent-plugin").path,
           FileManager.default.fileExists(atPath: bundled + "/.claude-plugin/plugin.json") { return bundled }
        let beside = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("plugin").path
        return FileManager.default.fileExists(atPath: beside + "/.claude-plugin/plugin.json") ? beside : nil
    }
}
