import Foundation

public enum NotionError: Error {
    case network(Error)
    case http(status: Int, message: String)
    case encoding

    public var isRetryable: Bool {
        switch self {
        case .network:                    return true
        case .http(let s, _):            return s == 429 || (500...599).contains(s)
        case .encoding:                   return false
        }
    }

    public var userMessage: String {
        switch self {
        case .network(let e):
            return "네트워크 오류: \(e.localizedDescription)"
        case .http(let s, let msg):
            let short = msg.count > 140 ? String(msg.prefix(140)) + "…" : msg
            return "HTTP \(s): \(short)"
        case .encoding:
            return "요청 생성에 실패했습니다."
        }
    }
}

public final class NotionClient {
    private let settings: Settings
    private let session: URLSession

    public init(settings: Settings, session: URLSession = .shared) {
        self.settings = settings
        self.session = session
    }

    private func requestBody(text: String) -> [String: Any] {
        let prefix = settings.notePrefix.trimmingCharacters(in: .whitespaces)
        let titleText = prefix.isEmpty ? text : "\(prefix) \(text)"
        return [
            "parent": ["database_id": settings.databaseId],
            "properties": [
                settings.titleProperty: [
                    "title": [["type": "text", "text": ["content": String(titleText.prefix(1900))]]]
                ]
            ],
            "children": [[
                "object": "block", "type": "paragraph",
                "paragraph": ["rich_text": [["type": "text", "text": ["content": String(text.prefix(1900))]]]]
            ]],
        ]
    }

    public func send(text: String, completion: @escaping (Result<Void, NotionError>) -> Void) {
        guard let url = URL(string: "https://api.notion.com/v1/pages") else {
            completion(.failure(.encoding)); return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(settings.notionToken)", forHTTPHeaderField: "Authorization")
        req.setValue(settings.notionVersion,           forHTTPHeaderField: "Notion-Version")
        req.setValue("application/json",               forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 20
        do {
            req.httpBody = try JSONSerialization.data(withJSONObject: requestBody(text: text))
        } catch { completion(.failure(.encoding)); return }

        session.dataTask(with: req) { data, response, error in
            if let error = error { completion(.failure(.network(error))); return }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure(.network(URLError(.badServerResponse)))); return
            }
            if (200...299).contains(http.statusCode) {
                completion(.success(()))
            } else {
                let msg = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                completion(.failure(.http(status: http.statusCode, message: msg)))
            }
        }.resume()
    }
}
