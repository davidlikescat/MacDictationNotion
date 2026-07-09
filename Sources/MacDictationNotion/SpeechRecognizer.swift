import Foundation
import Speech
import AVFoundation

enum RecognizerError: LocalizedError {
    case unavailable
    case notAuthorized
    case audioEngineFailed(Error)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "음성 인식을 사용할 수 없습니다. (해당 언어가 준비되지 않았거나 마이크가 없음)"
        case .notAuthorized:
            return "음성 인식/마이크 권한이 없습니다. 시스템 설정에서 허용해 주세요."
        case .audioEngineFailed(let error):
            return "마이크 시작 실패: \(error.localizedDescription)"
        }
    }
}

/// Captures microphone audio and transcribes it with the on-device speech engine
/// (the same technology that powers macOS Dictation — no external STT API, no cost).
final class SpeechRecognizer {
    private let recognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    private(set) var isRecording = false
    private var latestTranscript = ""
    private var onFinal: ((String) -> Void)?
    private var completionFired = false

    /// Live partial transcript callback (called on the main thread).
    var onPartial: ((String) -> Void)?

    init(localeIdentifier: String) {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier))
    }

    /// Requests both Speech Recognition and Microphone permission, reporting the
    /// combined result on the main thread.
    static func requestAuthorization(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { speechStatus in
            let speechOK = (speechStatus == .authorized)
            AVCaptureDevice.requestAccess(for: .audio) { micOK in
                DispatchQueue.main.async { completion(speechOK && micOK) }
            }
        }
    }

    func startRecording() throws {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            throw RecognizerError.notAuthorized
        }
        guard let recognizer = recognizer, recognizer.isAvailable else {
            throw RecognizerError.unavailable
        }

        // Reset state for a fresh session.
        latestTranscript = ""
        completionFired = false
        onFinal = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            throw RecognizerError.audioEngineFailed(error)
        }

        isRecording = true

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }
            if let result = result {
                self.latestTranscript = result.bestTranscription.formattedString
                if let onPartial = self.onPartial {
                    DispatchQueue.main.async { onPartial(self.latestTranscript) }
                }
                if result.isFinal { self.fireFinal() }
            }
            if error != nil { self.fireFinal() }
        }
    }

    /// Stops recording and delivers the finalized transcript on the main thread.
    func stopRecording(completion: @escaping (String) -> Void) {
        guard isRecording else {
            DispatchQueue.main.async { completion(self.latestTranscript) }
            return
        }
        isRecording = false
        onFinal = completion

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()

        // Safety net: if a final result never arrives, deliver the latest transcript.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            self?.fireFinal()
        }
    }

    /// Delivers the transcript exactly once, and only after `stopRecording` armed `onFinal`.
    private func fireFinal() {
        DispatchQueue.main.async {
            guard let handler = self.onFinal, !self.completionFired else { return }
            self.completionFired = true
            let text = self.latestTranscript
            self.cleanup()
            handler(text)
        }
    }

    private func cleanup() {
        task?.cancel()
        task = nil
        request = nil
        onFinal = nil
    }
}
