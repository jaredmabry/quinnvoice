import AVFoundation
import Foundation
import Speech

/// Always-on wake word detection using Apple's on-device speech recognition.
///
/// Listens continuously for a configurable wake phrase (default: "Hey Quinn") using
/// `SFSpeechRecognizer` with on-device processing. Employs Voice Activity Detection (VAD)
/// via audio energy thresholds to minimize CPU usage — speech recognition only runs
/// when audio energy exceeds the silence threshold.
///
/// - Important: Requires microphone and speech recognition permissions.
///   The recognizer uses `.onDeviceRecognition` to avoid cloud calls for wake word detection.
@MainActor
final class WakeWordDetector {

    // MARK: - Public Properties

    /// Called on the main thread when the wake phrase is detected.
    var onWakeWordDetected: (() -> Void)?

    /// Whether the detector is actively listening for the wake word.
    private(set) var isListening: Bool = false

    /// The phrase to listen for (case-insensitive matching).
    var wakePhrase: String = "Hey Quinn"

    // MARK: - Private Properties

    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    /// Minimum RMS energy level to trigger speech recognition processing.
    /// Audio below this threshold is considered silence and ignored.
    private let energyThreshold: Float = 0.015

    /// Cooldown period after wake word detection to prevent rapid re-triggers.
    private let cooldownInterval: TimeInterval = 3.0
    private var lastDetectionTime: Date = .distantPast

    /// Timer to periodically restart the recognition task (Apple limits continuous sessions).
    private var restartTimer: Timer?

    /// Maximum duration for a single recognition session before restart (in seconds).
    private let maxSessionDuration: TimeInterval = 30.0

    // MARK: - Init

    init() {
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }

    // MARK: - Public Methods

    /// Start listening for the wake word.
    ///
    /// Begins continuous audio capture and on-device speech recognition.
    /// When the wake phrase is detected in the recognized text, ``onWakeWordDetected`` is called.
    ///
    /// - Throws: If the audio engine fails to start or speech recognition is unavailable.
    func start() async throws {
        guard !isListening else { return }
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            print("[WakeWordDetector] Speech recognizer not available")
            return
        }

        // Request speech recognition authorization if needed
        let authStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        guard authStatus == .authorized else {
            print("[WakeWordDetector] Speech recognition not authorized: \(authStatus.rawValue)")
            return
        }

        isListening = true
        try startRecognitionSession()

        // Set up periodic restart to handle Apple's recognition session limits
        restartTimer = Timer.scheduledTimer(withTimeInterval: maxSessionDuration, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.restartRecognitionSession()
            }
        }
    }

    /// Stop listening for the wake word and release all audio resources.
    func stop() {
        guard isListening else { return }
        isListening = false

        restartTimer?.invalidate()
        restartTimer = nil

        stopRecognitionSession()
    }

    // MARK: - Private Methods

    private func startRecognitionSession() throws {
        guard let recognizer = speechRecognizer else { return }

        // Create a new recognition request configured for on-device processing
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        // We only need basic transcription for keyword matching
        if #available(macOS 14, *) {
            request.addsPunctuation = false
        }
        self.recognitionRequest = request

        // Install audio tap on the input node
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            guard let self else { return }

            // VAD: only feed audio to recognizer when energy exceeds threshold
            let level = self.computeRMSLevel(buffer: buffer)
            if level > self.energyThreshold {
                self.recognitionRequest?.append(buffer)
            }
        }

        audioEngine.prepare()
        try audioEngine.start()

        // Start recognition task
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }

                if let result {
                    let text = result.bestTranscription.formattedString.lowercased()
                    let phrase = self.wakePhrase.lowercased()

                    // Check if the wake phrase appears in the recognized text
                    if text.contains(phrase) {
                        let now = Date()
                        if now.timeIntervalSince(self.lastDetectionTime) > self.cooldownInterval {
                            self.lastDetectionTime = now
                            self.onWakeWordDetected?()
                            // Restart the session after detection to clear the buffer
                            self.restartRecognitionSession()
                        }
                    }
                }

                if let error {
                    // Only log non-cancellation errors
                    let nsError = error as NSError
                    if nsError.domain != "kAFAssistantErrorDomain" || nsError.code != 216 {
                        print("[WakeWordDetector] Recognition error: \(error.localizedDescription)")
                    }
                    // Restart if still listening
                    if self.isListening {
                        self.restartRecognitionSession()
                    }
                }
            }
        }
    }

    private func stopRecognitionSession() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil

        if audioEngine.isRunning {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        }
    }

    private func restartRecognitionSession() {
        stopRecognitionSession()
        guard isListening else { return }

        // Small delay before restarting to avoid rapid restarts
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard self.isListening else { return }
            try? self.startRecognitionSession()
        }
    }

    /// Compute the RMS energy level of an audio buffer for VAD.
    private nonisolated func computeRMSLevel(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }

        var sum: Float = 0
        let samples = channelData[0]
        for i in 0..<count {
            let sample = samples[i]
            sum += sample * sample
        }
        return sqrtf(sum / Float(count))
    }

    /// Request speech recognition permission and return whether it was granted.
    static func requestPermission() async -> Bool {
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        return status == .authorized
    }
}
