import XCTest
@testable import MacDictationNotionCore

final class SettingsTests: XCTestCase {

    private func decode(_ json: String) throws -> Settings {
        try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
    }

    // MARK: - Defaults

    func test_defaults_titleProperty() throws {
        let s = try decode(#"{"notionToken":"t","databaseId":"d"}"#)
        XCTAssertEqual(s.titleProperty, "Name")
    }

    func test_defaults_locale() throws {
        let s = try decode(#"{"notionToken":"t","databaseId":"d"}"#)
        XCTAssertEqual(s.locale, "ko-KR")
    }

    func test_defaults_notePrefix() throws {
        let s = try decode(#"{"notionToken":"t","databaseId":"d"}"#)
        XCTAssertEqual(s.notePrefix, "음성 메모:")
    }

    func test_defaults_hotkey() throws {
        let s = try decode(#"{"notionToken":"t","databaseId":"d"}"#)
        XCTAssertEqual(s.hotkeyKeyCode,   2)    // kVK_ANSI_D
        XCTAssertEqual(s.hotkeyModifiers, 768)  // cmdKey | shiftKey
    }

    // MARK: - isValid

    func test_isValid_bothPresent() throws {
        let s = try decode(#"{"notionToken":"tok","databaseId":"db"}"#)
        XCTAssertTrue(s.isValid)
    }

    func test_isValid_emptyToken() throws {
        let s = try decode(#"{"notionToken":"","databaseId":"db"}"#)
        XCTAssertFalse(s.isValid)
    }

    func test_isValid_emptyDbId() throws {
        let s = try decode(#"{"notionToken":"tok","databaseId":""}"#)
        XCTAssertFalse(s.isValid)
    }

    // MARK: - Custom values

    func test_customLocale() throws {
        let s = try decode(#"{"notionToken":"t","databaseId":"d","locale":"en-US"}"#)
        XCTAssertEqual(s.locale, "en-US")
    }

    func test_customHotkey() throws {
        let s = try decode(#"{"notionToken":"t","databaseId":"d","hotkeyKeyCode":15,"hotkeyModifiers":256}"#)
        XCTAssertEqual(s.hotkeyKeyCode, 15)
        XCTAssertEqual(s.hotkeyModifiers, 256)
    }

    func test_customNotePrefix_empty() throws {
        let s = try decode(#"{"notionToken":"t","databaseId":"d","notePrefix":""}"#)
        XCTAssertEqual(s.notePrefix, "")
    }

    func test_invalidJSON_throws() {
        XCTAssertThrowsError(try decode("not json"))
    }
}
