import Foundation

// MARK: - Noise Suppression Level

/// Intensity of noise suppression applied to microphone input.
enum NoiseSuppressionLevel: String, Codable, Sendable, CaseIterable {
    case low
    case medium
    case high

    /// Human-readable display name.
    var displayName: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }

    /// Description of the suppression behavior at this level.
    var description: String {
        switch self {
        case .low: return "Light filtering — preserves more ambient sound"
        case .medium: return "Balanced — good for most environments"
        case .high: return "Aggressive — best for noisy environments"
        }
    }

    /// The EQ attenuation factor used when applying noise suppression.
    /// Higher values mean more aggressive filtering of low-energy frequency bands.
    var attenuationFactor: Float {
        switch self {
        case .low: return 0.3
        case .medium: return 0.6
        case .high: return 0.9
        }
    }
}

// MARK: - Audio Processing Configuration

/// Configuration for audio input processing including noise suppression,
/// silence detection, voice activity detection, and echo cancellation.
struct AudioProcessingConfig: Codable, Sendable, Equatable {
    /// Whether noise suppression is enabled.
    var noiseSuppressionEnabled: Bool

    /// The intensity of noise suppression when enabled.
    var noiseSuppressionLevel: NoiseSuppressionLevel

    /// RMS threshold below which audio is considered silence (0.0–1.0).
    /// Audio frames with RMS below this value are not sent to Gemini.
    var silenceThreshold: Float

    /// Voice activity detection sensitivity (0.0–1.0).
    /// Lower values require louder speech to trigger; higher values are more sensitive.
    var vadSensitivity: Float

    /// Whether echo cancellation is enabled to reduce feedback from speaker output.
    var echoCancellation: Bool

    /// Default audio processing configuration with sensible defaults.
    static let `default` = AudioProcessingConfig(
        noiseSuppressionEnabled: true,
        noiseSuppressionLevel: .medium,
        silenceThreshold: 0.02,
        vadSensitivity: 0.5,
        echoCancellation: true
    )

    init(
        noiseSuppressionEnabled: Bool = true,
        noiseSuppressionLevel: NoiseSuppressionLevel = .medium,
        silenceThreshold: Float = 0.02,
        vadSensitivity: Float = 0.5,
        echoCancellation: Bool = true
    ) {
        self.noiseSuppressionEnabled = noiseSuppressionEnabled
        self.noiseSuppressionLevel = noiseSuppressionLevel
        self.silenceThreshold = silenceThreshold
        self.vadSensitivity = vadSensitivity
        self.echoCancellation = echoCancellation
    }
}
