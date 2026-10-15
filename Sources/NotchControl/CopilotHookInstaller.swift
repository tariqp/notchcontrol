import Foundation

/// Writes NotchControl's hook file for GitHub Copilot CLI at ~/.copilot/hooks/notchcontrol.json.
enum CopilotHookInstaller {
    static let events: [(name: String, timeout: Int)] = [
        ("sessionStart", 10), ("sessionEnd", 10), ("userPromptSubmitted", 10),
        ("preToolUse", 10), ("postToolUse", 10), ("postToolUseFailure", 10),
        ("permissionRequest", 86400), ("agentStop", 10), ("errorOccurred", 10),
        ("notification", 10), ("subagentStart", 10), ("subagentStop", 10),
    ]

    static var hooksDir: URL {
        let home = ProcessInfo.processInfo.environment["COPILOT_HOME"].map { URL(fileURLWithPath: $0) }
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".copilot")
        return home.appendingPathComponent("hooks", isDirectory: true)
    }

    static var fileURL: URL { hooksDir.appendingPathComponent("notchcontrol.json") }

    static func isInstalled() -> Bool { FileManager.default.fileExists(atPath: fileURL.path) }

    static func install() throws {
        let bridge = HookInstaller.bridgePath
        var hooks: [String: Any] = [:]
        for event in events {
            let cmd = "[ ! -x \"\(bridge)\" ] || exec \"\(bridge)\" --agent copilot --event \(event.name)"
            hooks[event.name] = [["type": "command", "bash": cmd, "timeoutSec": event.timeout]]
        }
        let config: [String: Any] = ["version": 1, "hooks": hooks]
        try FileManager.default.createDirectory(at: hooksDir, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: fileURL, options: .atomic)
    }

    static func uninstall() throws {
        if isInstalled() { try FileManager.default.removeItem(at: fileURL) }
    }
}
