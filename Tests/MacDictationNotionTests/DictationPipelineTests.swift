import XCTest
@testable import MacDictationNotionCore

// MARK: - Mock speech recognizer

final class MockSpeechRecognizer: SpeechRecognizing {
    var onPartial: ((String) -> Void)?
    var onAudioLevel: ((Float) -> Void)?
    private(set) var isRecording = false

    var startError: Error? = nil
    var finalTranscript: String = "안녕하세요 테스트입니다"
    var partials: [String] = []

    func startRecording() throws {
        if let e = startError { throw e }
        isRecording = true
        partials.forEach { onPartial?($0) }
    }

    func stopRecording(completion: @escaping (String) -> Void) {
        isRecording = false
        completion(finalTranscript)
    }

    func cancelRecording() {
        isRecording = false
    }
}

// MARK: - URL stubs (reuse pattern from NotionClientTests)

private final class NotionSuccessProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "api.notion.com"
    }
    override class func canonicalRequest(for r: URLRequest) -> URLRequest { r }
    override func startLoading() {
        let body = #"{"object":"page","id":"abc"}"#
        let resp = HTTPURLResponse(url: request.url!, statusCode: 200,
                                   httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class NotionFailProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "api.notion.com"
    }
    override class func canonicalRequest(for r: URLRequest) -> URLRequest { r }
    override func startLoading() {
        let body = #"{"object":"error","status":400,"code":"validation_error","message":"bad"}"#
        let resp = HTTPURLResponse(url: request.url!, statusCode: 400,
                                   httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class OllamaSuccessProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "localhost"
    }
    override class func canonicalRequest(for r: URLRequest) -> URLRequest { r }
    override func startLoading() {
        let body = #"{"message":{"content":"정제된 텍스트입니다."}}"#
        let resp = HTTPURLResponse(url: request.url!, statusCode: 200,
                                   httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class OllamaFailProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "localhost"
    }
    override class func canonicalRequest(for r: URLRequest) -> URLRequest { r }
    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}

// MARK: - Helpers

private func makeSettings(llmRefine: Bool = false) throws -> Settings {
    let json = """
    {"notionToken":"tok","databaseId":"db","titleProperty":"Name",
     "llmRefine":\(llmRefine),"ollamaModel":"qwen2.5:7b"}
    """
    return try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
}

private func session(protocols: [URLProtocol.Type]) -> URLSession {
    let cfg = URLSessionConfiguration.ephemeral
    cfg.protocolClasses = protocols
    return URLSession(configuration: cfg)
}

// MARK: - Tests

final class DictationPipelineTests: XCTestCase {

    // 1. 정상 전송 — STT 결과가 Notion에 도착
    func test_fullPipeline_success_sendsText() throws {
        let recognizer = MockSpeechRecognizer()
        recognizer.finalTranscript = "노션에 전송할 내용"
        let settings = try makeSettings()
        let client   = NotionClient(settings: settings,
                                    session: session(protocols: [NotionSuccessProtocol.self]))
        let refiner  = LLMRefiner(settings: settings)
        let pipeline = DictationPipeline(recognizer: recognizer, refiner: refiner, client: client)

        let exp = expectation(description: "success")
        pipeline.onSuccess = { text in
            XCTAssertEqual(text, "노션에 전송할 내용")
            exp.fulfill()
        }
        try pipeline.start()
        pipeline.stop()
        wait(for: [exp], timeout: 2)
    }

    // 2. LLM 정제 ON — 정제된 텍스트가 Notion에 전송됨
    func test_llmOn_sendsRefinedText() throws {
        let recognizer = MockSpeechRecognizer()
        recognizer.finalTranscript = "어 음 테스트야"
        let settings = try makeSettings(llmRefine: true)
        let client   = NotionClient(settings: settings,
                                    session: session(protocols: [NotionSuccessProtocol.self]))
        let refiner  = LLMRefiner(settings: settings,
                                  session: session(protocols: [OllamaSuccessProtocol.self]))
        let pipeline = DictationPipeline(recognizer: recognizer, refiner: refiner, client: client)

        let exp = expectation(description: "refined")
        pipeline.onSuccess = { text in
            XCTAssertEqual(text, "정제된 텍스트입니다.")
            exp.fulfill()
        }
        try pipeline.start()
        pipeline.stop()
        wait(for: [exp], timeout: 2)
    }

    // 3. LLM 실패 시 원문 fallback — Notion은 원문 수신
    func test_llmFail_fallbackToOriginal() throws {
        let recognizer = MockSpeechRecognizer()
        recognizer.finalTranscript = "원문 텍스트"
        let settings = try makeSettings(llmRefine: true)
        let client   = NotionClient(settings: settings,
                                    session: session(protocols: [NotionSuccessProtocol.self]))
        let refiner  = LLMRefiner(settings: settings,
                                  session: session(protocols: [OllamaFailProtocol.self]))
        let pipeline = DictationPipeline(recognizer: recognizer, refiner: refiner, client: client)

        let exp = expectation(description: "fallback")
        pipeline.onSuccess = { text in
            XCTAssertEqual(text, "원문 텍스트")
            exp.fulfill()
        }
        try pipeline.start()
        pipeline.stop()
        wait(for: [exp], timeout: 2)
    }

    // 4. 빈 전사 결과 — onFailure(.emptyTranscript) 호출
    func test_emptyTranscript_callsFailure() throws {
        let recognizer = MockSpeechRecognizer()
        recognizer.finalTranscript = "   "
        let settings = try makeSettings()
        let pipeline = DictationPipeline(
            recognizer: recognizer,
            refiner: LLMRefiner(settings: settings),
            client: NotionClient(settings: settings,
                                 session: session(protocols: [NotionSuccessProtocol.self]))
        )

        let exp = expectation(description: "empty")
        pipeline.onFailure = { error in
            XCTAssertEqual(error, .emptyTranscript)
            exp.fulfill()
        }
        try pipeline.start()
        pipeline.stop()
        wait(for: [exp], timeout: 2)
    }

    // 5. 취소 — Notion 호출 없음, isRecording = false
    func test_cancel_stopsRecording_noNotionCall() throws {
        let recognizer = MockSpeechRecognizer()
        let settings   = try makeSettings()
        let pipeline   = DictationPipeline(
            recognizer: recognizer,
            refiner: LLMRefiner(settings: settings),
            client: NotionClient(settings: settings,
                                 session: session(protocols: [NotionSuccessProtocol.self]))
        )
        pipeline.onSuccess = { _ in XCTFail("success should not be called after cancel") }

        try pipeline.start()
        XCTAssertTrue(recognizer.isRecording)
        pipeline.cancel()
        XCTAssertFalse(recognizer.isRecording)
        XCTAssertEqual(pipeline.state, .idle)
    }

    // 6. start 오류 — onFailure(.recognizerError) + throws
    func test_startError_propagatesFailure() throws {
        let recognizer = MockSpeechRecognizer()
        recognizer.startError = NSError(domain: "test", code: -1,
                                        userInfo: [NSLocalizedDescriptionKey: "권한 없음"])
        let settings = try makeSettings()
        let pipeline = DictationPipeline(
            recognizer: recognizer,
            refiner: LLMRefiner(settings: settings),
            client: NotionClient(settings: settings,
                                 session: session(protocols: [NotionSuccessProtocol.self]))
        )

        let exp = expectation(description: "error")
        pipeline.onFailure = { error in
            if case .recognizerError = error { exp.fulfill() }
        }
        XCTAssertThrowsError(try pipeline.start())
        wait(for: [exp], timeout: 1)
    }

    // 7. Notion HTTP 400 — onFailure(.notionError) 호출
    func test_notionError_callsFailure() throws {
        let recognizer = MockSpeechRecognizer()
        recognizer.finalTranscript = "내용"
        let settings = try makeSettings()
        let pipeline = DictationPipeline(
            recognizer: recognizer,
            refiner: LLMRefiner(settings: settings),
            client: NotionClient(settings: settings,
                                 session: session(protocols: [NotionFailProtocol.self]))
        )

        let exp = expectation(description: "notion error")
        pipeline.onFailure = { error in
            if case .notionError(let e) = error,
               case .http(let status, _) = e {
                XCTAssertEqual(status, 400)
                exp.fulfill()
            }
        }
        try pipeline.start()
        pipeline.stop()
        wait(for: [exp], timeout: 2)
    }

    // 8. 상태 전이 검증 — idle→recording→refining→sending→idle
    func test_stateTransitions() throws {
        let recognizer = MockSpeechRecognizer()
        recognizer.finalTranscript = "상태 전이 테스트"
        let settings = try makeSettings(llmRefine: true)
        let client   = NotionClient(settings: settings,
                                    session: session(protocols: [NotionSuccessProtocol.self]))
        let refiner  = LLMRefiner(settings: settings,
                                  session: session(protocols: [OllamaSuccessProtocol.self]))
        let pipeline = DictationPipeline(recognizer: recognizer, refiner: refiner, client: client)

        var states: [DictationPipeline.State] = []
        pipeline.onStateChange = { states.append($0) }

        let exp = expectation(description: "done")
        pipeline.onSuccess = { _ in exp.fulfill() }

        XCTAssertEqual(pipeline.state, .idle)
        try pipeline.start()
        XCTAssertEqual(pipeline.state, .recording)
        pipeline.stop()
        wait(for: [exp], timeout: 3)

        XCTAssertTrue(states.contains(.recording))
        XCTAssertTrue(states.contains(.refining))
        XCTAssertTrue(states.contains(.sending))
        XCTAssertEqual(pipeline.state, .idle)
    }

    // 9. 부분 전사 콜백 전달 검증
    func test_partialTranscripts_forwarded() throws {
        let recognizer = MockSpeechRecognizer()
        recognizer.partials = ["안녕", "안녕하세요"]
        recognizer.finalTranscript = "안녕하세요"
        let settings = try makeSettings()
        let pipeline = DictationPipeline(
            recognizer: recognizer,
            refiner: LLMRefiner(settings: settings),
            client: NotionClient(settings: settings,
                                 session: session(protocols: [NotionSuccessProtocol.self]))
        )

        var received: [String] = []
        pipeline.onPartialTranscript = { received.append($0) }

        let exp = expectation(description: "done")
        pipeline.onSuccess = { _ in exp.fulfill() }
        try pipeline.start()
        pipeline.stop()
        wait(for: [exp], timeout: 2)

        XCTAssertEqual(received, ["안녕", "안녕하세요"])
    }

    // 10. 녹음 중이 아닐 때 stop/cancel 은 no-op
    func test_stop_whenIdle_isNoOp() throws {
        let recognizer = MockSpeechRecognizer()
        let settings   = try makeSettings()
        let pipeline   = DictationPipeline(
            recognizer: recognizer,
            refiner: LLMRefiner(settings: settings),
            client: NotionClient(settings: settings,
                                 session: session(protocols: [NotionSuccessProtocol.self]))
        )
        pipeline.onFailure = { _ in XCTFail("should not fail") }
        pipeline.stop()
        pipeline.cancel()
        XCTAssertEqual(pipeline.state, .idle)
    }
}
