import Foundation

enum NotionError: Error {
    case network(Error)
    case http(status: Int, message: String)
    case encoding

    /// Whether it is worth queuing the item for a later retry.
    var isRetryable: Bool {
        switch self {
        case .network:
            return true
        case .http(let status, _):
            return status == 429 || (500...599).contains(status)
        case .encoding:
            return false
        }
    }

    var userMessage: String {
        switch self {
        case .network(let error):
            return "네트워크 오류: \(error.localizedDescription)"
        case .http(let status, let message):
            let short = message.count > 140 ? String(message.prefix(140)) + "…" : message
            return "HTTP \(status): \(short)"
        case .encoding:
            return "요청 생성에 실패했습니다."
        }
    }
}

/// Creates a new page in a Notion database via the official REST API.
final class NotionClient {
    private let settings: Settings
    private let session: URLSession

    init(settings: Settings, session: URLSession = .shared) {
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
                    "title": [
                        ["type": "text", "text": ["content": String(titleText.prefix(1900))]]
                    ]
                ]
            ],
            "children": [
                [
                    "object": "block",
                    "type": "paragraph",
                    "paragraph": [
                        "rich_text": [
                            ["type": "text", "text": ["content": String(text.prefix(1900))]]
                        ]
                    ]
                ]
            ]
        ]
    }

    func send(text: String, completion: @escaping (Result<Void, NotionError>) -> Void) {
        guard let url = URL(string: "https://api.notion.com/v1/pages") else {
            completion(.failure(.encoding)); return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(settings.notionToken)", forHTTPHeaderField: "Authorization")
        request.setValue(settings.notionVersion, forHTTPHeaderField: "Notion-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody(text: text))
        } catch {
            completion(.failure(.encoding)); return
        }

        session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(.network(error))); return
            }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure(.network(URLError(.badServerResponse)))); return
            }
            if (200...299).contains(http.statusCode) {
                completion(.success(()))
            } else {
                let message = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                completion(.failure(.http(status: http.statusCode, message: message)))
            }
        }.resume()
    }
}
