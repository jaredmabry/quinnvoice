import Foundation

/// Voice configuration for Gemini Live API.
struct VoiceConfig: Codable, Sendable {
    var name: String
    var pitch: Double
    var speed: Double

    static let `default` = VoiceConfig(name: "Kore", pitch: 0, speed: 1.0)

    /// Available Gemini Live voices.
    static let availableVoices = [
        "Aoede", "Charon", "Fenrir", "Kore", "Leda",
        "Orus", "Puck", "Zephyr"
    ]
}
