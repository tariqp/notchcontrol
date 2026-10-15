// notchcontrol-bridge: forwards one agent hook event (JSON on stdin) to the running
// NotchControl app over a Unix socket and prints the app's reply, if any.
// Exits 0 silently when the app is not running so hooks never fail.
//
// Usage: notchcontrol-bridge --agent claude|copilot [--event <copilot event name>]
import Foundation

let args = CommandLine.arguments
func arg(_ flag: String) -> String? {
    guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
    return args[i + 1]
}
let agent = arg("--agent") ?? "claude"
let eventOverride = arg("--event")

let input = FileHandle.standardInput.readDataToEndOfFile()
guard var event = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any] else { exit(0) }
event["agent"] = agent

// MARK: Normalise other agents into the Claude Code hook shape

/// Copilot CLI camelCase event names -> Claude Code hook event names.
let copilotEvents: [String: String] = [
    "sessionstart": "SessionStart", "sessionend": "SessionEnd",
    "userpromptsubmitted": "UserPromptSubmit", "userprompttransformed": "UserPromptSubmit",
    "pretooluse": "PreToolUse", "posttooluse": "PostToolUse", "posttoolusefailure": "PostToolUseFailure",
    "permissionrequest": "PermissionRequest", "agentstop": "Stop", "erroroccurred": "StopFailure",
    "notification": "Notification", "precompact": "PreCompact",
    "subagentstart": "SubagentStart", "subagentstop": "SubagentStop",
]

if agent == "copilot" {
    let rawName = eventOverride ?? (event["hookEventName"] as? String) ?? (event["hook_event_name"] as? String) ?? ""
    if let mapped = copilotEvents[rawName.lowercased()] {
        event["hook_event_name"] = mapped
    } else if event["hook_event_name"] == nil {
        event["hook_event_name"] = rawName
    }
    if event["session_id"] == nil { event["session_id"] = event["sessionId"] }
    if event["tool_name"] == nil { event["tool_name"] = event["toolName"] }
    if event["tool_input"] == nil { event["tool_input"] = event["toolArgs"] ?? event["toolInput"] }
    if event["hook_event_name"] as? String == "StopFailure",
       let err = event["error"] as? [String: Any], let msg = err["message"] as? String {
        event["error"] = msg
    }
}

// MARK: Where was this agent launched from?
// The hook runs as a child of the agent process, which is a child of a shell inside
// some terminal or editor. Send the ancestor chain and our tty so the app can find
// and focus that window later.

func procInfo(_ pid: pid_t) -> kinfo_proc? {
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
    guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
    return info
}

var ancestors: [Int] = []
var cursor = getppid()
while cursor > 1, ancestors.count < 24, let info = procInfo(cursor) {
    ancestors.append(Int(cursor))
    cursor = info.kp_eproc.e_ppid
}
event["_pids"] = ancestors
// The hook itself may run detached from the terminal; the first ancestor with a tty is the shell/agent.
for pid in [Int(getpid())] + ancestors {
    guard let info = procInfo(pid_t(pid)), info.kp_eproc.e_tdev != -1,
          let name = devname(info.kp_eproc.e_tdev, S_IFCHR) else { continue }
    event["_tty"] = "/dev/" + String(cString: name)
    break
}

guard let payload = try? JSONSerialization.data(withJSONObject: event) else { exit(0) }

// MARK: Send to the app

let socketPath = (NSHomeDirectory() as NSString)
    .appendingPathComponent("Library/Application Support/NotchControl/bridge.sock")

let fd = socket(AF_UNIX, SOCK_STREAM, 0)
guard fd >= 0 else { exit(0) }
var one: Int32 = 1
setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))

var addr = sockaddr_un()
addr.sun_family = sa_family_t(AF_UNIX)
let pathBytes = socketPath.utf8CString
guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else { exit(0) }
withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
    ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dst in
        for (i, c) in pathBytes.enumerated() { dst[i] = c }
    }
}
let len = socklen_t(MemoryLayout<sockaddr_un>.size)
let rc = withUnsafePointer(to: &addr) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, len) }
}
guard rc == 0 else { exit(0) }

var out = payload
out.append(0x0A)
out.withUnsafeBytes { buf in
    var off = 0
    while off < buf.count {
        let n = write(fd, buf.baseAddress! + off, buf.count - off)
        if n <= 0 { break }
        off += n
    }
}

var reply = Data()
var chunk = [UInt8](repeating: 0, count: 4096)
while true {
    let n = read(fd, &chunk, chunk.count)
    if n <= 0 { break }
    reply.append(chunk, count: n)
    if chunk[..<n].contains(0x0A) { break }
}
close(fd)

// MARK: Translate the reply for the agent that asked

guard let text = String(data: reply, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
      !text.isEmpty else { exit(0) }

if agent == "copilot",
   let obj = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any],
   let specific = obj["hookSpecificOutput"] as? [String: Any],
   let decision = specific["decision"] as? [String: Any],
   let behavior = decision["behavior"] as? String {
    var copilotReply: [String: Any] = ["permissionDecision": behavior == "allow" ? "allow" : "deny"]
    if behavior != "allow" { copilotReply["permissionDecisionReason"] = decision["message"] ?? "Denied in NotchControl." }
    if let data = try? JSONSerialization.data(withJSONObject: copilotReply), let s = String(data: data, encoding: .utf8) {
        print(s)
    }
    exit(0)
}

print(text)
