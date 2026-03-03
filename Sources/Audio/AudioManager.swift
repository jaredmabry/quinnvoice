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
    }

    // MARK: - Mic Capture

    func startCapture() throws {
        guard !isCapturing else { return }

        let inputNode = engine.inputNode
        let hardwareFormat = inputNode.outputFormat(forBus: 0)

        // We need 16kHz int16 mono for Gemini. Install a tap at the hardware format
        // and convert in the callback.
        let targetFormat = AudioBufferConverter.inputFormat

        // Create converter from hardware format to 16kHz int16 mono
        // Use a float32 intermediate for the tap since taps prefer float
        let tapFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: hardwareFormat.sampleRate,
            channels: 1,
            interleaved: false
        )!

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

        try engine.start()
        isCapturing = true
    }

    func stopCapture() {
        guard isCapturing else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isCapturing = false
    }

    // MARK: - Playback

    /// Schedule raw 16-bit PCM audio data (24kHz mono) for playback.
    func playAudioData(_ data: Data) {
        guard let buffer = AudioBufferConverter.int16DataToPlaybackBuffer(data) else {
            return
        }

        if !engine.isRunning {
            try? engine.start()
        }

        playerNode.scheduleBuffer(buffer)

        if !playerNode.isPlaying {
            playerNode.play()
        }
    }

    /// Stop any current playback immediately (barge-in support).
    func stopPlayback() {
        playerNode.stop()
    }

    /// Restart the engine if needed (e.g. after route change).
    func ensureEngineRunning() {
        if !engine.isRunning {
            try? engine.start()
        }
    }

    func teardown() {
        stopPlayback()
        stopCapture()
        engine.stop()
    }
}
