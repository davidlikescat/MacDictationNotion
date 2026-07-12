import Foundation
import Speech
import AVFoundation
import MacDictationNotionCore

enum RecognizerError: LocalizedError {
    case unavailable
    case notAuthorized
    case audioEngineFailed(Error)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Speech recognition unavailable. The selected language may not be ready or no microphone is connected."
        case .notAuthorized:
            return "Microphone or speech recognition permission denied. Enable both in System Settings > Privacy & Security."
        case .audioEngineFailed(let error):
            return "Microphone failed to start: \(error.localizedDescription)"
        }
    }
}

final class SpeechRecognizer: SpeechRecognizing {
    private let recognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    private(set) var isRecording = false
    private var latestTranscript = ""
    private var onFinal: ((String) -> Void)?
    private var completionFired = false

    var onPartial: ((String) -> Void)?
    var onAudioLevel: ((Float) -> Void)?

    init(localeIdentifier: String) {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier))
    }

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

        latestTranscript = ""
        completionFired = false
        onFinal = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Do NOT force requiresOnDeviceRecognition.
        // On-device mode fires isFinal on every pause, breaking multi-sentence sessions.
        // Server-based recognition accumulates the full session into formattedString
        // across pauses naturally, which is what we want.
        self.request = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
            self?.emitAudioLevel(from: buffer)
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
                let text = result.bestTranscription.formattedString
                // Server STT occasionally delivers empty string on isFinal — keep last good value.
                if !text.isEmpty { self.latestTranscript = text }
                DispatchQueue.main.async { self.onPartial?(self.latestTranscript) }
                if result.isFinal { self.fireFinal() }
            }
            if error != nil { self.fireFinal() }
        }
    }

    func cancelRecording() {
        guard isRecording else { return }
        isRecording = false
        completionFired = true
        onFinal = nil
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel(); task = nil
        request = nil
    }

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

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            self?.fireFinal()
        }
    }

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
        task?.cancel(); task = nil
        request = nil; onFinal = nil
    }

    private func emitAudioLevel(from buffer: AVAudioPCMBuffer) {
        guard let data = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }
        let sumSq = (0..<frameCount).reduce(Float(0)) { $0 + data[$1] * data[$1] }
        let rms = sqrt(sumSq / Float(frameCount))
        let db = 20.0 * log10(rms + 1e-9)
        let normalized = Float(max(0.0, min(1.0, (Double(db) + 50.0) / 50.0)))
        DispatchQueue.main.async { [weak self] in
            self?.onAudioLevel?(normalized)
        }
    }
}
