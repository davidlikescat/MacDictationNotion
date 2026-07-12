import Foundation

public struct Settings: Codable {
    public var notionToken: String
    public var databaseId: String
    public var titleProperty: String
    public var locale: String
    public var notePrefix: String
    public var notionVersion: String
    public var hotkeyKeyCode: Int
    public var hotkeyModifiers: Int
    public var llmRefine: Bool
    public var ollamaModel: String
    public var ollamaBaseURL: String

    enum CodingKeys: String, CodingKey {
        case notionToken, databaseId, titleProperty, locale, notePrefix, notionVersion,
             hotkeyKeyCode, hotkeyModifiers, llmRefine, ollamaModel, ollamaBaseURL
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        notionToken     = try c.decodeIfPresent(String.self, forKey: .notionToken)     ?? ""
        databaseId      = try c.decodeIfPresent(String.self, forKey: .databaseId)      ?? ""
        titleProperty   = try c.decodeIfPresent(String.self, forKey: .titleProperty)   ?? "Name"
        locale          = try c.decodeIfPresent(String.self, forKey: .locale)          ?? "ko-KR"
        notePrefix      = try c.decodeIfPresent(String.self, forKey: .notePrefix)      ?? "음성 메모:"
        notionVersion   = try c.decodeIfPresent(String.self, forKey: .notionVersion)   ?? "2022-06-28"
        hotkeyKeyCode   = try c.decodeIfPresent(Int.self,    forKey: .hotkeyKeyCode)   ?? 2
        hotkeyModifiers = try c.decodeIfPresent(Int.self,    forKey: .hotkeyModifiers) ?? 768
        llmRefine       = try c.decodeIfPresent(Bool.self,   forKey: .llmRefine)       ?? false
        ollamaModel     = try c.decodeIfPresent(String.self, forKey: .ollamaModel)     ?? "qwen2.5:7b"
        ollamaBaseURL   = try c.decodeIfPresent(String.self, forKey: .ollamaBaseURL)   ?? "http://localhost:11434"
    }

    public var isValid: Bool {
        !notionToken.isEmpty && !databaseId.isEmpty && !titleProperty.isEmpty
    }

    public static var configDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("MacDictationNotion", isDirectory: true)
    }

    public static var configURL: URL {
        configDirectory.appendingPathComponent("config.json")
    }

    public static func load() throws -> Settings {
        let data = try Data(contentsOf: configURL)
        var settings = try JSONDecoder().decode(Settings.self, from: data)
        let env = ProcessInfo.processInfo.environment
        if let token = env["NOTION_TOKEN"],       !token.isEmpty { settings.notionToken = token }
        if let db    = env["NOTION_DATABASE_ID"], !db.isEmpty    { settings.databaseId  = db }
        return settings
    }

    @discardableResult
    public static func ensureExampleExists() -> URL {
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
              "notionVersion": "2022-06-28",
              "hotkeyKeyCode": 2,
              "hotkeyModifiers": 768
            }
            """
            try? template.data(using: .utf8)?.write(to: url, options: .atomic)
        }
        return url
    }
}
