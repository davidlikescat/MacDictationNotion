import Foundation

/// User configuration loaded from `~/Library/Application Support/MacDictationNotion/config.json`.
/// Notion credentials can also be supplied via the environment variables
/// `NOTION_TOKEN` and `NOTION_DATABASE_ID`, which override the file values.
struct Settings: Codable {
    var notionToken: String
    var databaseId: String
    var titleProperty: String
    var locale: String
    var notePrefix: String
    var notionVersion: String

    enum CodingKeys: String, CodingKey {
        case notionToken, databaseId, titleProperty, locale, notePrefix, notionVersion
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        notionToken   = try c.decodeIfPresent(String.self, forKey: .notionToken)   ?? ""
        databaseId    = try c.decodeIfPresent(String.self, forKey: .databaseId)    ?? ""
        titleProperty = try c.decodeIfPresent(String.self, forKey: .titleProperty) ?? "Name"
        locale        = try c.decodeIfPresent(String.self, forKey: .locale)        ?? "ko-KR"
        notePrefix    = try c.decodeIfPresent(String.self, forKey: .notePrefix)    ?? "음성 메모:"
        notionVersion = try c.decodeIfPresent(String.self, forKey: .notionVersion) ?? "2022-06-28"
    }

    var isValid: Bool {
        !notionToken.isEmpty && !databaseId.isEmpty && !titleProperty.isEmpty
    }

    // MARK: - Paths

    static var configDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("MacDictationNotion", isDirectory: true)
    }

    static var configURL: URL {
        configDirectory.appendingPathComponent("config.json")
    }

    // MARK: - Loading

    static func load() throws -> Settings {
        let data = try Data(contentsOf: configURL)
        var settings = try JSONDecoder().decode(Settings.self, from: data)

        let env = ProcessInfo.processInfo.environment
        if let token = env["NOTION_TOKEN"], !token.isEmpty { settings.notionToken = token }
        if let db = env["NOTION_DATABASE_ID"], !db.isEmpty { settings.databaseId = db }
        return settings
    }

    /// Ensures the config directory exists and drops a template file if none is present.
    /// Returns the config file URL so callers can reveal it in Finder.
    @discardableResult
    static func ensureExampleExists() -> URL {
        let dir = configDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let url = configURL
        if !FileManager.default.fileExists(atPath: url.path) {
            let template = """
            {
              "notionToken": "secret_여기에_Notion_Integration_토큰을_입력",
              "databaseId": "여기에_32자리_데이터베이스_ID를_입력",
              "titleProperty": "Name",
              "locale": "ko-KR",
              "notePrefix": "음성 메모:",
              "notionVersion": "2022-06-28"
            }
            """
            try? template.data(using: .utf8)?.write(to: url, options: .atomic)
        }
        return url
    }
}
