import XCTest
@testable import MacDictationNotionCore

final class OfflineQueueTests: XCTestCase {

    private var tempURL: URL!
    private var queue: OfflineQueue!

    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".json")
        queue = OfflineQueue(fileURL: tempURL)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempURL)
        super.tearDown()
    }

    // MARK: - Empty state

    func test_startsEmpty() {
        XCTAssertEqual(queue.count, 0)
        XCTAssertTrue(queue.load().isEmpty)
    }

    // MARK: - Enqueue

    func test_enqueue_incrementsCount() {
        queue.enqueue("hello")
        XCTAssertEqual(queue.count, 1)
    }

    func test_enqueue_storesText() {
        queue.enqueue("hello world")
        XCTAssertEqual(queue.load().first?.text, "hello world")
    }

    func test_enqueue_multiple() {
        queue.enqueue("a"); queue.enqueue("b"); queue.enqueue("c")
        XCTAssertEqual(queue.count, 3)
    }

    func test_enqueue_assignsNonEmptyID() {
        queue.enqueue("test")
        XCTAssertFalse(queue.load().first!.id.isEmpty)
    }

    func test_enqueue_assignsUniqueIDs() {
        queue.enqueue("a"); queue.enqueue("b")
        let items = queue.load()
        XCTAssertNotEqual(items[0].id, items[1].id)
    }

    // MARK: - Remove

    func test_remove_decreasesCount() {
        queue.enqueue("to remove")
        queue.remove(queue.load().first!)
        XCTAssertEqual(queue.count, 0)
    }

    func test_remove_onlyTargetItem() {
        queue.enqueue("keep"); queue.enqueue("remove")
        let toRemove = queue.load().last!
        queue.remove(toRemove)
        XCTAssertEqual(queue.count, 1)
        XCTAssertEqual(queue.load().first?.text, "keep")
    }

    func test_remove_nonExistentItem_noChange() {
        queue.enqueue("item")
        let ghost = OfflineQueue.Item(id: "nonexistent", text: "ghost", createdAt: Date())
        queue.remove(ghost)
        XCTAssertEqual(queue.count, 1)
    }

    // MARK: - Persistence

    func test_persistence_acrossInstances() {
        queue.enqueue("persistent")
        let queue2 = OfflineQueue(fileURL: tempURL)
        XCTAssertEqual(queue2.count, 1)
        XCTAssertEqual(queue2.load().first?.text, "persistent")
    }

    func test_persistence_afterRemove() {
        queue.enqueue("a"); queue.enqueue("b")
        queue.remove(queue.load().first!)
        let queue2 = OfflineQueue(fileURL: tempURL)
        XCTAssertEqual(queue2.count, 1)
    }
}
