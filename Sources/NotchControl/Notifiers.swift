import Foundation
import UserNotifications

enum SettingsKey {
    static let slackWebhookURL = "slackWebhookURL"
    static let slackNotifyApproval = "slackNotifyApproval"
    static let slackNotifyWaiting = "slackNotifyWaiting"
    static let slackNotifyFinished = "slackNotifyFinished"
    static let clipboardLimit = "clipboardLimit"
}

/// Posts messages to a Slack Incoming Webhook configured in Settings.
enum SlackNotifier {
    static var webhookURL: URL? {
        guard let raw = UserDefaults.standard.string(forKey: SettingsKey.slackWebhookURL)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: raw), url.scheme == "https" else { return nil }
        return url
    }

    static func post(_ text: String, completion: ((Bool, String) -> Void)? = nil) {
        guard let url = webhookURL else { completion?(false, "No Slack webhook URL set"); return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["text": text])
        URLSession.shared.dataTask(with: req) { data, resp, err in
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let ok = err == nil && (200..<300).contains(status)
            let detail = err?.localizedDescription ?? (ok ? "Sent" : "Slack replied \(status): \(String(data: data ?? Data(), encoding: .utf8) ?? "")")
            if !ok { NSLog("NotchControl: Slack post failed: \(detail)") }
            DispatchQueue.main.async { completion?(ok, detail) }
        }.resume()
    }
}

/// macOS notifications. Only available when running from a real .app bundle.
enum LocalNotifier {
    static var available: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app"
    }

    static func requestPermission() {
        guard available else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func show(title: String, body: String) {
        guard available else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = String(body.prefix(200))
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
