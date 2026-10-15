import EventKit
import Foundation

/// Upcoming calendar events from the system calendar (EventKit).
final class CalendarService: ObservableObject {
    struct Event: Identifiable, Equatable {
        let id: String
        let title: String
        let start: Date
        let end: Date
        let isAllDay: Bool
        let calendar: String
        let location: String?
        let url: URL?
        let notes: String?

        /// A video-call link found in the event's URL, location or notes.
        var meetingURL: URL? {
            let hosts = ["zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com", "webex.com",
                         "whereby.com", "meet.jit.si", "gather.town", "around.co", "discord.gg", "slack.com/huddle"]
            var candidates: [String] = []
            if let url { candidates.append(url.absoluteString) }
            for text in [location, notes].compactMap({ $0 }) {
                let ns = text as NSString
                let regex = try? NSRegularExpression(pattern: "https?://[^\\s<>\"']+")
                regex?.matches(in: text, range: NSRange(location: 0, length: ns.length)).forEach { candidates.append(ns.substring(with: $0.range)) }
            }
            for c in candidates {
                let trimmed = c.trimmingCharacters(in: CharacterSet(charactersIn: ".,;)"))
                if hosts.contains(where: { trimmed.contains($0) }), let u = URL(string: trimmed) { return u }
            }
            return nil
        }
    }

    enum Access { case unknown, granted, denied, unavailable }

    @Published private(set) var events: [Event] = []
    @Published private(set) var access: Access = .unknown

    private let store = EKEventStore()
    private var timer: Timer?

    /// The next timed event that has not ended yet.
    var next: Event? {
        let now = Date()
        return events.first { !$0.isAllDay && $0.end > now }
    }

    func start() {
        guard Bundle.main.bundleIdentifier != nil else { access = .unavailable; return } // TCC needs a real bundle
        store.requestFullAccessToEvents { [weak self] granted, _ in
            DispatchQueue.main.async {
                self?.access = granted ? .granted : .denied
                if granted {
                    self?.refresh()
                    self?.timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in self?.refresh() }
                }
            }
        }
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            self?.refresh()
        }
    }

    func refresh() {
        guard access == .granted else { return }
        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: 2, to: start) ?? start
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let found = store.events(matching: predicate)
            .filter { $0.endDate > Date() }
            .sorted { $0.startDate < $1.startDate }
            .prefix(20)
            .map { e in
                Event(id: e.eventIdentifier ?? UUID().uuidString, title: e.title ?? "Untitled",
                      start: e.startDate, end: e.endDate, isAllDay: e.isAllDay,
                      calendar: e.calendar.title, location: e.location, url: e.url, notes: e.notes)
            }
        events = Array(found)
    }
}
