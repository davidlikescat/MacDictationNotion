import XCTest
@testable import MacDictationNotionCore

final class LLMRefinerTests: XCTestCase {

    private func makeSettings(llmRefine: Bool = false, model: String = "qwen2.5:7b") throws -> Settings {
        let json = """
        {
          "notionToken": "tok",
          "databaseId": "db",
          "llmRefine": \(llmRefine),
          "ollamaModel": "\(model)"
        }
        """
        return try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
    }

    // llmRefine=false이면 네트워크 호출 없이 원문 그대로 반환
    func test_passthrough_when_disabled() throws {
        let settings = try makeSettings(llmRefine: false)
        let refiner  = LLMRefiner(settings: settings)
        let exp = expectation(description: "passthrough")
        refiner.refine(text: "테스트 원문") { result in
            XCTAssertEqual(result, "테스트 원문")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }

    // Ollama가 없으면 원문 fallback
    func test_fallback_on_network_error() throws {
        let settings = try makeSettings(llmRefine: true)
        let config   = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FailingURLProtocol.self]
        let session  = URLSession(configuration: config)
        let refiner  = LLMRefiner(settings: settings, session: session)

        let exp = expectation(description: "fallback")
        refiner.refine(text: "원문 텍스트") { result in
            XCTAssertEqual(result, "원문 텍스트")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)
    }

    // Ollama가 빈 content 반환하면 원문 fallback
    func test_fallback_on_empty_response() throws {
        let settings = try makeSettings(llmRefine: true)
        let config   = URLSessionConfiguration.ephemeral
        config.protocolClasses = [EmptyContentURLProtocol.self]
        let session  = URLSession(configuration: config)
        let refiner  = LLMRefiner(settings: settings, session: session)

        let exp = expectation(description: "empty fallback")
        refiner.refine(text: "원문") { result in
            XCTAssertEqual(result, "원문")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)
    }

    // 정상 응답이면 정제된 텍스트 반환
    func test_returns_refined_text() throws {
        let settings = try makeSettings(llmRefine: true)
        let config   = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SuccessURLProtocol.self]
        let session  = URLSession(configuration: config)
        let refiner  = LLMRefiner(settings: settings, session: session)

        let exp = expectation(description: "refined")
        refiner.refine(text: "어 음 테스트 텍스트야") { result in
            XCTAssertEqual(result, "테스트 텍스트입니다.")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)
    }

    // Settings 기본값 검증
    func test_default_llmRefine_is_false() throws {
        let s = try makeSettings()
        XCTAssertFalse(s.llmRefine)
    }

    func test_default_ollamaModel() throws {
        let s = try makeSettings()
        XCTAssertEqual(s.ollamaModel, "qwen2.5:7b")
    }

    func test_default_ollamaBaseURL() throws {
        let s = try makeSettings()
        XCTAssertEqual(s.ollamaBaseURL, "http://localhost:11434")
    }
}

// MARK: - URLProtocol stubs

private final class FailingURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}

private final class EmptyContentURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let body = #"{"message":{"content":"   "}}"#
        let data = Data(body.utf8)
        let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class SuccessURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let body = #"{"message":{"content":"테스트 텍스트입니다."}}"#
        let data = Data(body.utf8)
        let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
