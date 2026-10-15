import Foundation

/// Appends short diagnostic lines to ~/Library/Application Support/NotchControl/debug.log.
enum DebugLog {
    static let url = AppPaths.supportDir.appendingPathComponent("debug.log")
    private static let queue = DispatchQueue(label: "notchcontrol.debuglog")
    private static let formatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"; return f
    }()

    static func log(_ message: String) {
        let line = "\(formatter.string(from: Date())) \(message)\n"
        queue.async {
            if let h = try? FileHandle(forWritingTo: url) {
                h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close()
            } else {
                try? line.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
}
