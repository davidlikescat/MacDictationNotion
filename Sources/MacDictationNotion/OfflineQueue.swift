import Foundation

/// Persists transcripts that failed to send (e.g. offline) so they can be
/// retried when connectivity returns. Stored as JSON next to the config file.
final class OfflineQueue {
    struct Item: Codable, Equatable {
        let id: String
        let text: String
        let createdAt: Date
    }

    private let fileURL: URL
    private let lock = NSLock()

    init() {
        let dir = Settings.configDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("pending.json")
    }

    func load() -> [Item] {
        lock.lock(); defer { lock.unlock() }
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([Item].self, from: data)) ?? []
    }

    private func save(_ items: [Item]) {
        lock.lock(); defer { lock.unlock() }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(items) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    var count: Int { load().count }

    func enqueue(_ text: String) {
        var items = load()
        items.append(Item(id: UUID().uuidString, text: text, createdAt: Date()))
        save(items)
    }

    func remove(_ item: Item) {
        let items = load().filter { $0.id != item.id }
        save(items)
    }
}
