import AVFoundation
import Foundation

/// Manages voice preview playback by creating a temporary Gemini Live session
/// to generate a short audio sample for a given voice.
@Observable
@MainActor
final class VoicePreviewManager {

    /// The voice name currently being previewed (nil if idle).
    var previewingVoice: String?

    /// Whether a preview is currently loading/playing.
    var isLoading: Bool = false

    /// Error message from last preview attempt.
    var errorMessage: String?

    private var previewSession: GeminiLiveSession?
    private var audioPlayer: AVAudioPlayer?
    private var collectedAudioData = Data()
    private var previewTask: Task<Void, Never>?

    /// The sample phrase used for voice preview.
    static let samplePhrase = "Hi, I'm Quinn. How can I help you today?"

    /// Preview a voice by sending a sample phrase to Gemini Live and playing the response audio.
    func previewVoice(name: String, apiKey: String) {
        // Cancel any existing preview
        cancelPreview()

        previewingVoice = name
        isLoading = true
        errorMessage = nil
        collectedAudioData = Data()

        previewTask = Task { @MainActor in
            do {
                let session = GeminiLiveSession(apiKey: apiKey)
                self.previewSession = session

                // Set up handler to collect audio data
                await session.setHandler { [weak self] event in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        switch event {
                        case .audioData(let data):
                            self.collectedAudioData.append(data)
                        case .turnComplete:
                            self.playCollectedAudio()
                        case .error(let message):
                            self.errorMessage = message
                            self.isLoading = false
                            self.previewingVoice = nil
                        case .setupComplete:
                            // Send a text message to trigger audio response
                            Task {
                                try? await session.sendText(Self.samplePhrase)
                            }
                        default:
                            break
                        }
                    }
                }

                let voiceConfig = VoiceConfig(name: name, pitch: 0, speed: 1.0)
                try await session.connect(
                    systemInstruction: "Say exactly: \"\(Self.samplePhrase)\" and nothing else. Do not add any extra words.",
                    voiceConfig: voiceConfig
                )

                // Timeout after 10 seconds
                try await Task.sleep(for: .seconds(10))
                if isLoading {
                    errorMessage = "Preview timed out"
                    isLoading = false
                    previewingVoice = nil
                    await session.disconnect()
                }
            } catch {
                if !Task.isCancelled {
                    errorMessage = error.localizedDescription
                    isLoading = false
                    previewingVoice = nil
                }
            }
        }
    }

    /// Cancel any in-progress preview.
    func cancelPreview() {
        previewTask?.cancel()
        previewTask = nil
        audioPlayer?.stop()
        audioPlayer = nil

        if let session = previewSession {
            Task {
                await session.disconnect()
            }
        }
        previewSession = nil
        isLoading = false
        previewingVoice = nil
        collectedAudioData = Data()
    }

    private func playCollectedAudio() {
        guard !collectedAudioData.isEmpty else {
            isLoading = false
            previewingVoice = nil
            return
        }

        // Gemini Live returns raw PCM 24kHz 16-bit mono audio — wrap in WAV header
        let wavData = createWAVData(from: collectedAudioData, sampleRate: 24000, channels: 1, bitsPerSample: 16)

        do {
            let player = try AVAudioPlayer(data: wavData)
            self.audioPlayer = player
            player.play()
            isLoading = false

            // Clean up after playback finishes
            Task {
                try? await Task.sleep(for: .seconds(Double(player.duration) + 0.5))
                self.previewingVoice = nil
                if let session = self.previewSession {
                    await session.disconnect()
                }
                self.previewSession = nil
            }
        } catch {
            errorMessage = "Playback failed: \(error.localizedDescription)"
            isLoading = false
            previewingVoice = nil
        }
    }

    /// Create a WAV file from raw PCM data.
    private func createWAVData(from pcmData: Data, sampleRate: Int, channels: Int, bitsPerSample: Int) -> Data {
        var data = Data()
        let byteRate = sampleRate * channels * bitsPerSample / 8
        let blockAlign = channels * bitsPerSample / 8
        let dataSize = pcmData.count
        let fileSize = 36 + dataSize

        // RIFF header
        data.append(contentsOf: "RIFF".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(fileSize).littleEndian) { Array($0) })
        data.append(contentsOf: "WAVE".utf8)

        // fmt chunk
        data.append(contentsOf: "fmt ".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) }) // PCM
        data.append(contentsOf: withUnsafeBytes(of: UInt16(channels).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(byteRate).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(blockAlign).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(bitsPerSample).littleEndian) { Array($0) })

        // data chunk
        data.append(contentsOf: "data".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(dataSize).littleEndian) { Array($0) })
        data.append(pcmData)

        return data
    }
}
