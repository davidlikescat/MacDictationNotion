import Foundation

public protocol SpeechRecognizing: AnyObject {
    var onPartial: ((String) -> Void)? { get set }
    var onAudioLevel: ((Float) -> Void)? { get set }
    var isRecording: Bool { get }
    func startRecording() throws
    func stopRecording(completion: @escaping (String) -> Void)
    func cancelRecording()
}
