import Foundation

/// Writes NotchControl's hook entries into ~/.codex/hooks.json (OpenAI Codex CLI).
/// Codex uses the same hook file shape and event names as Claude Code.
enum CodexHookInstaller {
    static let events: [(name: String, timeout: Int)] = [
        ("SessionStart", 10), ("SessionEnd", 1), ("UserPromptSubmit", 10), ("PreToolUse", 10),
        ("PermissionRequest", 86400), ("PostToolUse", 10), ("PreCompact", 10), ("PostCompact", 10),
        ("SubagentStart", 10), ("SubagentStop", 10), ("Stop", 10),
    ]

    static var fileURL: URL {
        let home = ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) }
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex")
        return home.appendingPathComponent("hooks.json")
    }

    static var command: String {
        "/bin/sh -c '[ ! -x \"\(HookInstaller.bridgePath)\" ] || exec \"\(HookInstaller.bridgePath)\" --agent codex'"
    }

    private static func load() -> [String: Any] {
        guard let data = try? Data(contentsOf: fileURL),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [:] }
        return obj
    }

    private static func entryMatches(_ entry: [String: Any]) -> Bool {
        let hooks = entry["hooks"] as? [[String: Any]] ?? []
        return hooks.contains { ($0["command"] as? String)?.contains(HookInstaller.marker) == true }
    }

    static func isInstalled() -> Bool {
        let hooks = load()["hooks"] as? [String: Any] ?? [:]
        guard let entries = hooks["PreToolUse"] as? [[String: Any]] else { return false }
        return entries.contains(where: entryMatches)
    }

    static func install() throws {
        var config = load()
        var hooks = config["hooks"] as? [String: Any] ?? [:]
        for event in events {
            var entries = hooks[event.name] as? [[String: Any]] ?? []
            entries.removeAll(where: entryMatches)
            var hook: [String: Any] = ["type": "command", "command": command, "timeout": event.timeout]
            hook["statusMessage"] = event.name == "PermissionRequest" ? "Waiting for your approval in NotchControl" : "NotchControl"
            entries.append(["hooks": [hook]])
            hooks[event.name] = entries
        }
        config["hooks"] = hooks
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: fileURL, options: .atomic)
    }

    static func uninstall() throws {
        var config = load()
        guard var hooks = config["hooks"] as? [String: Any] else { return }
        for (name, value) in hooks {
            guard var entries = value as? [[String: Any]] else { continue }
            entries.removeAll(where: entryMatches)
            if entries.isEmpty { hooks.removeValue(forKey: name) } else { hooks[name] = entries }
        }
        config["hooks"] = hooks
        let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: fileURL, options: .atomic)
    }
}
