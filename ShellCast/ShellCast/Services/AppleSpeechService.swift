import Foundation
import Speech
import AVFoundation

@MainActor
final class AppleSpeechService {
    static let shared = AppleSpeechService()

    private let speechRecognizer = SFSpeechRecognizer()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private(set) var isRecording = false

    private init() {}

    func startRecording() throws {
        guard !isRecording else { return }

        SFSpeechRecognizer.requestAuthorization { _ in }

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = false

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }

        try audioEngine.start()
        isRecording = true
    }

    func stopAndTranscribe() async -> String {
        guard isRecording else { return "" }

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        isRecording = false

        defer {
            recognitionRequest = nil
            recognitionTask = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }

        guard let recognitionRequest, let speechRecognizer, speechRecognizer.isAvailable else { return "" }

        return await withCheckedContinuation { continuation in
            var didResume = false
            recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { result, error in
                guard !didResume else { return }
                if let result, result.isFinal {
                    didResume = true
                    continuation.resume(returning: result.bestTranscription.formattedString)
                } else if error != nil {
                    didResume = true
                    continuation.resume(returning: "")
                }
            }
        }
    }

    func cancelRecording() {
        guard isRecording else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
