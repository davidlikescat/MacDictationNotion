import XCTest
@testable import MacDictationNotionCore

final class NotionClientTests: XCTestCase {

    // MARK: - NotionError.isRetryable

    func test_network_isRetryable() {
        XCTAssertTrue(NotionError.network(URLError(.notConnectedToInternet)).isRetryable)
    }

    func test_http_429_isRetryable() {
        XCTAssertTrue(NotionError.http(status: 429, message: "rate limited").isRetryable)
    }

    func test_http_500_isRetryable() {
        XCTAssertTrue(NotionError.http(status: 500, message: "server error").isRetryable)
    }

    func test_http_503_isRetryable() {
        XCTAssertTrue(NotionError.http(status: 503, message: "unavailable").isRetryable)
    }

    func test_http_401_notRetryable() {
        XCTAssertFalse(NotionError.http(status: 401, message: "unauthorized").isRetryable)
    }

    func test_http_404_notRetryable() {
        XCTAssertFalse(NotionError.http(status: 404, message: "not found").isRetryable)
    }

    func test_http_400_notRetryable() {
        XCTAssertFalse(NotionError.http(status: 400, message: "bad request").isRetryable)
    }

    func test_encoding_notRetryable() {
        XCTAssertFalse(NotionError.encoding.isRetryable)
    }

    // MARK: - NotionError.userMessage

    func test_userMessage_containsStatusCode() {
        let msg = NotionError.http(status: 401, message: "Bad token").userMessage
        XCTAssertTrue(msg.contains("401"))
    }

    func test_userMessage_truncatesLongMessage() {
        let long = String(repeating: "x", count: 200)
        let msg = NotionError.http(status: 400, message: long).userMessage
        XCTAssertLessThan(msg.count, long.count + 20)
    }

    func test_userMessage_network_containsDescription() {
        let err = URLError(.notConnectedToInternet)
        let msg = NotionError.network(err).userMessage
        XCTAssertFalse(msg.isEmpty)
    }

    func test_userMessage_encoding() {
        XCTAssertFalse(NotionError.encoding.userMessage.isEmpty)
    }
}
