import Foundation
import WhisperKit
import AVFoundation

@MainActor
final class WhisperService {
    static let shared = WhisperService()

    private var whisperKit: WhisperKit?
    private var loadedModelName: String?
    private var audioRecorder: AVAudioRecorder?
    private(set) var isRecording = false
    private(set) var isModelLoaded = false
    private(set) var isLoadingModel = false

    private var recordingURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("whisper_recording.wav")
    }

    /// Called with status text updates during model loading (e.g. "Downloading 45%", "Loading model...")
    var onStatusUpdate: ((String) -> Void)?

    private var progressObservation: NSKeyValueObservation?

    private init() {}

    /// Load a model. Downloads on first use, then caches locally.
    func loadModel(_ model: WhisperModel? = nil) async throws {
        let target = model ?? TerminalSettings.shared.whisperModel

        if isModelLoaded && loadedModelName == target.rawValue { return }
        guard !isLoadingModel else { return }

        isLoadingModel = true
        isModelLoaded = false
        defer { isLoadingModel = false }

        // Check if model was previously downloaded to our cache
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("WhisperModels")
        let cachedModelPath = cacheDir.appendingPathComponent(target.rawValue)

        if FileManager.default.fileExists(atPath: cachedModelPath.path) {
            // Use cached model
            onStatusUpdate?("Loading \(target.displayName)...")
            let kit = try await WhisperKit(
                modelFolder: cachedModelPath.path,
                verbose: false,
                load: true,
                download: false
            )
            whisperKit = kit
            loadedModelName = target.rawValue
            isModelLoaded = true
            onStatusUpdate?("Ready")
            return
        }

        // Download model from HuggingFace (WhisperKit handles caching)
        onStatusUpdate?("Downloading \(target.displayName)...")

        let kit = try await WhisperKit(
            model: target.whisperKitVariant,
            verbose: false,
            load: true,
            download: true
        )

        whisperKit = kit
        loadedModelName = target.rawValue
        isModelLoaded = true
        onStatusUpdate?("Ready")
    }

    /// Start recording audio from the microphone.
    func startRecording() throws {
        guard !isRecording else { return }

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        // Record as 16kHz mono WAV - what Whisper expects
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]

        // Remove old recording if exists
        try? FileManager.default.removeItem(at: recordingURL)

        audioRecorder = try AVAudioRecorder(url: recordingURL, settings: settings)
        audioRecorder?.record()
        isRecording = true
    }

    /// Stop recording and transcribe the captured audio.
    /// Returns transcribed text, or a debug message starting with "[debug]" if something went wrong.
    func stopAndTranscribe() async -> String {
        guard isRecording, let recorder = audioRecorder else { return "[debug] not recording" }

        recorder.stop()
        audioRecorder = nil
        isRecording = false

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        guard let whisperKit else { return "[debug] no whisperKit" }

        let path = recordingURL.path
        guard FileManager.default.fileExists(atPath: path) else { return "[debug] no file" }

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
        guard fileSize > 100 else { return "[debug] file too small: \(fileSize) bytes" }

        // Load audio as float array using WhisperKit's AudioProcessor
        let audioArray: [Float]
        do {
            audioArray = try AudioProcessor.loadAudioAsFloatArray(fromPath: path)
        } catch {
            return "[debug] loadAudio failed: \(error.localizedDescription)"
        }

        guard !audioArray.isEmpty else { return "[debug] empty audio array" }

        let duration = Float(audioArray.count) / 16000.0

        // Transcribe
        let results = await whisperKit.transcribe(audioArrays: [audioArray])

        // Clean up
        try? FileManager.default.removeItem(at: recordingURL)

        guard let firstResult = results.first, let transcriptions = firstResult else {
            return "[debug] no results, audio \(duration)s, \(audioArray.count) samples"
        }

        let text = transcriptions.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "[debug] empty text, audio \(duration)s" : text
    }

    /// Cancel recording without transcribing.
    func cancelRecording() {
        guard isRecording else { return }

        audioRecorder?.stop()
        audioRecorder = nil
        isRecording = false

        try? FileManager.default.removeItem(at: recordingURL)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
