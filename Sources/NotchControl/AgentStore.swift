import AppKit
import Foundation
import SwiftUI

struct AgentSession: Identifiable {
    let id: String
    var agent: String
    var cwd: String
    var status: String = "Idle"
    var activity: String = ""
    var lastPrompt: String = ""
    var lastMessage: String = ""
    var updatedAt = Date()
    /// Activity labels of tools that have started but not finished (parallel tool calls).
    var runningTools: [String] = []
    /// Where the agent was launched from (terminal app + tty), resolved from the hook's process tree.
    var terminal: TerminalOrigin?
    var startedAt = Date()
    var branch: String?
    /// Tools the user allowed for the rest of this session; matching permission requests are answered automatically.
    var autoAllowed: [String] = []
    /// Last few activity changes, newest last.
    var timeline: [TimelineEntry] = []
    /// Hint shown under the reply field after sending (e.g. "Copied, paste it in Cursor").
    var replyHint: String = ""

    struct TimelineEntry: Identifiable {
        let id = UUID()
        let at: Date
        let text: String
    }

    var isBusy: Bool { status == "Working" || status == "Waiting for approval" }

    var title: String {
        let folder = (cwd as NSString).lastPathComponent
        return folder.isEmpty ? agent.capitalized : "\(agent.capitalized) · \(folder)"
    }
}

/// A permission request (or question) from an agent that is waiting for an answer in the notch.
final class PendingDecision: Identifiable {
    struct Question: Identifiable {
        let id = UUID()
        let text: String
        let header: String
        let options: [String]
    }

    let id = UUID()
    let sessionID: String
    let agent: String
    let toolName: String
    let summary: String
    let questions: [Question]
    let createdAt = Date()
    private var respond: ((String?) -> Void)?
    /// The original tool input; an AskUserQuestion answer must return it with `answers` added.
    let input: [String: Any]

    init(sessionID: String, agent: String, toolName: String, input: [String: Any], respond: @escaping (String?) -> Void) {
        self.sessionID = sessionID
        self.agent = agent
        self.toolName = toolName
        self.input = input
        self.respond = respond
        let raw = (input["questions"] as? [[String: Any]]) ?? []
        questions = raw.map { q in
            Question(text: q["question"] as? String ?? "",
                     header: q["header"] as? String ?? "",
                     options: ((q["options"] as? [[String: Any]]) ?? []).compactMap { $0["label"] as? String })
        }
        if let first = questions.first {
            summary = first.text
        } else {
            summary = AgentStore.summary(tool: toolName, input: input) ?? AgentStore.describe(input)
        }
    }

    func resolve(_ json: String?) {
        respond?(json)
        respond = nil
    }
}

final class AgentStore: ObservableObject {
    enum Event {
        case needsApproval(PendingDecision)
        case waitingForInput(AgentSession)
        case finished(AgentSession)
        case failed(AgentSession)
    }

    @Published private(set) var sessions: [String: AgentSession] = [:]
    @Published private(set) var pending: [PendingDecision] = []
    var onEvent: ((Event) -> Void)?
    private var cleanupTimer: Timer?

    init() {
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.dropStaleSessions() }
    }

    /// A finished session disappears after 30 minutes; one with no events at all for 3 hours is gone too.
    private func dropStaleSessions() {
        let now = Date()
        let before = sessions.count
        sessions = sessions.filter { _, s in
            let age = now.timeIntervalSince(s.updatedAt)
            if s.status == "Done" || s.status == "Idle" { return age < 30 * 60 }
            return age < 3 * 60 * 60
        }
        if sessions.count != before { objectWillChange.send() }
    }

    var orderedSessions: [AgentSession] { sessions.values.sorted { $0.updatedAt > $1.updatedAt } }

    var headline: String {
        if let p = pending.first { return "Approve \(p.toolName)?" }
        if let s = orderedSessions.first { return s.activity.isEmpty ? s.status : s.activity }
        return "No agents"
    }

    var indicatorColor: Color {
        if !pending.isEmpty { return .orange }
        guard let s = orderedSessions.first else { return .gray }
        switch s.status {
        case "Working": return .green
        case "Waiting for you", "Waiting for approval": return .orange
        case "Failed": return .red
        default: return .gray
        }
    }

    // MARK: Event handling (called on the main thread by BridgeServer)

    func handle(_ event: [String: Any], respond: @escaping (String?) -> Void) {
        let name = event["hook_event_name"] as? String ?? ""
        let id = event["session_id"] as? String ?? "unknown"
        let agent = event["agent"] as? String ?? "claude"
        let cwd = event["cwd"] as? String ?? ""

        var s = sessions[id] ?? AgentSession(id: id, agent: agent, cwd: cwd)
        if !cwd.isEmpty { s.cwd = cwd }
        s.updatedAt = Date()
        if s.terminal == nil, let pids = event["_pids"] as? [Int] {
            s.terminal = TerminalOrigin.locate(pids: pids, tty: event["_tty"] as? String)
        }
        if s.branch == nil || name == "SessionStart" || name == "UserPromptSubmit" { s.branch = Self.gitBranch(at: s.cwd) }
        let previousActivity = s.activity
        defer {
            if var saved = sessions[id], saved.activity != previousActivity, !saved.activity.isEmpty {
                saved.timeline.append(.init(at: Date(), text: saved.activity))
                if saved.timeline.count > 12 { saved.timeline.removeFirst(saved.timeline.count - 12) }
                sessions[id] = saved
            }
        }

        switch name {
        case "SessionStart":
            s.status = "Idle"
            s.activity = "Session started"
        case "UserPromptSubmit":
            s.lastPrompt = event["prompt"] as? String ?? ""
            s.runningTools.removeAll()
            s.status = "Working"
            s.activity = "Thinking"
        case "PreToolUse":
            let tool = Self.normalizeTool(event["tool_name"] as? String ?? "Tool")
            let input = event["tool_input"] as? [String: Any] ?? [:]
            let label = Self.activity(tool: tool, summary: Self.summary(tool: tool, input: input))
            s.runningTools.append(label)
            if s.runningTools.count > 8 { s.runningTools.removeFirst() }
            s.status = "Working"
            s.activity = label
        case "PostToolUse", "PostToolUseFailure":
            // Finish the matching tool; if others are still running keep showing the latest one.
            let tool = Self.normalizeTool(event["tool_name"] as? String ?? "Tool")
            let input = event["tool_input"] as? [String: Any] ?? [:]
            let label = Self.activity(tool: tool, summary: Self.summary(tool: tool, input: input))
            if let i = s.runningTools.lastIndex(of: label) {
                s.runningTools.remove(at: i)
            } else if !s.runningTools.isEmpty {
                s.runningTools.removeFirst()
            }
            s.status = "Working"
            s.activity = s.runningTools.last ?? "Thinking"
        case "PermissionRequest":
            let tool = Self.normalizeTool(event["tool_name"] as? String ?? "Tool")
            let input = event["tool_input"] as? [String: Any] ?? [:]
            if s.autoAllowed.contains(tool), input["questions"] == nil {
                s.status = "Working"
                s.activity = "Auto-allowed " + Self.activity(tool: tool, summary: Self.summary(tool: tool, input: input))
                sessions[id] = s
                respond(Self.decisionJSON(allow: true))
                return
            }
            let decision = PendingDecision(sessionID: id, agent: agent, toolName: tool, input: input, respond: respond)
            pending.append(decision)
            s.status = "Waiting for approval"
            s.activity = Self.activity(tool: tool, summary: Self.summary(tool: tool, input: input))
            sessions[id] = s
            onEvent?(.needsApproval(decision))
            return // answered later by decide(...)
        case "Notification":
            let type = event["notification_type"] as? String ?? ""
            let message = event["message"] as? String ?? ""
            if type == "idle_prompt" || message.localizedCaseInsensitiveContains("waiting for your input") {
                s.status = "Waiting for you"
                s.activity = "Waiting for your input"
                sessions[id] = s
                onEvent?(.waitingForInput(s))
            } else if type == "permission_prompt" {
                s.status = "Waiting for approval"
            }
        case "Stop":
            s.runningTools.removeAll()
            s.status = "Done"
            s.activity = "Finished"
            s.lastMessage = event["last_assistant_message"] as? String ?? ""
            sessions[id] = s
            onEvent?(.finished(s))
        case "StopFailure":
            s.status = "Failed"
            s.activity = event["error"] as? String ?? "Stopped with an error"
            sessions[id] = s
            onEvent?(.failed(s))
        case "SessionEnd":
            sessions.removeValue(forKey: id)
            for p in pending where p.sessionID == id { p.resolve(nil) }
            pending.removeAll { $0.sessionID == id }
            respond(nil)
            return
        case "PreCompact", "PostCompact":
            s.activity = "Compacting the conversation"
        case "SubagentStart":
            s.activity = "Running a subagent"
        case "SubagentStop":
            s.activity = "Thinking"
        default:
            break
        }
        sessions[id] = s
        respond(nil)
    }

    static func decisionJSON(allow: Bool, updatedInput: [String: Any]? = nil) -> String? {
        var decision: [String: Any] = ["behavior": allow ? "allow" : "deny"]
        if !allow { decision["message"] = "Denied in NotchControl." }
        if let updatedInput { decision["updatedInput"] = updatedInput }
        let output: [String: Any] = ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": decision]]
        return (try? JSONSerialization.data(withJSONObject: output)).flatMap { String(data: $0, encoding: .utf8) }
    }

    /// Answer a pending permission request. `answers` is used for AskUserQuestion prompts.
    /// `forSession` also allows the same tool for the rest of that session.
    func decide(_ p: PendingDecision, allow: Bool, answers: [String: String]? = nil, forSession: Bool = false) {
        var updated: [String: Any]?
        if allow, let answers {
            updated = p.input
            updated?["answers"] = answers
        }
        p.resolve(Self.decisionJSON(allow: allow, updatedInput: updated))
        pending.removeAll { $0.id == p.id }
        if var s = sessions[p.sessionID] {
            s.status = allow ? "Working" : "Idle"
            s.activity = allow ? "Thinking" : "Denied \(p.toolName)"
            s.updatedAt = Date()
            if allow, forSession, !s.autoAllowed.contains(p.toolName) { s.autoAllowed.append(p.toolName) }
            sessions[p.sessionID] = s
        }
    }

    func clearAutoAllowed(_ s: AgentSession) {
        guard var saved = sessions[s.id] else { return }
        saved.autoAllowed.removeAll()
        sessions[s.id] = saved
    }

    /// Sends a reply to the agent's terminal (Terminal and iTerm2 via AppleScript).
    /// Other apps get the text on the clipboard and are brought forward so the user can paste.
    func send(_ text: String, to s: AgentSession) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var saved = sessions[s.id] else { return }
        if s.terminal?.sendText(trimmed) == true {
            saved.replyHint = ""
            saved.lastPrompt = trimmed
            saved.status = "Working"
            saved.activity = "Thinking"
        } else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(trimmed, forType: .string)
            s.terminal?.focus(cwd: s.cwd)
            saved.replyHint = "Copied. Paste it into \(s.terminal?.appName ?? "the terminal") and press Enter."
        }
        saved.updatedAt = Date()
        sessions[s.id] = saved
    }

    /// Current git branch for a working directory (handles worktrees and detached HEAD).
    static func gitBranch(at cwd: String) -> String? {
        guard !cwd.isEmpty else { return nil }
        var dir = URL(fileURLWithPath: cwd)
        for _ in 0..<12 {
            let dotGit = dir.appendingPathComponent(".git")
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: dotGit.path, isDirectory: &isDir) {
                var gitDir = dotGit
                if !isDir.boolValue, let text = try? String(contentsOf: dotGit, encoding: .utf8),
                   let line = text.split(separator: "\n").first, line.hasPrefix("gitdir: ") {
                    let path = String(line.dropFirst(8)).trimmingCharacters(in: .whitespaces)
                    gitDir = path.hasPrefix("/") ? URL(fileURLWithPath: path) : dir.appendingPathComponent(path)
                }
                guard let head = try? String(contentsOf: gitDir.appendingPathComponent("HEAD"), encoding: .utf8) else { return nil }
                let ref = head.trimmingCharacters(in: .whitespacesAndNewlines)
                if ref.hasPrefix("ref: refs/heads/") { return String(ref.dropFirst(16)) }
                return String(ref.prefix(7))
            }
            if dir.path == "/" { break }
            dir.deleteLastPathComponent()
        }
        return nil
    }

    /// Brings the terminal (or editor) that runs this session to the front.
    func focusTerminal(_ s: AgentSession) {
        if let t = s.terminal { t.focus(cwd: s.cwd) } else { DebugLog.log("focus: no terminal known for session \(s.id)") }
    }

    func dismiss(_ p: PendingDecision) {
        p.resolve(nil) // no answer: the agent's own prompt decides
        pending.removeAll { $0.id == p.id }
    }

    // MARK: Labels

    /// Map other agents' tool names onto Claude Code's vocabulary so labels stay consistent.
    static func normalizeTool(_ name: String) -> String {
        switch name.lowercased() {
        case "bash", "shell", "run_in_terminal", "execute", "exec": return "Bash"
        case "read", "view", "read_file", "cat": return "Read"
        case "write", "create", "create_file", "write_file": return "Write"
        case "edit", "str_replace_editor", "edit_file", "multiedit", "patch", "apply_patch": return "Edit"
        case "grep", "search", "search_file_content": return "Grep"
        case "glob", "find", "list", "ls": return "Glob"
        case "webfetch", "web_fetch", "fetch", "read_web_page": return "WebFetch"
        case "websearch", "web_search", "google_web_search": return "WebSearch"
        case "task", "agent", "subagent": return "Task"
        case "todowrite", "todo_write": return "TodoWrite"
        case "askuserquestion", "ask_user", "question": return "AskUserQuestion"
        default: return name
        }
    }

    /// The one piece of tool input worth showing for a tool call.
    static func summary(tool: String, input: [String: Any]) -> String? {
        func str(_ keys: String...) -> String? {
            for k in keys {
                if let v = input[k] as? String, !v.isEmpty { return v }
            }
            return nil
        }
        switch tool {
        case "Bash": return str("command", "cmd", "shell")
        case "Read", "Write", "Edit", "MultiEdit", "NotebookEdit":
            return str("file_path", "path").map { ($0 as NSString).lastPathComponent }
        case "Grep", "Glob": return str("pattern")
        case "WebSearch": return str("query")
        case "WebFetch": return str("url").flatMap { URL(string: $0)?.host }
        case "Task", "Agent": return str("description")
        default: return str("description", "command", "query", "pattern", "file_path", "url")
        }
    }

    /// Human-readable activity line for the notch.
    static func activity(tool: String, summary: String?) -> String {
        func with(_ prefix: String, _ sep: String = " ") -> String {
            guard let summary else { return prefix }
            return prefix + sep + summary
        }
        switch tool {
        case "Bash": return with("Running", ": ")
        case "Read": return with("Reading")
        case "Write": return with("Writing")
        case "Edit", "MultiEdit", "NotebookEdit": return with("Editing")
        case "Grep": return with("Searching for")
        case "Glob": return with("Finding files")
        case "WebSearch": return summary.map { "Searching the web for \($0)" } ?? "Searching the web"
        case "WebFetch": return summary.map { "Reading \($0)" } ?? "Reading a web page"
        case "Task", "Agent": return with("Subagent", ": ")
        case "TodoWrite": return "Updating the to-do list"
        case "AskUserQuestion": return "Asking you a question"
        case "ExitPlanMode": return "Finishing the plan"
        default: return with("Using \(tool)", ": ")
        }
    }

    static func describe(_ input: [String: Any]) -> String {
        guard !input.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: input, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "" }
        return String(text.prefix(400))
    }
}
