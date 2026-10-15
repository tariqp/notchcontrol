import AppKit
import Foundation
import UniformTypeIdentifiers

/// Files dropped onto the notch, kept until the user drags them out or removes them.
final class ShelfStore: ObservableObject {
    struct Item: Identifiable, Equatable {
        let url: URL
        var id: String { url.path }
        var name: String { url.lastPathComponent }
        var icon: NSImage { NSWorkspace.shared.icon(forFile: url.path) }
        var exists: Bool { FileManager.default.fileExists(atPath: url.path) }
    }

    @Published private(set) var items: [Item] = []
    private let key = "shelf.paths"

    init() {
        let paths = UserDefaults.standard.stringArray(forKey: key) ?? []
        items = paths.map { Item(url: URL(fileURLWithPath: $0)) }.filter(\.exists)
    }

    func add(_ urls: [URL]) {
        for url in urls where url.isFileURL && !items.contains(where: { $0.url == url }) {
            items.insert(Item(url: url), at: 0)
        }
        if items.count > 40 { items.removeLast(items.count - 40) }
        save()
    }

    /// Reads file URLs out of drop providers and adds them.
    func add(providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !fileProviders.isEmpty else { return false }
        for p in fileProviders {
            p.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { [weak self] data, _ in
                var url: URL?
                if let d = data as? Data { url = URL(dataRepresentation: d, relativeTo: nil) }
                else if let u = data as? URL { url = u }
                guard let url else { return }
                DispatchQueue.main.async { self?.add([url]) }
            }
        }
        return true
    }

    func remove(_ item: Item) { items.removeAll { $0 == item }; save() }
    func clear() { items.removeAll(); save() }

    private func save() { UserDefaults.standard.set(items.map(\.url.path), forKey: key) }
}
