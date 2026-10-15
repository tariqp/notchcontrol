import Foundation

/// Adds or removes NotchControl's hook entries in ~/.claude/settings.json.
enum HookInstaller {
    static let events: [(name: String, timeout: Int)] = [
        ("SessionStart", 10), ("UserPromptSubmit", 10), ("PreToolUse", 10), ("PostToolUse", 10),
        ("PostToolUseFailure", 10), ("PermissionRequest", 86400), ("Notification", 10),
        ("Stop", 10), ("StopFailure", 10), ("SessionEnd", 10),
        ("PreCompact", 10), ("PostCompact", 10), ("SubagentStart", 10), ("SubagentStop", 10),
    ]
    static let marker = "notchcontrol-bridge"

    static var settingsURL: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/settings.json")
    }

    /// The bridge helper next to this app (inside the bundle, or beside the binary when run with `swift run`).
    static var bridgePath: String {
        let inBundle = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/notchcontrol-bridge").path
        if FileManager.default.isExecutableFile(atPath: inBundle) { return inBundle }
        let exe = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        return exe.deletingLastPathComponent().appendingPathComponent("notchcontrol-bridge").path
    }

    static var command: String {
        "/bin/sh -c '[ ! -x \"\(bridgePath)\" ] || exec \"\(bridgePath)\" --agent claude'"
    }

    private static func load() -> [String: Any] {
        guard let data = try? Data(contentsOf: settingsURL),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [:] }
        return obj
    }

    private static func save(_ settings: [String: Any]) throws {
        let dir = settingsURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: settingsURL.path) {
            let backup = settingsURL.appendingPathExtension("notchcontrol.backup")
            try? FileManager.default.removeItem(at: backup)
            try FileManager.default.copyItem(at: settingsURL, to: backup)
        }
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: settingsURL)
    }

    private static func entryMatches(_ entry: [String: Any]) -> Bool {
        let hooks = entry["hooks"] as? [[String: Any]] ?? []
        return hooks.contains { ($0["command"] as? String)?.contains(marker) == true }
    }

    static func isInstalled() -> Bool {
        let hooks = load()["hooks"] as? [String: Any] ?? [:]
        guard let entries = hooks["PreToolUse"] as? [[String: Any]] else { return false }
        return entries.contains(where: entryMatches)
    }

    static func install() throws {
        var settings = load()
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        for event in events {
            var entries = hooks[event.name] as? [[String: Any]] ?? []
            entries.removeAll(where: entryMatches) // refresh the path if it moved
            var hook: [String: Any] = ["type": "command", "command": command, "timeout": event.timeout]
            if event.name == "PermissionRequest" { hook["statusMessage"] = "Waiting for your approval in NotchControl" }
            entries.append(["hooks": [hook]])
            hooks[event.name] = entries
        }
        settings["hooks"] = hooks
        try save(settings)
    }

    static func uninstall() throws {
        var settings = load()
        guard var hooks = settings["hooks"] as? [String: Any] else { return }
        for (name, value) in hooks {
            guard var entries = value as? [[String: Any]] else { continue }
            entries.removeAll(where: entryMatches)
            if entries.isEmpty { hooks.removeValue(forKey: name) } else { hooks[name] = entries }
        }
        settings["hooks"] = hooks
        try save(settings)
    }
}
