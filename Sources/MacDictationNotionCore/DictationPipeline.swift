import Foundation

public final class DictationPipeline {

    public enum State: Equatable {
        case idle, recording, refining, sending
    }

    public enum PipelineError: Error, Equatable {
        case emptyTranscript
        case notionError(NotionError)
        case recognizerError(String)

        public static func == (lhs: PipelineError, rhs: PipelineError) -> Bool {
            switch (lhs, rhs) {
            case (.emptyTranscript, .emptyTranscript): return true
            case (.recognizerError(let a), .recognizerError(let b)): return a == b
            case (.notionError(let a), .notionError(let b)):
                switch (a, b) {
                case (.encoding, .encoding): return true
                case (.http(let s1, _), .http(let s2, _)): return s1 == s2
                default: return false
                }
            default: return false
            }
        }
    }

    // MARK: - Callbacks (all called on the main thread)
    public var onStateChange: ((State) -> Void)?
    public var onPartialTranscript: ((String) -> Void)?
    public var onAudioLevel: ((Float) -> Void)?
    public var onSuccess: ((String) -> Void)?
    public var onFailure: ((PipelineError) -> Void)?

    // MARK: - Dependencies
    private let recognizer: any SpeechRecognizing
    private let refiner:    LLMRefiner
    private let client:     NotionClient

    private(set) public var state: State = .idle {
        didSet {
            let s = state  // capture current value, not lazy self.state
            DispatchQueue.main.async { self.onStateChange?(s) }
        }
    }

    public init(recognizer: any SpeechRecognizing,
                refiner: LLMRefiner,
                client: NotionClient) {
        self.recognizer = recognizer
        self.refiner    = refiner
        self.client     = client
    }

    // MARK: - Public API

    public func start() throws {
        guard state == .idle else { return }
        recognizer.onPartial = { [weak self] text in
            DispatchQueue.main.async { self?.onPartialTranscript?(text) }
        }
        recognizer.onAudioLevel = { [weak self] level in
            self?.onAudioLevel?(level)
        }
        do {
            try recognizer.startRecording()
        } catch {
            onFailure?(.recognizerError(error.localizedDescription))
            throw error
        }
        state = .recording
    }

    public func stop() {
        guard state == .recording else { return }
        recognizer.stopRecording { [weak self] text in   // main thread
            guard let self = self else { return }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                self.state = .idle
                self.onFailure?(.emptyTranscript)
                return
            }
            self.state = .refining
            self.refiner.refine(text: trimmed) { [weak self] refined in  // bg thread
                guard let self = self else { return }
                DispatchQueue.main.async {
                    self.state = .sending
                    self.client.send(text: refined) { [weak self] result in  // bg thread
                        guard let self = self else { return }
                        DispatchQueue.main.async {
                            self.state = .idle
                            switch result {
                            case .success:
                                self.onSuccess?(refined)
                            case .failure(let e):
                                self.onFailure?(.notionError(e))
                            }
                        }
                    }
                }
            }
        }
    }

    public func cancel() {
        guard state == .recording else { return }
        recognizer.cancelRecording()
        state = .idle
    }
}
