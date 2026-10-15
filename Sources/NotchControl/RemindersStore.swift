import Foundation

/// Simple local reminders that fire in the notch, as a notification, and optionally in Slack.
final class RemindersStore: ObservableObject {
    struct Reminder: Identifiable, Codable, Equatable {
        var id = UUID()
        var title: String
        var due: Date?
        var notifySlack: Bool
        var fired = false
        var done = false
    }

    @Published private(set) var reminders: [Reminder] = []
    var onFire: ((Reminder) -> Void)?

    private var timer: Timer?
    private let fileURL = AppPaths.supportDir.appendingPathComponent("reminders.json")

    /// Open items: dated ones first (soonest first), then plain to-dos in the order added.
    var upcoming: [Reminder] {
        let open = reminders.filter { !$0.done }
        let dated = open.filter { $0.due != nil }.sorted { $0.due! < $1.due! }
        return dated + open.filter { $0.due == nil }
    }
    var doneToday: [Reminder] { reminders.filter { $0.done } }
    var dueCount: Int { reminders.filter { $0.fired && !$0.done }.count }

    func start() {
        load()
        check()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in self?.check() }
    }

    func add(title: String, due: Date?, notifySlack: Bool) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        reminders.append(Reminder(title: t, due: due, notifySlack: notifySlack))
        save()
    }

    func markDone(_ r: Reminder) {
        guard let i = reminders.firstIndex(where: { $0.id == r.id }) else { return }
        reminders[i].done = true
        save()
    }

    func toggleDone(_ r: Reminder) {
        guard let i = reminders.firstIndex(where: { $0.id == r.id }) else { return }
        reminders[i].done.toggle()
        save()
    }

    func clearDone() {
        reminders.removeAll { $0.done }
        save()
    }

    func remove(_ r: Reminder) {
        reminders.removeAll { $0.id == r.id }
        save()
    }

    private func check() {
        let now = Date()
        var changed = false
        for i in reminders.indices where !reminders[i].fired && !reminders[i].done && (reminders[i].due ?? .distantFuture) <= now {
            reminders[i].fired = true
            changed = true
            onFire?(reminders[i])
        }
        if changed { save() }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Reminder].self, from: data) else { return }
        reminders = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(reminders) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
