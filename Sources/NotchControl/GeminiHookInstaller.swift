import Foundation

/// Writes NotchControl's hook entries into ~/.gemini/settings.json (Gemini CLI).
/// Gemini has its own event names; the bridge maps them onto Claude Code's.
enum GeminiHookInstaller {
    static let events: [(name: String, timeout: Int)] = [ // timeout in milliseconds
        ("SessionStart", 10_000), ("SessionEnd", 10_000), ("BeforeAgent", 10_000), ("AfterAgent", 10_000),
        ("BeforeTool", 10_000), ("AfterTool", 10_000), ("Notification", 10_000), ("PreCompress", 10_000),
    ]

    static var fileURL: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".gemini/settings.json")
    }

    static func command(for event: String) -> String {
        "/bin/sh -c '[ ! -x \"\(HookInstaller.bridgePath)\" ] || exec \"\(HookInstaller.bridgePath)\" --agent gemini --event \(event)'"
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
        guard let entries = hooks["BeforeTool"] as? [[String: Any]] else { return false }
        return entries.contains(where: entryMatches)
    }

    static func install() throws {
        var settings = load()
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        for event in events {
            var entries = hooks[event.name] as? [[String: Any]] ?? []
            entries.removeAll(where: entryMatches)
            let hook: [String: Any] = ["type": "command", "name": "notchcontrol", "command": command(for: event.name), "timeout": event.timeout]
            entries.append(["hooks": [hook]])
            hooks[event.name] = entries
        }
        settings["hooks"] = hooks
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let backup = fileURL.appendingPathExtension("notchcontrol.backup")
            try? FileManager.default.removeItem(at: backup)
            try FileManager.default.copyItem(at: fileURL, to: backup)
        }
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: fileURL, options: .atomic)
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
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: fileURL, options: .atomic)
    }
}
