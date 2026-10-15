import Foundation
import Security

/// Subscription usage windows (the same numbers Claude Code's /usage shows), fetched with the
/// login Claude Code stores in the keychain. macOS asks once before the app may read that item.
final class AccountUsage: ObservableObject {
    struct Window: Identifiable {
        let id: String
        let label: String
        let utilization: Double     // percent 0–100
        let resetsAt: Date?
    }

    enum State: Equatable {
        case idle, loading, ok, noCredentials, expired
        case error(String)
    }

    @Published private(set) var windows: [Window] = []
    @Published private(set) var state: State = .idle
    @Published private(set) var plan: String?
    @Published private(set) var updatedAt: Date?

    private var timer: Timer?
    private let queue = DispatchQueue(label: "notchcontrol.accountusage", qos: .utility)

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        if state == .loading { return }
        state = .loading
        queue.async { [weak self] in
            guard let self else { return }
            guard let creds = self.readCredentials() else {
                DispatchQueue.main.async { self.state = .noCredentials }
                return
            }
            if let exp = creds.expires, exp < Date() {
                DispatchQueue.main.async { self.plan = creds.plan; self.state = .expired }
                return
            }
            self.fetch(token: creds.token) { result in
                DispatchQueue.main.async {
                    self.plan = creds.plan
                    switch result {
                    case .success(let windows):
                        self.windows = windows
                        self.updatedAt = Date()
                        self.state = .ok
                    case .failure(let err):
                        self.state = .error(err)
                    }
                }
            }
        }
    }

    // MARK: Keychain

    private func readCredentials() -> (token: String, expires: Date?, plan: String?)? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty else { return nil }
        let expires = (oauth["expiresAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
        return (token, expires, oauth["subscriptionType"] as? String)
    }

    // MARK: API

    private static let labels: [String: String] = [
        "five_hour": "Session (5 h)", "seven_day": "Weekly (all models)",
        "seven_day_opus": "Weekly · Opus", "seven_day_sonnet": "Weekly · Sonnet",
        "seven_day_oauth_apps": "Weekly · apps",
    ]
    private static let order = ["five_hour", "seven_day", "seven_day_opus", "seven_day_sonnet", "seven_day_oauth_apps"]

    private func fetch(token: String, completion: @escaping (Result<[Window], String>) -> Void) {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 20
        URLSession.shared.dataTask(with: req) { data, resp, err in
            if let err { completion(.failure(err.localizedDescription)); return }
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard let data, (200..<300).contains(status) else {
                completion(.failure(status == 401 ? "Login expired. Run `claude` once to refresh it." : "Usage request failed (\(status))"))
                return
            }
            guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                completion(.failure("Unexpected usage response"))
                return
            }
            let iso = ISO8601DateFormatter()
            let isoFrac = ISO8601DateFormatter(); isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var windows: [Window] = []
            let keys = Self.order + json.keys.filter { !Self.order.contains($0) }.sorted()
            for key in keys {
                guard let w = json[key] as? [String: Any],
                      let util = (w["utilization"] as? Double) ?? (w["utilization"] as? Int).map(Double.init) else { continue }
                let resets = (w["resets_at"] as? String).flatMap { isoFrac.date(from: $0) ?? iso.date(from: $0) }
                let label = Self.labels[key] ?? key.replacingOccurrences(of: "_", with: " ").capitalized
                windows.append(Window(id: key, label: label, utilization: util, resetsAt: resets))
            }
            completion(.success(windows))
        }.resume()
    }
}

extension String: Error {}
