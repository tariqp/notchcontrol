import AppKit
import Foundation

/// Keeps a history of text copied to the clipboard.
final class ClipboardStore: ObservableObject {
    struct Item: Identifiable, Codable, Equatable {
        let id: UUID
        let text: String
        let date: Date
    }

    @Published private(set) var items: [Item] = []
    @Published var lastCopiedID: UUID?

    private var changeCount = NSPasteboard.general.changeCount
    private var timer: Timer?
    private let fileURL = AppPaths.supportDir.appendingPathComponent("clipboard.json")
    private static let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    var limit: Int {
        let v = UserDefaults.standard.integer(forKey: SettingsKey.clipboardLimit)
        return v > 0 ? v : 50
    }

    func start() {
        load()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.check() }
    }

    private func check() {
        let pb = NSPasteboard.general
        guard pb.changeCount != changeCount else { return }
        changeCount = pb.changeCount
        if pb.types?.contains(Self.concealed) == true { return } // password managers mark secrets this way
        guard let text = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return }
        items.removeAll { $0.text == text }
        items.insert(Item(id: UUID(), text: text, date: Date()), at: 0)
        if items.count > limit { items = Array(items.prefix(limit)) }
        save()
    }

    func copy(_ item: Item) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(item.text, forType: .string)
        changeCount = pb.changeCount
        lastCopiedID = item.id
        items.removeAll { $0.id == item.id }
        items.insert(Item(id: item.id, text: item.text, date: Date()), at: 0)
        save()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            if self?.lastCopiedID == item.id { self?.lastCopiedID = nil }
        }
    }

    func remove(_ item: Item) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func clear() {
        items.removeAll()
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Item].self, from: data) else { return }
        items = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
