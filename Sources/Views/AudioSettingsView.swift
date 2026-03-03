import SwiftUI
import AVFoundation

/// Settings view for audio input processing configuration.
///
/// Provides controls for noise suppression, silence threshold, voice activity detection,
/// echo cancellation, and a live microphone level meter for testing.
struct AudioSettingsView: View {
    @Bindable var configManager: ConfigManager
    @State private var isTesting = false
    @State private var currentMicLevel: Float = 0
    @State private var testTimer: Timer?
    @State private var testEngine: AVAudioEngine?
    @State private var testCountdown: Int = 5

    private var audioConfig: Binding<AudioProcessingConfig> {
        $configManager.config.audioProcessing
    }

    var body: some View {
        Form {
            // Noise Suppression
            Section {
                Toggle("Noise Suppression", isOn: audioConfig.noiseSuppressionEnabled)

                if configManager.config.audioProcessing.noiseSuppressionEnabled {
                    Picker("Suppression Level", selection: audioConfig.noiseSuppressionLevel) {
                        ForEach(NoiseSuppressionLevel.allCases, id: \.self) { level in
                            VStack(alignment: .leading) {
                                Text(level.displayName)
                            }
                            .tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            } header: {
                Text("Noise Suppression")
            } footer: {
                Text("Reduces background noise from your microphone before sending audio to Gemini. Higher levels filter more aggressively but may affect voice quality.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Silence Threshold
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Silence Threshold")
                        Spacer()
                        Text(String(format: "%.3f", configManager.config.audioProcessing.silenceThreshold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }

                    Slider(
                        value: audioConfig.silenceThreshold,
                        in: 0.0...0.1,
                        step: 0.005
                    )

                    // Level indicator showing current mic level vs threshold
                    if isTesting {
                        MicLevelIndicator(
                            currentLevel: currentMicLevel,
                            threshold: configManager.config.audioProcessing.silenceThreshold
                        )
                        .frame(height: 20)
                    }
                }
            } header: {
                Text("Silence Detection")
            } footer: {
                Text("Audio below this RMS level is treated as silence and not sent to Gemini. Increase to filter more ambient noise; decrease for sensitive environments.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // VAD Sensitivity
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Less Sensitive")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("More Sensitive")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Slider(
                        value: audioConfig.vadSensitivity,
                        in: 0.0...1.0,
                        step: 0.05
                    )

                    Text("Current: \(String(format: "%.0f%%", configManager.config.audioProcessing.vadSensitivity * 100))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            } header: {
                Text("Voice Activity Detection")
            } footer: {
                Text("Controls how sensitive the voice detection is. Lower values require louder speech to register; higher values pick up quieter speech.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Echo Cancellation
            Section {
                Toggle("Echo Cancellation", isOn: audioConfig.echoCancellation)
            } header: {
                Text("Echo Cancellation")
            } footer: {
                Text("Reduces audio feedback from Quinn's speech being picked up by your microphone. Recommended when not using headphones.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Test Microphone
            Section {
                Button {
                    if isTesting {
                        stopMicTest()
                    } else {
                        startMicTest()
                    }
                } label: {
                    HStack {
                        Image(systemName: isTesting ? "mic.fill" : "mic")
                            .foregroundStyle(isTesting ? .red : .secondary)
                        Text(isTesting ? "Testing… (\(testCountdown)s)" : "Test Microphone")
                        if isTesting {
                            Spacer()
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }

                if isTesting {
                    MicLevelIndicator(
                        currentLevel: currentMicLevel,
                        threshold: configManager.config.audioProcessing.silenceThreshold
                    )
                    .frame(height: 24)
                    .animation(.linear(duration: 0.05), value: currentMicLevel)
                }
            } header: {
                Text("Microphone Test")
            } footer: {
                Text("Start a 5-second mic capture to see your current audio levels and verify your threshold settings are working correctly.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onChange(of: configManager.config.audioProcessing) { _, _ in
            configManager.save()
        }
        .onDisappear {
            stopMicTest()
        }
    }

    // MARK: - Mic Test

    private func startMicTest() {
        isTesting = true
        testCountdown = 5
        currentMicLevel = 0

        // Check microphone permission first
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            break
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                Task { @MainActor in
                    if granted {
                        self.startMicTest()
                    } else {
                        self.isTesting = false
                    }
                }
            }
            return
        default:
            isTesting = false
            return
        }

        do {
            let engine = AVAudioEngine()

            // Prepare the engine first to avoid crashes on inputNode access
            engine.prepare()

            let inputNode = engine.inputNode
            let hardwareFormat = inputNode.outputFormat(forBus: 0)

            guard hardwareFormat.sampleRate > 0 else {
                isTesting = false
                return
            }

            let tapFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: hardwareFormat.sampleRate,
                channels: 1,
                interleaved: false
            )!

            inputNode.installTap(onBus: 0, bufferSize: 1600, format: tapFormat) { buffer, _ in
                let level = AudioBufferConverter.rmsLevel(of: buffer)
                Task { @MainActor in
                    self.currentMicLevel = level
                }
            }

            try engine.start()
            testEngine = engine

            // Countdown timer
            testTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                Task { @MainActor in
                    testCountdown -= 1
                    if testCountdown <= 0 {
                        stopMicTest()
                    }
                }
            }
        } catch {
            isTesting = false
            testEngine = nil
        }
    }

    private func stopMicTest() {
        testTimer?.invalidate()
        testTimer = nil

        if let engine = testEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        testEngine = nil
        isTesting = false
        currentMicLevel = 0
    }
}

// MARK: - Mic Level Indicator

/// A horizontal bar showing the current microphone RMS level with a threshold marker.
struct MicLevelIndicator: View {
    let currentLevel: Float
    let threshold: Float

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.15))

                // Current level bar
                RoundedRectangle(cornerRadius: 4)
                    .fill(levelColor)
                    .frame(width: max(0, geometry.size.width * CGFloat(min(currentLevel, 1.0))))

                // Threshold marker
                Rectangle()
                    .fill(Color.orange)
                    .frame(width: 2)
                    .offset(x: geometry.size.width * CGFloat(min(threshold, 1.0)))

                // Labels
                HStack {
                    Text(String(format: "%.3f", currentLevel))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        .padding(.leading, 4)
                    Spacer()
                    Text(currentLevel > threshold ? "Voice" : "Silence")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(currentLevel > threshold ? .green : .secondary)
                        .padding(.trailing, 4)
                }
            }
        }
    }

    private var levelColor: Color {
        if currentLevel > threshold {
            return .green.opacity(0.6)
        }
        return .red.opacity(0.3)
    }
}
