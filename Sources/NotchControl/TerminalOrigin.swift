import AppKit
import Foundation

/// The GUI app (Terminal, iTerm2, VS Code, Cursor, …) that an agent session was launched from.
struct TerminalOrigin {
    let pid: pid_t
    let bundleID: String?
    let tty: String?

    /// Walks the hook's ancestor chain and picks the first process that is a regular GUI app.
    static func locate(pids: [Int], tty: String?) -> TerminalOrigin? {
        for pid in pids {
            guard let app = NSRunningApplication(processIdentifier: pid_t(pid)),
                  app.activationPolicy == .regular else { continue }
            return TerminalOrigin(pid: pid_t(pid), bundleID: app.bundleIdentifier, tty: tty)
        }
        return nil
    }

    var appName: String {
        NSRunningApplication(processIdentifier: pid)?.localizedName ?? "the terminal"
    }

    /// Types `text` plus Enter into the agent's Terminal.app or iTerm2 tab. Returns false for other apps.
    func sendText(_ text: String) -> Bool {
        guard let tty, let script = Self.typeScript(bundleID: bundleID, tty: tty, text: text) else { return false }
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        if let error { DebugLog.log("sendText: \(error)"); return false }
        return true
    }

    private static func typeScript(bundleID: String?, tty: String, text: String) -> String? {
        let escaped = text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        switch bundleID {
        case "com.apple.Terminal":
            return """
            tell application "Terminal"
                repeat with w in windows
                    repeat with t in tabs of w
                        if tty of t is "\(tty)" then
                            do script "\(escaped)" in t
                            return
                        end if
                    end repeat
                end repeat
            end tell
            """
        case "com.googlecode.iterm2":
            return """
            tell application "iTerm2"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if tty of s is "\(tty)" then
                                tell s to write text "\(escaped)"
                                return
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            """
        default:
            return nil
        }
    }

    /// Editors whose windows are keyed by folder: opening the session's cwd focuses the right window.
    private static let folderEditors: Set<String> = [
        "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.vscodium",
        "com.todesktop.230313mzl4w4u92", // Cursor
        "com.exafunction.windsurf", "dev.zed.Zed",
    ]

    /// Brings the app forward and, for Terminal and iTerm2, selects the tab attached to the tty.
    func focus(cwd: String) {
        guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else {
            DebugLog.log("focus: process \(pid) is gone"); return
        }
        DebugLog.log("focus: \(bundleID ?? "?") pid=\(pid) tty=\(tty ?? "-") cwd=\(cwd)")
        if let tty, let script = Self.selectTabScript(bundleID: bundleID, tty: tty) {
            DispatchQueue.global(qos: .userInitiated).async {
                var error: NSDictionary?
                NSAppleScript(source: script)?.executeAndReturnError(&error)
                if let error { DebugLog.log("focus tab: \(error)") }
                DispatchQueue.main.async { Self.bringForward(app) }
            }
            return
        }
        if let id = bundleID, Self.folderEditors.contains(id), !cwd.isEmpty, let bundleURL = app.bundleURL,
           FileManager.default.fileExists(atPath: cwd) {
            // Reuses the window that already has this folder open, instead of just the last-used window.
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.open([URL(fileURLWithPath: cwd)], withApplicationAt: bundleURL, configuration: config) { _, error in
                if let error { DebugLog.log("focus open folder: \(error)"); DispatchQueue.main.async { Self.bringForward(app) } }
            }
            return
        }
        Self.bringForward(app)
    }

    /// Activation from a background (menu-bar) app is unreliable on macOS 14+, so go through
    /// NSWorkspace first (which may activate on our behalf) and fall back to the direct call.
    private static func bringForward(_ app: NSRunningApplication) {
        if let url = app.bundleURL {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
                if let error {
                    DebugLog.log("focus openApplication: \(error)")
                    DispatchQueue.main.async { app.activate(options: [.activateAllWindows]) }
                }
            }
        } else {
            app.activate(options: [.activateAllWindows])
        }
    }

    private static func selectTabScript(bundleID: String?, tty: String) -> String? {
        switch bundleID {
        case "com.apple.Terminal":
            return """
            tell application "Terminal"
                repeat with w in windows
                    repeat with t in tabs of w
                        if tty of t is "\(tty)" then
                            set selected tab of w to t
                            set index of w to 1
                            return
                        end if
                    end repeat
                end repeat
            end tell
            """
        case "com.googlecode.iterm2":
            return """
            tell application "iTerm2"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if tty of s is "\(tty)" then
                                select w
                                select t
                                select s
                                return
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            """
        default:
            return nil
        }
    }
}
