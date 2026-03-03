import AVFoundation
import Foundation

/// Manages mic capture and speaker playback via AVAudioEngine.
@MainActor
final class AudioManager: Sendable {

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()

    /// Called on the audio thread with raw 16-bit PCM data at 16kHz mono.
    var onMicData: (@Sendable (Data) -> Void)?

    /// Called on the main thread with mic RMS level (0…1).
    var onMicLevel: (@Sendable @MainActor (Float) -> Void)?

    /// Whether the player is currently playing audio.
    var isPlaying: Bool {
        playerNode.isPlaying
    }

    private var isCapturing = false

    init() {
        engine.attach(playerNode)

        // Connect player node → main mixer at 24kHz float32 (Gemini output format)
        let playbackFormat = AudioBufferConverter.outputFloatFormat
        engine.connect(playerNode, to: engine.mainMixerNode, format: playbackFormat)
        print("[AudioManager] Initialized — playerNode connected at \(playbackFormat)")
    }

    // MARK: - Mic Capture

    func startCapture() throws {
        guard !isCapturing else { return }

        let inputNode = engine.inputNode
        let hardwareFormat = inputNode.outputFormat(forBus: 0)
        print("[AudioManager] Hardware mic format: \(hardwareFormat)")

        guard hardwareFormat.sampleRate > 0 else {
            print("[AudioManager] ERROR: Hardware sample rate is 0 — no mic available")
            throw AudioError.noMicrophone
        }

        // Use float32 intermediate for the tap since taps prefer float
        let tapFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: hardwareFormat.sampleRate,
            channels: 1,
            interleaved: false
        )!

        // We need 16kHz int16 mono for Gemini
        let targetFormat = AudioBufferConverter.inputFormat

        inputNode.installTap(onBus: 0, bufferSize: 1600, format: tapFormat) { [weak self] buffer, _ in
            guard let self else { return }

            // Compute level for visualization
            let level = AudioBufferConverter.rmsLevel(of: buffer)
            Task { @MainActor in
                self.onMicLevel?(level)
            }

            // Convert to 16kHz int16 for Gemini
            guard let converted = AudioBufferConverter.convert(buffer: buffer, to: targetFormat),
                  let data = AudioBufferConverter.bufferToInt16Data(converted) else {
                return
            }

            self.onMicData?(data)
        }

        // Prepare and start the engine (needed for both capture and playback)
        engine.prepare()
        try engine.start()
        isCapturing = true
        print("[AudioManager] Capture started — engine running: \(engine.isRunning)")
    }

    func stopCapture() {
        guard isCapturing else { return }
        engine.inputNode.removeTap(onBus: 0)
        // Don't stop the engine — playerNode may still need it for playback
        isCapturing = false
        print("[AudioManager] Capture stopped (engine still running for playback)")
    }

    // MARK: - Playback

    /// Schedule raw 16-bit PCM audio data (24kHz mono) for playback.
    func playAudioData(_ data: Data) {
        guard let buffer = AudioBufferConverter.int16DataToPlaybackBuffer(data) else {
            print("[AudioManager] WARNING: Failed to convert \(data.count) bytes to playback buffer")
            return
        }

        if !engine.isRunning {
            print("[AudioManager] Engine not running for playback — starting")
            engine.prepare()
            try? engine.start()
        }

        playerNode.scheduleBuffer(buffer)

        if !playerNode.isPlaying {
            playerNode.play()
            print("[AudioManager] PlayerNode started — buffer frames: \(buffer.frameLength)")
        }
    }

    /// Stop any current playback immediately (barge-in support).
    func stopPlayback() {
        playerNode.stop()
    }

    /// Restart the engine if needed (e.g. after route change).
    func ensureEngineRunning() {
        if !engine.isRunning {
            engine.prepare()
            try? engine.start()
        }
    }

    func teardown() {
        stopPlayback()
        stopCapture()
        engine.stop()
        print("[AudioManager] Teardown complete")
    }

    // MARK: - Errors

    enum AudioError: LocalizedError {
        case noMicrophone

        var errorDescription: String? {
            switch self {
            case .noMicrophone: return "No microphone available"
            }
        }
    }
}
