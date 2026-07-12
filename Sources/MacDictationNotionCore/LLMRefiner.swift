import Foundation

public final class LLMRefiner {
    private let settings: Settings
    private let session: URLSession

    public init(settings: Settings, session: URLSession = .shared) {
        self.settings = settings
        self.session  = session
    }

    public func refine(text: String, completion: @escaping (String) -> Void) {
        guard settings.llmRefine else { completion(text); return }

        let baseURL = settings.ollamaBaseURL.hasSuffix("/")
            ? String(settings.ollamaBaseURL.dropLast())
            : settings.ollamaBaseURL

        guard let url = URL(string: "\(baseURL)/api/chat") else {
            completion(text); return
        }

        let body: [String: Any] = [
            "model": settings.ollamaModel,
            "stream": false,
            "messages": [
                [
                    "role": "system",
                    "content": """
                    당신은 한국어 음성 인식(STT) 텍스트 정제 전문가입니다.
                    규칙:
                    - 받아쓰기 오류·발음 오인식 교정
                    - 필러 단어 제거 (어, 음, 저, 그, 뭐, 아)
                    - 구어체를 자연스러운 문어체로
                    - 원본 의미 절대 변경 금지
                    - 정제된 텍스트만 출력, 설명·따옴표·부연 금지
                    """
                ],
                [
                    "role": "user",
                    "content": text
                ]
            ]
        ]

        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
            completion(text); return
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = httpBody
        req.timeoutInterval = 30

        session.dataTask(with: req) { data, response, error in
            guard error == nil,
                  let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let message = json["message"] as? [String: Any],
                  let content = message["content"] as? String,
                  !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                completion(text); return
            }
            let refined = content.trimmingCharacters(in: .whitespacesAndNewlines)
            completion(refined)
        }.resume()
    }
}
