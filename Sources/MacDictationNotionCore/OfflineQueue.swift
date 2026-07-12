import Foundation

public final class OfflineQueue {
    public struct Item: Codable, Equatable {
        public let id: String
        public let text: String
        public let createdAt: Date
    }

    private let fileURL: URL
    private let lock = NSLock()

    public init() {
        let dir = Settings.configDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("pending.json")
    }

    // Internal init for unit tests — allows injecting a temp file path.
    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() -> [Item] {
        lock.lock(); defer { lock.unlock() }
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([Item].self, from: data)) ?? []
    }

    private func save(_ items: [Item]) {
        lock.lock(); defer { lock.unlock() }
        let enc = JSONEncoder()
        enc.outputFormatting = .prettyPrinted
        if let data = try? enc.encode(items) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    public var count: Int { load().count }

    public func enqueue(_ text: String) {
        var items = load()
        items.append(Item(id: UUID().uuidString, text: text, createdAt: Date()))
        save(items)
    }

    public func remove(_ item: Item) {
        save(load().filter { $0.id != item.id })
    }
}
